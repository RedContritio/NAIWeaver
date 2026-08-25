import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import '../gateway/backend_gateway.dart';
import '../../features/generation/models/nai_character.dart';

/// Strips backslashes from a prompt before it reaches the NovelAI API.
/// NovelAI prompts have no use for `\` (it's not an escape or weighting
/// character in their syntax), and stray backslashes — usually pasted in by
/// accident from other tooling — only pollute the prompt. Done here, at the
/// single API chokepoint, so every path (txt2img, img2img, characters) is
/// covered. Returns an empty string for null input.
String sanitizePromptForNai(String? prompt) =>
    (prompt ?? '').replaceAll('\\', '');

String _newClientRequestId() {
  final random = math.Random.secure();
  int uint32() => random.nextInt(1 << 16) * (1 << 16) + random.nextInt(1 << 16);
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-'
      '${uint32().toRadixString(16).padLeft(8, '0')}-'
      '${uint32().toRadixString(16).padLeft(8, '0')}';
}

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

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException([this.message = 'Unauthorized']);
}

/// A generation request was rejected before it entered the server queue.
class GenerationRequestException implements Exception {
  final int? statusCode;
  final String code;
  final String message;
  final String? existingTaskId;
  final String? existingTaskCreatedAt;
  final String? pointKind;

  const GenerationRequestException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.existingTaskId,
    this.existingTaskCreatedAt,
    this.pointKind,
  });
}

/// Service to interact with NovelAI Image Generation API (V4.5)
class NovelAIService {
  final Dio _dio = Dio();
  final String _apiKey;

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

