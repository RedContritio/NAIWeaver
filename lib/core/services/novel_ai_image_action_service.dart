import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../gateway/backend_gateway.dart';
import '../gateway/backend_permissions.dart';
import 'novel_ai_service.dart';

enum NovelAiImageAction { upscale, backgroundRemoval }

extension NovelAiImageActionPermission on NovelAiImageAction {
  String get backendPermission => switch (this) {
    NovelAiImageAction.upscale => BackendPermission.imageUpscale,
    NovelAiImageAction.backgroundRemoval => BackendPermission.imageAugment,
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

/// Shared transport boundary for NAI image actions.
///
/// [NovelAIService] already selects the authenticated gateway URL on Web and
/// the bearer-token direct URL on desktop. This wrapper keeps callers from
/// imposing a local-token requirement on the gateway path and centralizes the
/// request shapes used by gallery actions.
class NovelAiImageActionService {
  NovelAiImageActionService(this._service, {bool? gatewayMode})
    : _gatewayMode = gatewayMode ?? useBackendGateway;

  final NovelAIService _service;
  final bool _gatewayMode;

  bool isConfigured({required String apiKey}) =>
      _gatewayMode || apiKey.trim().isNotEmpty;

  Future<Uint8List> upscale({
    required Uint8List bytes,
    required int width,
    required int height,
    required int scale,
  }) => _service.upscaleImage(
    imageBase64: base64Encode(bytes),
    width: width,
    height: height,
    scale: scale,
  );

  Future<Uint8List> removeBackground({
    required Uint8List bytes,
    required int width,
    required int height,
  }) => _service.augmentImage(
    imageBase64: base64Encode(bytes),
    width: width,
    height: height,
    reqType: 'bg-removal',
  );
}
