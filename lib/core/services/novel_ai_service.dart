import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import '../gateway/backend_exception.dart';
import '../gateway/backend_gateway.dart';
import '../gateway/backend_rules.dart';
import '../gateway/image_quote.dart';
import '../../features/generation/models/generation_quote.dart';
import '../../features/generation/models/nai_character.dart';
import '../../features/generation/services/gateway_task_watcher.dart';
import 'backend_client.dart';
import 'backend_history_api.dart';

/// Strips backslashes from a prompt before it reaches the NovelAI API.
/// NovelAI prompts have no use for `\` (it's not an escape or weighting
/// character in their syntax), and stray backslashes — usually pasted in by
/// accident from other tooling — only pollute the prompt. Done here, at the
/// single API chokepoint, so every path (txt2img, img2img, characters) is
/// covered. Returns an empty string for null input.
String sanitizePromptForNai(String? prompt) =>
    (prompt ?? '').replaceAll('\\', '');

/// Result of an image generation
class GenerationResult {
  final Uint8List imageBytes;
  final Map<String, dynamic> metadata;

  GenerationResult({required this.imageBytes, required this.metadata});
}

class ImageGenerationRequest {
  final Map<String, dynamic> body;
  final Map<String, dynamic> metadata;

  const ImageGenerationRequest({required this.body, required this.metadata});
}

class GatewayGenerationItem {
  final String id;
  final int batchIndex;
  final String status;

  const GatewayGenerationItem({
    required this.id,
    required this.batchIndex,
    required this.status,
  });
}

class GatewayGenerationSubmission {
  final String taskId;
  final List<GatewayGenerationItem> items;

  const GatewayGenerationSubmission({
    required this.taskId,
    required this.items,
  });
}

/// The user declined the gateway's price.
class QuoteDeclinedException implements Exception {
  const QuoteDeclinedException();
}

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException([this.message = 'Unauthorized']);
}

/// Service to interact with the NovelAI Image Generation API (V5).
class NovelAIService {
  static const String v5CuratedModel = 'nai-diffusion-5-curated';
  static const String v5FullModel = 'nai-diffusion-5-full';
  static const String v5FullInpaintingModel = 'nai-diffusion-5-full-inpainting';

  // NovelAI V5 does not yet provide Curated inpainting, Vibe Transfer or
  // Precise Reference. These are the same compatibility models currently used
  // by novelai.net (see [imageModelFor]).
  static const String v4_5CuratedInpaintingModel =
      'nai-diffusion-4-5-curated-inpainting';
  static const String v4_5FullInpaintingModel =
      'nai-diffusion-4-5-full-inpainting';
  static const String v4_5CuratedModel = 'nai-diffusion-4-5-curated';
  static const String v4_5FullModel = 'nai-diffusion-4-5-full';

  /// The model for an image request, as novelai.net routes it (the gateway
  /// applies the same rule, docs/GATEWAY_CONTRACT.md §3). [references] means
  /// vibes or Precise Reference images, which V5 does not support yet: those
  /// requests stay on the V4.5 model their vibes were encoded with
  /// ([encodeVibeImage]).
  static String imageModelFor({
    required String action,
    required bool curated,
    required bool references,
  }) {
    if (action == 'infill') {
      if (curated) return v4_5CuratedInpaintingModel;
      return references ? v4_5FullInpaintingModel : v5FullInpaintingModel;
    }
    if (references) return curated ? v4_5CuratedModel : v4_5FullModel;
    return curated ? v5CuratedModel : v5FullModel;
  }

  final Dio _dio = Dio();
  final String _apiKey;
  final BackendClient _client;
  final bool _gateway;

  /// Waits between the resends of a submission whose response never arrived;
  /// its length is the number of resends.
  final List<Duration> submitRetryDelays;

  /// Requests go through the gateway, which prices and queues them.
  bool get viaGateway => _gateway;

  /// The signed-in user's image rules (fetched when not known yet).
  Future<ImageRules> loadImageRules() => _client.requireImageRules();

  /// Maximum output dimension (px) the NAI upscale endpoint accepts.
  static const int maxUpscaleOutputPixels = 4096;