  NovelAIService(this._apiKey) {
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

  String _imageUrl(String path) => useBackendGateway
      ? novelAiProxyUrl('image', path)
      : 'https://image.novelai.net$path';

  String _apiUrl(String path) => useBackendGateway
      ? novelAiProxyUrl('api', path)
      : 'https://api.novelai.net$path';

  Map<String, String> _headers({bool json = true}) => {
    if (!useBackendGateway) 'Authorization': 'Bearer $_apiKey',
    if (json) 'Content-Type': 'application/json',
  };

  /// POST with automatic retry on connection/timeout errors.
  Future<Response<dynamic>> _postWithRetry(
    String url, {
    required dynamic data,
    Options? options,
  }) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        return await _dio.post(url, data: data, options: options);
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

  /// Wait for a gateway-owned generation task. The job itself lives on the
  /// server, so closing or refreshing the client cannot discard it.
  Future<Uint8List> waitForGatewayGeneration(
    String taskId, {
    ValueChanged<String>? onStatus,
  }) async {
    var retryDelay = const Duration(seconds: 1);
    var pollFailures = 0;
    var imageFailures = 0;
    while (true) {
      try {
        final statusResponse = await _dio.get<dynamic>(
          backendUrl('/api/generation-items/$taskId'),
        );
        final task = statusResponse.data;
        if (task is! Map<String, dynamic>) {
          throw Exception('Invalid generation task response');
        }
        final taskStatus = task['status'] as String? ?? '';
        pollFailures = 0;
        onStatus?.call(taskStatus);
        if (taskStatus == 'success') {
          try {
            final imageResponse = await _dio.get<List<int>>(
              backendUrl('/api/history/$taskId/image'),
              options: Options(responseType: ResponseType.bytes),
            );
            return Uint8List.fromList(imageResponse.data ?? const <int>[]);
          } on DioException catch (error) {
            final imageStatus = error.response?.statusCode;
            if (imageStatus == 401) throw UnauthorizedException();
            imageFailures++;
            if (imageStatus == 403 ||
                (imageStatus == 404 && imageFailures >= 3) ||
                imageFailures >= 8) {
              rethrow;
            }
            await Future.delayed(retryDelay);
            continue;
          }
        }
        if (taskStatus == 'failed' ||
            taskStatus == 'rejected' ||
            taskStatus == 'cancelled') {
          throw Exception(
            task['error_message'] as String? ?? 'Generation failed',
          );
        }
        retryDelay = const Duration(seconds: 1);
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (status == 401) throw UnauthorizedException();
        if (status == 403 || status == 404) rethrow;
        pollFailures++;
        if (pollFailures >= 8) rethrow;
        await Future.delayed(retryDelay);
        final nextSeconds = (retryDelay.inSeconds * 2).clamp(1, 15);
        retryDelay = Duration(seconds: nextSeconds);
        continue;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  /// Encodes an image into a vibe vector via the NAI encode-vibe endpoint.
  ///
  /// Returns the raw binary vibe vector which must be base64-encoded before
  /// passing to `reference_image_multiple` in the generate call.
  Future<Uint8List> encodeVibeImage({
    required String imageBase64,
    double informationExtracted = 1.0,
    bool useCurated = false,
  }) async {
    final url = _imageUrl('/ai/encode-vibe');
    final body = {
      "image": imageBase64,
      "model": useCurated
          ? "nai-diffusion-4-5-curated"
          : "nai-diffusion-4-5-full",
      "information_extracted": informationExtracted,
    };

    try {
      final response = await _postWithRetry(
        url,
        data: body,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {..._headers()},
        ),
      );

      if (response.statusCode == 200) {
        return Uint8List.fromList(response.data as List<int>);
      } else {
        throw Exception('[Encode-Vibe Error ${response.statusCode}]');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw UnauthorizedException();
      }
      debugPrint('NovelAIService: Encode-vibe error: ${e.message}');
      throw _generationExceptionForDio(e);
    }
  }

  GenerationRequestException _generationExceptionForDio(DioException error) {
    final statusCode = error.response?.statusCode;
    final response = error.response?.data;
    final detail = response is Map<String, dynamic> ? response['detail'] : null;
    final detailMap = detail is Map<String, dynamic> ? detail : null;
    final message =
        detailMap?['message'] as String? ??
        (detail is String ? detail : 'Generation request failed');
    return GenerationRequestException(
      statusCode: statusCode,
      code: detailMap?['code'] as String? ?? '',
      message: message,
      existingTaskId: detailMap?['task_id'] as String?,
      existingTaskCreatedAt: detailMap?['created_at'] as String?,
      pointKind: detailMap?['point_kind'] as String?,
    );
  }

  /// Fetches the user's Anlas balance from the NovelAI user data API.
  /// Returns null on failure (no API key, network error).
  Future<int?> getAnlasBalance() async {
    if (useBackendGateway) return null;
    if (!useBackendGateway && _apiKey.isEmpty) return null;
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
      "params_version": 3,
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
      "model": action == 'infill'
          ? (useCurated
                ? "nai-diffusion-4-5-curated-inpainting"
                : "nai-diffusion-4-5-full-inpainting")
          : (useCurated
                ? "nai-diffusion-4-5-curated"
                : "nai-diffusion-4-5-full"),
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
  }) async {
    try {
      final response = await _postWithRetry(
        backendUrl('/api/generation-tasks'),
        data: {
          'client_request_id': clientRequestId,
          'request': request.body,
          'seeds': seeds,
        },
        options: Options(headers: _headers()),
      );
      final data = response.data;
      if (response.statusCode != 202 || data is! Map<String, dynamic>) {
        throw GenerationRequestException(
          statusCode: response.statusCode,
          code: 'invalid_submission_response',
          message: 'Invalid generation submission response',
        );
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
      if (taskId.isEmpty || items.length != seeds.length) {
        throw const GenerationRequestException(
          statusCode: null,
          code: 'invalid_submission_response',
          message: 'Invalid generation submission response',
        );
      }
      return GatewayGenerationSubmission(taskId: taskId, items: items);
    } on DioException catch (error) {
      throw _generationExceptionForDio(error);
    }
  }

  /// Generates an image using the NAI Diffusion V4.5 model.
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
    Future<void> Function(String taskId)? onGatewayTaskAccepted,
    ValueChanged<String>? onGatewayTaskStatus,
    String? batchId,
    int? batchIndex,
    bool isBatch = false,
  }) async {
    final url = _imageUrl('/ai/generate-image');
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
    final body = request.body;

    try {
      if (useBackendGateway) {
        final submission = await submitGatewayGenerationBatch(
          request: request,
          seeds: [seed],
          clientRequestId: _newClientRequestId(),
        );
        final taskId = submission.items.single.id;
        await onGatewayTaskAccepted?.call(taskId);
        final imageBytes = await waitForGatewayGeneration(
          taskId,
          onStatus: onGatewayTaskStatus,
        );
        return GenerationResult(
          imageBytes: imageBytes,
          metadata: Map<String, dynamic>.from(request.metadata),
        );
      }
      final response = await _postWithRetry(
        url,
        data: body,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {..._headers()},
        ),
      );

      if (response.statusCode == 200) {
        final imageBytes = await compute(
          _decodeZip,
          response.data as List<int>,
        );

        // Prepare metadata in official NAI style
        // We include both 'uc' and 'undesired_content' to be absolutely sure
        final metadata = Map<String, dynamic>.from(request.metadata);

        return GenerationResult(imageBytes: imageBytes, metadata: metadata);
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
      // Only a rejected task submission is a generation-request rejection.
      // Polling and image-download failures happen after it has been accepted
      // into the durable server queue and need their real network/API message.
      final isGatewaySubmission =
          useBackendGateway &&
          e.requestOptions.method == 'POST' &&
          e.requestOptions.path.contains('/api/generation-tasks');
      if (isGatewaySubmission) throw _generationExceptionForDio(e);
      rethrow;
    } catch (e) {
      debugPrint('NovelAIService: Error generating image: $e');
      rethrow;
    }
  }

  /// Augments an image using Director Tools (bg-removal, lineart, sketch, etc.)
  Future<Uint8List> augmentImage({
    required String imageBase64,
    required int width,
    required int height,
    required String reqType,
    int? defry,
    String? prompt,
  }) async {
    final url = _imageUrl('/ai/augment-image');
    final body = <String, dynamic>{
      'image': imageBase64,
      'width': width,
      'height': height,
      'req_type': reqType,
      if (defry != null) 'defry': defry,
      if (prompt != null) 'prompt': prompt,
    };

    try {
      final response = await _postWithRetry(
        url,
        data: body,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {..._headers()},
        ),
      );

      if (response.statusCode == 200) {
        return await compute(_decodeZip, response.data as List<int>);
      } else {
        throw Exception('[Augment Error ${response.statusCode}]');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw UnauthorizedException();
      }
      debugPrint('NovelAIService: Augment error: ${e.message}');
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
    }
  }

  /// Upscales an image using the NovelAI upscale endpoint.
  ///
  /// If [scale] would produce an output exceeding [maxUpscaleOutputPixels],
  /// an [ArgumentError] is thrown. Use [bestUpscaleScale] to pick a safe value.
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

    final url = _imageUrl('/ai/upscale');
    final body = {
      'image': imageBase64,
      'width': width,
      'height': height,
      'scale': scale,
    };

    try {
      final response = await _postWithRetry(
        url,
        data: body,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {..._headers()},
        ),
      );

      if (response.statusCode == 200) {
        return await compute(_decodeZip, response.data as List<int>);
      } else {
        throw Exception('[Upscale Error ${response.statusCode}]');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw UnauthorizedException();
      }
      debugPrint('NovelAIService: Upscale error: ${e.message}');
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
