import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naiweaver/core/utils/image_utils.dart';
import 'package:naiweaver/features/generation/services/metadata_import_service.dart';

void main() {
  final service = MetadataImportService();
  final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 2, height: 2)),
  );
  final history = <String, dynamic>{
    'prompt': 'history prompt',
    'uc': 'history negative',
    'width': 832,
    'height': 1216,
    'steps': 28,
    'scale': 5,
    'sampler': 'k_euler',
    'seed': 123,
    'v4_prompt': {
      'use_coords': true,
      'caption': {
        'char_captions': [
          {
            'char_caption': 'character prompt',
            'centers': [
              {'x': 0.2, 'y': 0.8},
            ],
          },
        ],
      },
    },
    'v4_negative_prompt': {
      'caption': {
        'char_captions': [
          {'char_caption': 'character negative'},
        ],
      },
    },
  };

  test('history restores parameters and characters without an image', () async {
    final result = service.parseGenerationParameters(history);
    expect(result.prompt, 'history prompt');
    expect(result.negativePrompt, 'history negative');
    expect(result.seed, '123');
    expect(result.width, 832);
    expect(result.height, 1216);
    expect(result.characters.single.prompt, 'character prompt');
    expect(result.characters.single.uc, 'character negative');
    expect(result.characters.single.center.x, 0.2);
    expect(result.autoPositioning, false);
    expect(result.imageBytes, isNull);
  });

  test(
    'local image import still restores embedded smart-style metadata',
    () async {
      final embedded = injectMetadata({
        'bytes': bytes,
        'metadata': {
          'prompt': 'styled prompt',
          'original_prompt': 'original prompt',
          'uc': 'styled negative',
          'original_negative_prompt': 'original negative',
          'active_style_names': ['saved style'],
          'is_style_enabled': true,
        },
      });
      final result = await service.parseImageMetadataBytes(
        embedded,
        smartStyleImport: true,
      );
      expect(result.prompt, 'original prompt');
      expect(result.negativePrompt, 'original negative');
      expect(result.activeStyleNames, ['saved style']);
      expect(result.isStyleEnabled, true);
    },
  );

  test('PNG conversion preserves metadata and stripping removes it', () {
    final original = injectMetadata({'bytes': bytes, 'metadata': history});
    expect(extractMetadata(original)?['Description'], 'history prompt');
    final converted = convertToPngPreservingMetadata({
      'bytes': bytes,
      'originalBytes': original,
    });
    expect(extractMetadata(converted!), extractMetadata(original));
    expect(extractMetadata(stripMetadata(original)), isNull);
  });

  test(
    'local images without metadata still report unavailable parameters',
    () async {
      await expectLater(
        service.parseImageMetadataBytes(bytes, smartStyleImport: true),
        throwsException,
      );
    },
  );
}
