import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';

void main() {
  final service = NovelAIService('');

  ImageGenerationRequest build({
    bool useCurated = false,
    String action = 'generate',
  }) {
    return service.buildImageGenerationRequest(
      prompt: '1girl',
      negativePrompt: '',
      width: 832,
      height: 1216,
      seed: 123,
      action: action,
      sourceImageBase64: action == 'generate' ? null : 'image',
      maskBase64: action == 'infill' ? 'mask' : null,
      useCurated: useCurated,
    );
  }

  test('full and curated generation use the official V5 model IDs', () {
    final full = build();
    final curated = build(useCurated: true);

    expect(full.body['model'], 'nai-diffusion-5-full');
    expect(curated.body['model'], 'nai-diffusion-5-curated');
    expect(full.body['parameters']['params_version'], 4);
    expect(curated.body['parameters']['params_version'], 4);
  });

  test('inpainting follows the current NovelAI website compatibility', () {
    final full = build(action: 'infill');
    final curated = build(action: 'infill', useCurated: true);

    expect(full.body['model'], 'nai-diffusion-5-full-inpainting');
    expect(curated.body['model'], 'nai-diffusion-4-5-curated-inpainting');
  });
}
