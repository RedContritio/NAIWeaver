import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../../../generation/models/nai_character.dart';
import '../models/img2img_session.dart';
import 'mask_encoder.dart';

/// The assembled request ready for GenerationNotifier.generateImg2Img().
class Img2ImgRequest {
  final String prompt;
  final String negativePrompt;
  final int width;
  final int height;
  final double scale;
  final int steps;
  final String sampler;
  final String sourceImageBase64;
  final String? maskBase64;
  final double strength;
  final double noise;
  final bool colorCorrect;
  final int maskBlur;
  final String? promptPrefix;
  final String? promptSuffix;
  final List<NaiCharacter> characters;
  final List<NaiInteraction> interactions;
  final bool useCoords;

  Img2ImgRequest({
    required this.prompt,
    required this.negativePrompt,
    required this.width,
    required this.height,
    required this.scale,
    required this.steps,
    required this.sampler,
    required this.sourceImageBase64,
    this.maskBase64,
    required this.strength,
    required this.noise,
    required this.colorCorrect,
    required this.maskBlur,
    this.promptPrefix,
    this.promptSuffix,
    this.characters = const [],
    this.interactions = const [],
    this.useCoords = false,
  });
}

class Img2ImgRequestBuilder {
  /// Builds a complete [Img2ImgRequest] from session state and generation params.
  static Future<Img2ImgRequest> build({
    required Img2ImgSession session,
    required int targetWidth,
    required int targetHeight,
    double scale = 5.0,
    int steps = 28,
    String sampler = 'k_euler_ancestral',
    String? promptPrefix,
    String? promptSuffix,
    String? styleNegativeContent,
    List<NaiCharacter> characters = const [],
    List<NaiInteraction> interactions = const [],
    bool useCoords = false,
  }) async {
    // Resize source image to target resolution and encode as base64
    final sourceBase64 = await compute(_resizeAndEncode, _ResizeParams(
      bytes: session.sourceImageBytes,
      width: targetWidth,
      height: targetHeight,
    ));

    // Render mask if strokes exist
    String? maskBase64;
    if (session.hasMask) {
      maskBase64 = await MaskEncoder.renderMaskBase64WithPrebaked(
        strokes: session.maskStrokes,
        width: targetWidth,
        height: targetHeight,
        prebakedMaskBytes: session.prebakedMaskBytes,
      );
      // Save debug mask in debug mode only
      if (kDebugMode) {
        try {
          await MaskEncoder.debugSaveMask(maskBase64, 'output/_debug_mask.png');
        } catch (e) {
          debugPrint('Img2ImgRequestBuilder.build: $e');
        }
      }
    }

    final effectiveNegative = styleNegativeContent != null && styleNegativeContent.isNotEmpty
        ? '${session.negativePrompt}, $styleNegativeContent'
        : session.negativePrompt;

    return Img2ImgRequest(
      prompt: session.prompt,
      negativePrompt: effectiveNegative,
      width: targetWidth,
      height: targetHeight,
      scale: scale,
      steps: steps,
      sampler: sampler,
      sourceImageBase64: sourceBase64,
      maskBase64: maskBase64,
      strength: session.settings.strength,
      noise: session.settings.noise,
      colorCorrect: session.settings.colorCorrect,
      maskBlur: session.settings.maskBlur,
      promptPrefix: promptPrefix,
      promptSuffix: promptSuffix,
      characters: characters,
      interactions: interactions,
      useCoords: useCoords,
    );
  }
}

class _ResizeParams {
  final Uint8List bytes;
  final int width;
  final int height;

  _ResizeParams({required this.bytes, required this.width, required this.height});
}

String _resizeAndEncode(_ResizeParams params) {
  final decoded = img.decodeImage(params.bytes);
  if (decoded == null) throw Exception('Failed to decode source image');

  final resized = img.copyResize(decoded, width: params.width, height: params.height);
  final rgb = resized.convert(numChannels: 3);
  final pngBytes = img.encodePng(rgb);
  return base64Encode(pngBytes);
}
