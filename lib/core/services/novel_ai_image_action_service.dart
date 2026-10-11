import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../features/gallery/services/tool_result_saver.dart';
import '../gateway/backend_gateway.dart';
import '../gateway/backend_permissions.dart';
import '../utils/timestamp_utils.dart';
import 'novel_ai_service.dart';

enum NovelAiImageAction { upscale, backgroundRemoval }

extension NovelAiImageActionPermission on NovelAiImageAction {
  String get backendPermission => switch (this) {
    NovelAiImageAction.upscale => BackendPermission.imageUpscale,
    NovelAiImageAction.backgroundRemoval => BackendPermission.imageAugment,
  };

  /// Gallery file prefix; the detail view badges results by it.
  String get filePrefix => switch (this) {
    NovelAiImageAction.upscale => 'NAI_UP',
    NovelAiImageAction.backgroundRemoval => 'BG',
  };
}

/// Pure capability rule used by the gallery visibility check and tests.
/// Direct mode is authorized by the user's NAI token at execution time; the
/// gateway additionally requires the corresponding server permission.
bool isNovelAiImageActionAvailable({
  required bool gatewayMode,
  required bool permissionGranted,
}) => !gatewayMode || permissionGranted;

bool hasNovelAiImageActionPermission(
  BuildContext context,
  NovelAiImageAction action,
) {
  final permissionGranted = hasBackendPermission(
    context,
    action.backendPermission,
  );
  return isNovelAiImageActionAvailable(
    gatewayMode: useBackendGateway,
    permissionGranted: permissionGranted,
  );
}

/// Why an action cannot be started.
enum NovelAiImageActionBlocker { permissionDenied, missingApiKey }

/// A problem found locally, before any (paid) request was sent.
class NovelAiImageActionException implements Exception {
  const NovelAiImageActionException.unreadable() : width = 0, height = 0;

  const NovelAiImageActionException.tooLarge(this.width, this.height);

  final int width;
  final int height;

  bool get isTooLarge => width > 0;

  @override
  String toString() => isTooLarge
      ? 'NovelAiImageActionException: ${width}x$height is too large'
      : 'NovelAiImageActionException: image could not be decoded';
}

class NovelAiBatchResult {
  const NovelAiBatchResult({required this.succeeded, required this.total});

  /// Images whose request and save both succeeded.
  final int succeeded;
  final int total;
}

/// An image to process in a batch. [readBytes] is called lazily, one image
/// at a time.
class NovelAiImageActionSource {
  const NovelAiImageActionSource({
    required this.baseName,
    required this.readBytes,
  });

  final String baseName;
  final Future<Uint8List> Function() readBytes;
}

typedef ImageSizeReader = Future<(int, int)?> Function(Uint8List bytes);

Future<(int, int)?> _decodeImageSize(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = (frame.image.width, frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

/// The single entry point for NAI image actions (upscale, background
/// removal) used by the quick actions, the gallery detail view and the
/// gallery's batch upscale: permission and configuration checks, scale
/// selection, the request itself, and saving the result (download on Web,
/// gallery with source metadata on native).
///
/// [NovelAIService] already selects the authenticated gateway URL on Web and
/// the bearer-token direct URL on desktop, so a local API key is only
/// required in direct mode.
class NovelAiImageActionService {
  NovelAiImageActionService(
    this._service, {
    required ToolResultSaver saver,
    bool? gatewayMode,
    ImageSizeReader? readImageSize,
  }) : _saver = saver,
       _gatewayMode = gatewayMode ?? useBackendGateway,
       _readImageSize = readImageSize ?? _decodeImageSize;

  final NovelAIService _service;
  final ToolResultSaver _saver;
  final bool _gatewayMode;
  final ImageSizeReader _readImageSize;

  bool isConfigured({required String apiKey}) =>
      _gatewayMode || apiKey.trim().isNotEmpty;

  /// Null when the action may run. [permissionGranted] is the caller's
  /// [hasNovelAiImageActionPermission] result.
  NovelAiImageActionBlocker? blocker({
    required String apiKey,
    required bool permissionGranted,
  }) {
    if (!isNovelAiImageActionAvailable(
      gatewayMode: _gatewayMode,
      permissionGranted: permissionGranted,
    )) {
      return NovelAiImageActionBlocker.permissionDenied;
    }
    if (!isConfigured(apiKey: apiKey)) {
      return NovelAiImageActionBlocker.missingApiKey;
    }
    return null;
  }

  /// Largest upscale factor whose output stays within the NAI limit.
  static int? upscaleScaleFor(int width, int height) =>
      NovelAIService.bestUpscaleScale(width, height);

  String outputFileName(NovelAiImageAction action, String baseName) =>
      '${action.filePrefix}_${baseName}_${generateTimestamp()}.png';

  /// Sends one request for [action] on [bytes]. Throws
  /// [NovelAiImageActionException] when the image cannot be sent (nothing is
  /// charged then); transport errors propagate unchanged.
  Future<Uint8List> perform(NovelAiImageAction action, Uint8List bytes) async {
    final size = await _readImageSize(bytes);
    if (size == null) throw const NovelAiImageActionException.unreadable();
    final (width, height) = size;
    final imageBase64 = base64Encode(bytes);
    switch (action) {
      case NovelAiImageAction.upscale:
        final scale = upscaleScaleFor(width, height);
        if (scale == null) {
          throw NovelAiImageActionException.tooLarge(width, height);
        }
        return _service.upscaleImage(
          imageBase64: imageBase64,
          width: width,
          height: height,
          scale: scale,
        );
      case NovelAiImageAction.backgroundRemoval:
        return _service.augmentImage(
          imageBase64: imageBase64,
          width: width,
          height: height,
          reqType: 'bg-removal',
        );
    }
  }

  Future<ToolResultSaveOutcome> save(
    Uint8List result,
    String fileName, {
    required Uint8List sourceBytes,
  }) => _saver.save(result, fileName, sourceBytes: sourceBytes);

  /// Upscales and saves every source in turn. Only images that were both
  /// upscaled and saved count as succeeded.
  Future<NovelAiBatchResult> upscaleAll(
    List<NovelAiImageActionSource> sources, {
    void Function(int processed, int total)? onProgress,
  }) async {
    var succeeded = 0;
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      try {
        final bytes = await source.readBytes();
        final result = await perform(NovelAiImageAction.upscale, bytes);
        final outcome = await save(
          result,
          outputFileName(NovelAiImageAction.upscale, source.baseName),
          sourceBytes: bytes,
        );
        if (outcome.succeeded) succeeded++;
      } catch (e) {
        debugPrint('NovelAiImageActionService: ${source.baseName}: $e');
      }
      onProgress?.call(i + 1, sources.length);
    }
    return NovelAiBatchResult(succeeded: succeeded, total: sources.length);
  }
}
