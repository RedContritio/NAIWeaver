import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/novel_ai_image_action_service.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';
import 'package:naiweaver/features/gallery/services/tool_result_saver.dart';

class _RecordingNovelAiService extends NovelAIService {
  _RecordingNovelAiService() : super('');

  final upscaleScales = <int>[];
  int backgroundRemovalCalls = 0;
  String? lastImageBase64;

  /// Images (by first byte) whose upscale request fails upstream.
  final failingImages = <int>{};

  @override
  Future<Uint8List> upscaleImage({
    required String imageBase64,
    required int width,
    required int height,
    int scale = 2,
  }) async {
    lastImageBase64 = imageBase64;
    // The real client rejects oversized output before sending anything.
    if (width * scale > NovelAIService.maxUpscaleOutputPixels ||
        height * scale > NovelAIService.maxUpscaleOutputPixels) {
      throw ArgumentError('too large');
    }
    upscaleScales.add(scale);
    final first = Uri.parse(
      'data:;base64,$imageBase64',
    ).data!.contentAsBytes().first;
    if (failingImages.contains(first)) throw Exception('upstream 500');
    return Uint8List.fromList([9, first]);
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

/// Image sizes keyed by the first byte of the fake image.
const _sizes = <int, (int, int)>{
  1: (832, 1216),
  2: (512, 512),
  3: (2500, 2500),
  4: (640, 640),
};

Future<(int, int)?> _fakeSize(Uint8List bytes) async => _sizes[bytes.first];

class _Saves {
  final names = <String>[];
  final sources = <Uint8List?>[];

  /// Results (by their second byte) whose save fails.
  final failing = <int>{};

  Future<void> write(
    Uint8List bytes,
    String fileName, {
    Uint8List? sourceBytes,
  }) async {
    if (failing.contains(bytes.last)) throw StateError('disk full');
    names.add(fileName);
    sources.add(sourceBytes);
  }
}

NovelAiImageActionService _actions(
  NovelAIService service, {
  bool gatewayMode = false,
  _Saves? saves,
}) => NovelAiImageActionService(
  service,
  gatewayMode: gatewayMode,
  readImageSize: _fakeSize,
  saver: ToolResultSaver(writeToGallery: (saves ?? _Saves()).write, web: false),
);

void main() {
  test(
    'gateway without a local key still executes through shared service',
    () async {
      final service = _RecordingNovelAiService();
      final actions = _actions(service, gatewayMode: true);

      expect(actions.blocker(apiKey: '', permissionGranted: true), isNull);
      expect(
        await actions.perform(
          NovelAiImageAction.upscale,
          Uint8List.fromList([2, 2, 3]),
        ),
        [9, 2],
      );
      await actions.perform(
        NovelAiImageAction.backgroundRemoval,
        Uint8List.fromList([2, 2, 3]),
      );

      expect(service.upscaleScales, [4]);
      expect(service.backgroundRemovalCalls, 1);
      expect(service.lastImageBase64, 'AgID');
    },
  );

  test('direct transport still requires a local key', () {
    final actions = _actions(_RecordingNovelAiService());

    expect(actions.isConfigured(apiKey: ''), isFalse);
    expect(
      actions.blocker(apiKey: ' ', permissionGranted: true),
      NovelAiImageActionBlocker.missingApiKey,
    );
    expect(actions.blocker(apiKey: 'token', permissionGranted: true), isNull);
  });

  test('gateway refuses actions the account may not use', () {
    final actions = _actions(_RecordingNovelAiService(), gatewayMode: true);

    expect(
      actions.blocker(apiKey: '', permissionGranted: false),
      NovelAiImageActionBlocker.permissionDenied,
    );
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

  test('upscale picks the largest scale that fits the output limit', () async {
    final service = _RecordingNovelAiService();
    final actions = _actions(service);

    // 832x1216 at 4x would be 3328x4864, beyond the 4096px limit.
    await actions.perform(NovelAiImageAction.upscale, Uint8List.fromList([1]));
    await actions.perform(NovelAiImageAction.upscale, Uint8List.fromList([2]));

    expect(service.upscaleScales, [2, 4]);
  });

  test('an image too large for any scale is refused before sending', () async {
    final service = _RecordingNovelAiService();
    final actions = _actions(service);

    await expectLater(
      actions.perform(NovelAiImageAction.upscale, Uint8List.fromList([3])),
      throwsA(
        isA<NovelAiImageActionException>()
            .having((e) => e.isTooLarge, 'isTooLarge', isTrue)
            .having((e) => e.width, 'width', 2500),
      ),
    );
    await expectLater(
      actions.perform(NovelAiImageAction.upscale, Uint8List.fromList([7])),
      throwsA(
        isA<NovelAiImageActionException>().having(
          (e) => e.isTooLarge,
          'isTooLarge',
          isFalse,
        ),
      ),
    );
    expect(service.lastImageBase64, isNull);
  });

  test(
    'batch upscale counts only images that were upscaled and saved',
    () async {
      final service = _RecordingNovelAiService()..failingImages.add(2);
      final saves = _Saves()..failing.add(4);
      final actions = _actions(service, saves: saves);
      final progress = <int>[];

      final result = await actions.upscaleAll([
        // 832x1216: only works at 2x; a hard-coded 4x used to fail here.
        NovelAiImageActionSource(
          baseName: 'portrait',
          readBytes: () async => Uint8List.fromList([1]),
        ),
        // Upstream request fails.
        NovelAiImageActionSource(
          baseName: 'broken',
          readBytes: () async => Uint8List.fromList([2]),
        ),
        // Too large for any scale.
        NovelAiImageActionSource(
          baseName: 'huge',
          readBytes: () async => Uint8List.fromList([3]),
        ),
        // Upscaled, but writing the result fails.
        NovelAiImageActionSource(
          baseName: 'unsaved',
          readBytes: () async => Uint8List.fromList([4]),
        ),
      ], onProgress: (processed, _) => progress.add(processed));

      expect(result.total, 4);
      expect(result.succeeded, 1);
      expect(progress, [1, 2, 3, 4]);
      expect(service.upscaleScales, [2, 4, 4]);
      expect(saves.names.single, startsWith('NAI_UP_portrait_'));
      expect(saves.sources.single, [1], reason: 'keeps the source metadata');
    },
  );
}
