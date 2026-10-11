import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';
import 'package:naiweaver/features/generation/models/nai_character.dart';

/// The gateway rejects request keys it does not know
/// (docs/GATEWAY_CONTRACT.md §3); the whitelist lives in
/// test/fixtures/image_request_keys.json and is shared with the server tests.
void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/image_request_keys.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final topLevel = (fixture['top_level_keys'] as Map).keys.toSet();
  final parameters = (fixture['parameter_keys'] as Map).keys.toSet();
  final service = NovelAIService('');

  final character = NaiCharacter(
    prompt: '1girl',
    uc: '',
    center: NaiCoordinate(x: 0.5, y: 0.5),
  );
  final requests = <String, ImageGenerationRequest>{
    'plain generation': service.buildImageGenerationRequest(
      prompt: 'p',
      width: 832,
      height: 1216,
      seed: 1,
      negativePrompt: 'n',
    ),
    'img2img': service.buildImageGenerationRequest(
      prompt: 'p',
      width: 832,
      height: 1216,
      seed: 1,
      action: 'img2img',
      sourceImageBase64: 'x',
      img2imgStrength: 0.5,
      img2imgNoise: 0.1,
    ),
    'infill': service.buildImageGenerationRequest(
      prompt: 'p',
      width: 832,
      height: 1216,
      seed: 1,
      action: 'infill',
      sourceImageBase64: 'x',
      maskBase64: 'm',
      img2imgStrength: 0.5,
      maskBlur: 4,
    ),
    'characters': service.buildImageGenerationRequest(
      prompt: 'p',
      width: 832,
      height: 1216,
      seed: 1,
      characters: [character],
    ),
    'director references': service.buildImageGenerationRequest(
      prompt: 'p',
      width: 832,
      height: 1216,
      seed: 1,
      directorRefImages: ['x'],
      directorRefDescriptions: [
        {'caption': 'c'},
      ],
      directorRefStrengths: [1.0],
      directorRefSecondaryStrengths: [0.0],
      directorRefInfoExtracted: [1.0],
    ),
    'vibes': service.buildImageGenerationRequest(
      prompt: 'p',
      width: 832,
      height: 1216,
      seed: 1,
      vibeTransferImages: ['x'],
      vibeTransferStrengths: [0.6],
      vibeTransferInfoExtracted: [1.0],
    ),
  };

  for (final entry in requests.entries) {
    test('${entry.key} uses only keys the gateway accepts', () {
      final body = entry.value.body;
      expect(topLevel, containsAll(body.keys));
      expect(
        parameters,
        containsAll((body['parameters'] as Map<String, dynamic>).keys),
      );
    });
  }
}
