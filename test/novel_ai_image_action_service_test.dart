import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/novel_ai_image_action_service.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';

class _RecordingNovelAiService extends NovelAIService {
  _RecordingNovelAiService() : super('');

  int upscaleCalls = 0;
  int backgroundRemovalCalls = 0;
  String? lastImageBase64;

  @override
  Future<Uint8List> upscaleImage({
    required String imageBase64,
    required int width,
    required int height,
    int scale = 2,
  }) async {
    upscaleCalls += 1;
    lastImageBase64 = imageBase64;
    return Uint8List.fromList([9]);
  }

  @override
  Future<Uint8List> augmentImage({
    required String imageBase64,
    required int width,
    required int height,
    required String reqType,
    int? defry,
    String? prompt,
  }) async {
    expect(reqType, 'bg-removal');
    backgroundRemovalCalls += 1;
    lastImageBase64 = imageBase64;
    return Uint8List.fromList([8]);
  }
}

void main() {
  test(
    'gateway without a local key still executes through shared service',
    () async {
      final service = _RecordingNovelAiService();
      final actions = NovelAiImageActionService(service, gatewayMode: true);

      expect(actions.isConfigured(apiKey: ''), isTrue);
      expect(
        await actions.upscale(
          bytes: Uint8List.fromList([1, 2, 3]),
          width: 32,
          height: 24,
          scale: 4,
        ),
        [9],
      );
      await actions.removeBackground(
        bytes: Uint8List.fromList([1, 2, 3]),
        width: 32,
        height: 24,
      );

      expect(service.upscaleCalls, 1);
      expect(service.backgroundRemovalCalls, 1);
      expect(service.lastImageBase64, 'AQID');
    },
  );

  test('direct transport still requires a local key', () {
    final actions = NovelAiImageActionService(
      _RecordingNovelAiService(),
      gatewayMode: false,
    );

    expect(actions.isConfigured(apiKey: ''), isFalse);
    expect(actions.isConfigured(apiKey: 'token'), isTrue);
  });

  test('gateway action visibility hides buttons without permission', () {
    expect(
      isNovelAiImageActionAvailable(
        gatewayMode: true,
        permissionGranted: false,
      ),
      isFalse,
    );
    expect(
      isNovelAiImageActionAvailable(gatewayMode: true, permissionGranted: true),
      isTrue,
    );
    expect(
      isNovelAiImageActionAvailable(
        gatewayMode: false,
        permissionGranted: false,
      ),
      isTrue,
    );
  });
}