  /// Returns the largest viable scale factor (4, 2) for the given input
  /// dimensions, or `null` if even 2x would exceed the output limit.
  static int? bestUpscaleScale(int width, int height) {
    for (final s in [4, 2]) {
      if (width * s <= maxUpscaleOutputPixels &&
          height * s <= maxUpscaleOutputPixels) {
        return s;
      }
    }
    return null;
  }

  NovelAIService(
    this._apiKey, {
    BackendClient? client,
    bool? gateway,
    this.submitRetryDelays = const [Duration(seconds: 1), Duration(seconds: 2)],
  }) : _client = client ?? BackendClient.shared,
       _gateway = gateway ?? useBackendGateway {
    _dio.options.connectTimeout = const Duration(seconds: 60);
    _dio.options.receiveTimeout = const Duration(minutes: 5);
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestHeader: false,
          requestBody: false, // Don't log base64 image data
          responseHeader: true,
          responseBody: false, // Don't log bytes
        ),
      );
    }
  }

  String _imageUrl(String path) => 'https://image.novelai.net$path';

  String _apiUrl(String path) => 'https://api.novelai.net$path';

  Map<String, String> _headers({bool json = true}) => {
    'Authorization': 'Bearer $_apiKey',
    if (json) 'Content-Type': 'application/json',
  };

  /// Sends one paid-tool POST through the gateway, which prices it from
  /// `rules.tool_caps` (docs/GATEWAY_CONTRACT.md §5). It is sent exactly once
  /// per user action, under a fresh `Idempotency-Key`: a repeat would be
  /// charged again.
  Future<List<int>> _postPaidTool(
    String path,
    Map<String, dynamic> body,
    int Function(ToolCaps caps) cap,
  ) async {
    final rules = await _client.requireImageRules();
    try {
      final response = await _client.post<List<int>>(
        novelAiProxyPath('image', path),
        data: body,
        options: BackendClient.longRunning(
          responseType: ResponseType.bytes,
          headers: {
            'Idempotency-Key': newClientRequestId(),
            'X-NAIWeaver-Expected-Points': '${cap(rules.toolCaps)}',
          },
        ),
      );
      return response.data ?? const <int>[];
    } on QuoteChangedException {
      // The cached prices are stale; the next call reloads them.
      _client.imageRules = null;
      rethrow;
    }
  }

  /// GET with automatic retry on connection/timeout errors.
  Future<Response<dynamic>> _getWithRetry(
    String url, {
    Options? options,
  }) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        return await _dio.get(url, options: options);
      } on DioException catch (e) {
        final retryable =
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout;
        if (!retryable || attempt >= 2) rethrow;
        debugPrint('NovelAIService: Retry ${attempt + 1} for $url');
        await Future.delayed(Duration(seconds: (attempt + 1) * 2));
      }
    }
    throw StateError('Unreachable');
  }

  /// Waits for the only image of [submission] and returns it. The job itself
  /// lives on the server, so closing or refreshing the client cannot discard
  /// it.
  Future<Uint8List> _awaitGatewayImage(
    GatewayGenerationSubmission submission,
  ) async {
    final id = submission.items.single.id;
    Uint8List? image;
    Object? failure;
    await GatewayTaskWatcher(api: BackendHistoryApi(client: _client)).watch(
      taskId: submission.taskId,
      itemIds: {id},
      token: GatewayWatchToken(),
      onItem: (item) {
        if (item.status == 'failed' ||
            item.status == 'rejected' ||
            item.status == 'cancelled') {
          failure = BackendException(
            statusCode: null,
            code: item.errorCode ?? BackendErrorCode.internalError,
          );
        }
      },
      onImage: (item, bytes) => image = bytes,
      onImageFailed: (item, error) => failure = error,
    );
    final bytes = image;
    if (bytes != null) return bytes;
    throw failure ??
        const BackendException(
          statusCode: null,
          code: BackendErrorCode.internalError,
        );
  }

  /// Encodes an image into a vibe vector via the NAI encode-vibe endpoint.
  ///
  /// Returns the raw binary vibe vector which must be base64-encoded before
  /// passing to `reference_image_multiple` in the generate call. Through the
  /// gateway this is a paid call, sent once.
  Future<Uint8List> encodeVibeImage({
    required String imageBase64,
    double informationExtracted = 1.0,
    bool useCurated = false,
  }) async {
    final body = {
      "image": imageBase64,
      // Vibe Transfer is not available for V5 yet, so encoding remains on
      // the matching V4.5 model until NovelAI exposes V5 support.
      "model": useCurated ? v4_5CuratedModel : v4_5FullModel,
      "information_extracted": informationExtracted,
    };

    if (_gateway) {
      return Uint8List.fromList(
        await _postPaidTool('/ai/encode-vibe', body, (caps) => caps.encodeVibe),
      );
    }
    try {
      final response = await _dio.post(
        _imageUrl('/ai/encode-vibe'),
        data: body,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {..._headers()},
        ),
      );
      return Uint8List.fromList(response.data as List<int>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw UnauthorizedException();
      }
      debugPrint('NovelAIService: Encode-vibe error: ${e.message}');
      rethrow;
    }
  }

  /// Fetches the user's Anlas balance from the NovelAI user data API.
  /// Returns null on failure (no API key, network error).
  Future<int?> getAnlasBalance() async {
    if (_gateway || _apiKey.isEmpty) return null;
    try {
      final response = await _getWithRetry(
        _apiUrl('/user/subscription'),
        options: Options(headers: _headers(json: false)),
      );
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final steps = data['trainingStepsLeft'];
        if (steps is int) return steps;
        if (steps is Map<String, dynamic>) {
          final fixed = steps['fixedTrainingStepsLeft'] as int? ?? 0;
          final purchased = steps['purchasedTrainingSteps'] as int? ?? 0;
          return fixed + purchased;
        }
      }
    } catch (e) {
      debugPrint('NovelAIService: Anlas fetch error: $e');
    }
    return null;
  }

  /// Builds the exact NovelAI payload used by both direct generation and the
  /// gateway's atomic batch endpoint.
  ImageGenerationRequest buildImageGenerationRequest({
    required String prompt,
    required int width,
    required int height,
    required int seed,
    int steps = 28,
    double scale = 6.0,
    String sampler = "k_euler_ancestral",
    String? negativePrompt,
    bool smea = false,
    bool smeaDyn = false,
    bool decrisper = false,
    String? promptPrefix,
    String? promptSuffix,
    List<NaiCharacter> characters = const [],
    List<NaiInteraction> interactions = const [],
    String action = 'generate',
    String? sourceImageBase64,
    String? maskBase64,
    double? img2imgStrength,
    double? img2imgNoise,
    bool? img2imgColorCorrect,
    int? maskBlur,
    List<String>? directorRefImages,
    List<Map<String, dynamic>>? directorRefDescriptions,
    List<double>? directorRefStrengths,
    List<double>? directorRefSecondaryStrengths,
    List<double>? directorRefInfoExtracted,
    List<String>? vibeTransferImages,
    List<double>? vibeTransferStrengths,
    List<double>? vibeTransferInfoExtracted,
    bool? useCoords,
    bool useCurated = false,
  }) {
    final inputPrompt = sanitizePromptForNai(
      "${promptPrefix ?? ''}$prompt${promptSuffix ?? ''}",
    );
    final effectiveNegativePrompt = sanitizePromptForNai(negativePrompt);
    final isMultiCharacter = characters.isNotEmpty;

    final charCaptions = <Map<String, dynamic>>[];
    for (var i = 0; i < characters.length; i++) {
      final character = characters[i];
      var caption = character.prompt;
      for (final interaction in interactions) {
        if (interaction.type == InteractionType.mutual) {
          if (interaction.sourceCharacterIndices.contains(i)) {
            caption = "mutual#${interaction.actionName}, $caption";
          }
        } else if (interaction.sourceCharacterIndices.contains(i)) {
          caption = "source#${interaction.actionName}, $caption";
        } else if (interaction.targetCharacterIndices.contains(i)) {
          caption = "target#${interaction.actionName}, $caption";
        }
      }
      charCaptions.add({
        'char_caption': sanitizePromptForNai(caption),
        'centers': [character.center.toJson()],
      });
    }

    final parameters = <String, dynamic>{
      "params_version": 4,
      "width": width,
      "height": height,
      "scale": scale,
      "sampler": sampler,
      "steps": steps,
      "seed": seed,
      "n_samples": 1,
      "noise_schedule": "karras",
      "sm": smea,
      "sm_dyn": smeaDyn,
      "dynamic_thresholding": decrisper,
      "uc": effectiveNegativePrompt,
      if (isMultiCharacter)
        "characterPrompts": charCaptions.map((caption) {
          return {
            'prompt': caption['char_caption'],
            'center': (caption['centers'] as List).isNotEmpty
                ? (caption['centers'] as List).first
                : {'x': 0.5, 'y': 0.5},
          };
        }).toList(),
      "v4_prompt": {
        "caption": {"base_caption": inputPrompt, "char_captions": charCaptions},
        "use_coords": useCoords ?? isMultiCharacter,
        "use_order": true,
      },
      "v4_negative_prompt": {
        "caption": {
          "base_caption": effectiveNegativePrompt,
          "char_captions": characters.map((character) {
            final negative = character.toV4NegativePrompt();
            final caption = negative['char_caption'];
            if (caption is String) {
              negative['char_caption'] = sanitizePromptForNai(caption);
            }
            return negative;
          }).toList(),
        },
      },
      if (action != 'generate' && sourceImageBase64 != null)
        "image": sourceImageBase64,
      if (action != 'generate' && maskBase64 != null) "mask": maskBase64,
      if (action != 'generate' && img2imgStrength != null)
        "strength": img2imgStrength,
      if (action == 'img2img' && img2imgNoise != null) "noise": img2imgNoise,
      if (action == 'img2img') "extra_noise_seed": seed,
      if (action != 'generate') "add_original_image": true,
      if (action == 'infill' && maskBlur != null) "mask_blur": maskBlur,
      if (directorRefImages != null && directorRefImages.isNotEmpty)
        "director_reference_images": directorRefImages,
      if (directorRefDescriptions != null && directorRefDescriptions.isNotEmpty)
        "director_reference_descriptions": directorRefDescriptions,
      if (directorRefStrengths != null && directorRefStrengths.isNotEmpty)
        "director_reference_strength_values": directorRefStrengths,
      if (directorRefSecondaryStrengths != null &&
          directorRefSecondaryStrengths.isNotEmpty)
        "director_reference_secondary_strength_values":
            directorRefSecondaryStrengths,
      if (directorRefInfoExtracted != null &&
          directorRefInfoExtracted.isNotEmpty)
        "director_reference_information_extracted": directorRefInfoExtracted,
      if (vibeTransferImages != null && vibeTransferImages.isNotEmpty)
        "reference_image_multiple": vibeTransferImages,
      if (vibeTransferStrengths != null && vibeTransferStrengths.isNotEmpty)
        "reference_strength_multiple": vibeTransferStrengths,
      if (vibeTransferInfoExtracted != null &&
          vibeTransferInfoExtracted.isNotEmpty)
        "reference_information_extracted_multiple": vibeTransferInfoExtracted,
    };

    final body = <String, dynamic>{
      "input": inputPrompt,
      "model": imageModelFor(
        action: action,
        curated: useCurated,
        references:
            (vibeTransferImages?.isNotEmpty ?? false) ||
            (directorRefImages?.isNotEmpty ?? false),
      ),
      "action": action,
      "parameters": parameters,
    };
    return ImageGenerationRequest(
      body: body,
      metadata: {
        "prompt": inputPrompt,
        "original_prompt": prompt,
        "uc": effectiveNegativePrompt,
        "undesired_content": effectiveNegativePrompt,
        "model": body["model"],
        "action": action,
        ...parameters,
      },
    );
  }

  Future<GatewayGenerationSubmission> submitGatewayGenerationBatch({
    required ImageGenerationRequest request,
    required List<int> seeds,
    required String clientRequestId,
    required Map<String, dynamic> expectedQuote,
  }) async {
    final body = {
      'client_request_id': clientRequestId,
      'request': request.body,
      'seeds': seeds,
      'expected_quote': expectedQuote,
    };
    // The POST may have reached the gateway (points reserved, task queued)
    // with only the response lost. The gateway answers a repeated
    // `client_request_id` with the original submission, so the same body is
    // resent a bounded number of times; it can not be charged twice. A 502 or
    // 504 comes from the reverse proxy (this endpoint only queues, it never
    // calls NovelAI), so it counts as a lost response too. Any other answer
    // from the gateway is final and never resent.
    BackendException? lost;
    Response<dynamic>? response;
    for (var attempt = 0; response == null; attempt++) {
      try {
        response = await _client.post<dynamic>(
          '/api/generation-tasks',
          data: body,
        );
      } on BackendException catch (error) {
        final lostResponse = error.statusCode == null
            ? error.isNetworkError
            : error.statusCode == 502 || error.statusCode == 504;
        if (!lostResponse) rethrow;
        lost = error;
        if (attempt >= submitRetryDelays.length) break;
        await Future<void>.delayed(submitRetryDelays[attempt]);
      }
    }
    if (response == null) {
      // Still no answer: the submission may exist anyway.
      final found = await _findLostSubmission(seeds);
      if (found != null) return found;
      throw lost!;
    }
    final data = response.data;
    const invalid = BackendException(
      statusCode: null,
      code: BackendErrorCode.invalidResponse,
    );
    if (response.statusCode != 202 || data is! Map<String, dynamic>) {
      throw invalid;
    }
    final taskId = data['task_id'] as String? ?? '';
    final rawItems = data['items'] as List<dynamic>? ?? const [];
    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => GatewayGenerationItem(
            id: item['id'] as String? ?? '',
            batchIndex: (item['batch_index'] as num?)?.toInt() ?? 0,
            status: item['status'] as String? ?? 'queued',
          ),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    if (taskId.isEmpty || items.length != seeds.length) throw invalid;
    return GatewayGenerationSubmission(taskId: taskId, items: items);
  }

  /// The submission of this account's current task when it holds exactly
  /// [seeds] (random seeds make that a reliable match), or null. Used after a
  /// submit whose response was lost.
  Future<GatewayGenerationSubmission?> _findLostSubmission(
    List<int> seeds,
  ) async {
    try {
      final task = await BackendHistoryApi(client: _client).fetchCurrentTask();
      if (task == null ||
          task.id.isEmpty ||
          task.items.length != seeds.length) {
        return null;
      }
      final items = task.items.toList()
        ..sort((a, b) => (a.batchIndex ?? 0).compareTo(b.batchIndex ?? 0));
      for (var index = 0; index < seeds.length; index++) {
        if (items[index].seed != seeds[index] || items[index].id.isEmpty) {
          return null;
        }
      }
      return GatewayGenerationSubmission(
        taskId: task.id,
        items: [
          for (var index = 0; index < items.length; index++)
            GatewayGenerationItem(
              id: items[index].id,
              batchIndex: items[index].batchIndex ?? index + 1,
              status: items[index].status,
            ),
        ],
      );
    } on Object {
      return null;
    }
  }

  /// Submits [request] with the price computed from the rules (loaded when not
  /// given). When the gateway answers with a different price (`quote_changed`,
  /// or the free allowance ran out), the user decides through [confirmQuote];
  /// on yes the request is sent once more with the gateway's price, on no
  /// [QuoteDeclinedException] is thrown. Red points are never offered to an
  /// account that cannot pay them ([canPayRed]).
  Future<GatewayGenerationSubmission> submitGatewayBatch({
    required ImageGenerationRequest request,
    required List<int> seeds,
    required String clientRequestId,
    QuoteConfirmer? confirmQuote,
    bool canPayRed = true,
    ImageRules? rules,
  }) async {
    final prices = rules ?? await loadImageRules();
    final ImageQuote shown;
    try {
      shown = quoteImageRequest(prices, request.body, images: seeds.length);
    } on InvalidQuoteRequest catch (error) {
      throw error.toBackendException();
    }
    try {
      return await submitGatewayGenerationBatch(
        request: request,
        seeds: seeds,
        clientRequestId: clientRequestId,
        expectedQuote: shown.toExpectedQuote(),
      );
    } on BackendException catch (error) {
      final server = _gatewayQuoteOf(error);
      if (server == null ||
          confirmQuote == null ||
          (server.mode == QuoteMode.paid && !canPayRed)) {
        // The cached prices are stale; the next call reloads them.
        if (error is QuoteChangedException) _client.imageRules = null;
        rethrow;
      }
      final confirmed = await confirmQuote(
        QuoteConfirmation(
          shown: shown,
          serverMode: server.mode,
          serverPoints: server.points,
          reasons: server.reasons,
        ),
      );
      if (!confirmed) throw const QuoteDeclinedException();
      return submitGatewayGenerationBatch(
        request: request,
        seeds: seeds,
        clientRequestId: newClientRequestId(),
        expectedQuote: {'mode': server.mode, 'points': server.points},
      );
    }
  }

  /// The gateway's own quote carried by a price disagreement, if [error] is
  /// one.
  ({String mode, int points, List<String> reasons})? _gatewayQuoteOf(
    BackendException error,
  ) {
    final raw = error is QuoteChangedException
        ? error.quote
        : error.code == BackendErrorCode.freeAllowanceExhausted
        ? error.details['quote']
        : null;
    if (raw is! Map<String, dynamic>) return null;
    final mode = raw['mode'];
    final points = raw['points'];
    if (mode is! String || points is! num) return null;
    return (
      mode: mode,
      points: points.toInt(),
      reasons: [for (final reason in raw['reasons'] as List? ?? []) '$reason'],
    );
  }

  /// Generates an image using the NAI Diffusion V5 model.
  ///
  /// For img2img: set [action] to `"img2img"`, provide [sourceImageBase64],
  /// and optionally [maskBase64] for inpainting.
  Future<GenerationResult> generateImage({
    required String prompt,
    required int width,
    required int height,
    required int seed,
    int steps = 28,
    double scale = 6.0,
    String sampler = "k_euler_ancestral",
    String? negativePrompt,
    bool smea = false,
    bool smeaDyn = false,
    bool decrisper = false,
    String? promptPrefix,
    String? promptSuffix,
    List<NaiCharacter> characters = const [],
    List<NaiInteraction> interactions = const [],
    String action = 'generate',
    String? sourceImageBase64,
    String? maskBase64,
    double? img2imgStrength,
    double? img2imgNoise,
    bool? img2imgColorCorrect,
    int? maskBlur,
    List<String>? directorRefImages,
    List<Map<String, dynamic>>? directorRefDescriptions,
    List<double>? directorRefStrengths,
    List<double>? directorRefSecondaryStrengths,
    List<double>? directorRefInfoExtracted,
    List<String>? vibeTransferImages,
    List<double>? vibeTransferStrengths,
    List<double>? vibeTransferInfoExtracted,
    bool? useCoords,
    bool useCurated = false,
    QuoteConfirmer? confirmQuote,
    bool canPayRed = true,
  }) async {
    final request = buildImageGenerationRequest(
      prompt: prompt,
      width: width,
      height: height,
      seed: seed,
      steps: steps,
      scale: scale,
      sampler: sampler,
      negativePrompt: negativePrompt,
      smea: smea,
      smeaDyn: smeaDyn,
      decrisper: decrisper,
      promptPrefix: promptPrefix,
      promptSuffix: promptSuffix,
      characters: characters,
      interactions: interactions,
      action: action,
      sourceImageBase64: sourceImageBase64,
      maskBase64: maskBase64,
      img2imgStrength: img2imgStrength,
      img2imgNoise: img2imgNoise,
      img2imgColorCorrect: img2imgColorCorrect,
      maskBlur: maskBlur,
      directorRefImages: directorRefImages,
      directorRefDescriptions: directorRefDescriptions,
      directorRefStrengths: directorRefStrengths,
      directorRefSecondaryStrengths: directorRefSecondaryStrengths,
      directorRefInfoExtracted: directorRefInfoExtracted,
      vibeTransferImages: vibeTransferImages,
      vibeTransferStrengths: vibeTransferStrengths,
      vibeTransferInfoExtracted: vibeTransferInfoExtracted,
      useCoords: useCoords,
      useCurated: useCurated,
    );
    if (_gateway) {
      final submission = await submitGatewayBatch(
        request: request,
        seeds: [seed],
        clientRequestId: newClientRequestId(),
        confirmQuote: confirmQuote,
        canPayRed: canPayRed,
      );
      return GenerationResult(
        imageBytes: await _awaitGatewayImage(submission),
        metadata: Map<String, dynamic>.from(request.metadata),
      );
    }
    return GenerationResult(
      imageBytes: await generateDirect(request),
      metadata: Map<String, dynamic>.from(request.metadata),
    );
  }

  /// Sends an already built request straight to NovelAI with the personal API
  /// key (no gateway) and returns the image.
  Future<Uint8List> generateDirect(ImageGenerationRequest request) async {
    try {
      final response = await _dio.post(
        _imageUrl('/ai/generate-image'),
        data: request.body,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {..._headers()},
        ),
      );

      if (response.statusCode == 200) {
        return await compute(_decodeZip, response.data as List<int>);
      } else {
        throw Exception('[API Error ${response.statusCode}]');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw UnauthorizedException();
      }
      debugPrint('NovelAIService: DioError: ${e.message}');
      // Log the response body for API errors (400, 422, etc.)
      final responseData = e.response?.data;
      if (responseData != null) {
        if (responseData is List<int>) {
          debugPrint(
            'NovelAIService: Response body: ${utf8.decode(responseData, allowMalformed: true)}',
          );
        } else {
          debugPrint('NovelAIService: Response body: $responseData');
        }
      }
      rethrow;
    } catch (e) {
      debugPrint('NovelAIService: Error generating image: $e');
      rethrow;
    }
  }

  /// Augments an image using Director Tools (bg-removal, lineart, sketch, etc.)
  /// Through the gateway this is a paid call, sent once.
  Future<Uint8List> augmentImage({
    required String imageBase64,
    required int width,
    required int height,
    required String reqType,
    int? defry,
    String? prompt,
  }) async {
    final body = <String, dynamic>{
      'image': imageBase64,
      'width': width,
      'height': height,
      'req_type': reqType,
      if (defry != null) 'defry': defry,
      if (prompt != null) 'prompt': prompt,
    };
    return _postImageTool('/ai/augment-image', body, (caps) => caps.augment);
  }

  /// Upscales an image using the NovelAI upscale endpoint.
  ///
  /// If [scale] would produce an output exceeding [maxUpscaleOutputPixels],
  /// an [ArgumentError] is thrown. Use [bestUpscaleScale] to pick a safe value.
  /// Through the gateway this is a paid call, sent once.
  Future<Uint8List> upscaleImage({
    required String imageBase64,
    required int width,
    required int height,
    int scale = 2,
  }) async {
    if (width * scale > maxUpscaleOutputPixels ||
        height * scale > maxUpscaleOutputPixels) {
      throw ArgumentError(
        'Output resolution ${width * scale}x${height * scale} exceeds '
        'NAI upscale limit of ${maxUpscaleOutputPixels}px. '
        'Try a smaller scale or image.',
      );
    }

    final body = {
      'image': imageBase64,
      'width': width,
      'height': height,
      'scale': scale,
    };
    return _postImageTool('/ai/upscale', body, (caps) => caps.upscale);
  }

  /// POSTs a tool whose response is a ZIP holding the resulting image.
  Future<Uint8List> _postImageTool(
    String path,
    Map<String, dynamic> body,
    int Function(ToolCaps caps) cap,
  ) async {
    if (_gateway) {
      return compute(_decodeZip, await _postPaidTool(path, body, cap));
    }
    try {
      final response = await _dio.post(
        _imageUrl(path),
        data: body,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {..._headers()},
        ),
      );
      return await compute(_decodeZip, response.data as List<int>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw UnauthorizedException();
      }
      debugPrint('NovelAIService: $path error: ${e.message}');
      final responseData = e.response?.data;
      if (responseData is List<int>) {
        debugPrint(
          'NovelAIService: Response body: ${utf8.decode(responseData, allowMalformed: true)}',
        );
      }
      rethrow;
    }
  }
}

/// Helper to decode the ZIP response from NAI
Uint8List _decodeZip(List<int> data) {
  final archive = ZipDecoder().decodeBytes(data);
  if (archive.isNotEmpty) {
    final file = archive.first;
    if (file.isFile) {
      final Uint8List bytes = file.content;
      // A failed generation (e.g. unsupported Vibe + Precise Reference
      // combos) can come back as an empty or truncated entry. Saving those
      // bytes puts a corrupt image in the gallery, so fail the generation
      // here instead (issue #24).
      if (!_looksLikeImage(bytes)) {
        throw Exception(
          'API returned invalid image data (${bytes.length} bytes).',
        );
      }
      return bytes;
    }
  }
  throw Exception('No image file found in ZIP response.');
}

/// PNG signature or RIFF/WebP header — the formats NAI returns.
bool _looksLikeImage(Uint8List b) {
  if (b.length < 12) return false;
  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  var isPng = true;
  for (var i = 0; i < png.length; i++) {
    if (b[i] != png[i]) {
      isPng = false;
      break;
    }
  }
  if (isPng) return true;
  return b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50;
}
