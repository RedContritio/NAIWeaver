import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';
import 'package:naiweaver/features/generation/providers/generation_notifier.dart';
import 'package:naiweaver/features/generation/services/metadata_import_service.dart';
import 'package:naiweaver/features/tools/img2img/services/img2img_request_builder.dart';

import 'support/generation_rig.dart';
import 'test_harness.dart';

/// A direct (no gateway) service that counts the requests in flight.
class _DirectService extends NovelAIService {
  _DirectService(super.key, this.image) : super(gateway: false);

  final Uint8List image;
  int calls = 0;
  int inFlight = 0;
  int maxInFlight = 0;

  /// Held while it is set: a request waits for it.
  Completer<void>? gate;

  @override
  Future<Uint8List> generateDirect(ImageGenerationRequest request) async {
    calls++;
    inFlight++;
    maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
    try {
      await gate?.future;
      return image;
    } finally {
      inFlight--;
    }
  }
}

Img2ImgRequest _img2img() => Img2ImgRequest(
  prompt: 'edit',
  negativePrompt: '',
  width: 832,
  height: 1216,
  scale: 5,
  steps: 28,
  sampler: 'k_euler_ancestral',
  sourceImageBase64: 'AAAA',
  strength: 0.5,
  noise: 0,
  colorCorrect: false,
  maskBlur: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Uint8List png;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('naiweaver_run');
    png = File('assets/logo.png').readAsBytesSync();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<GatewayRig> rig({
    Duration timeout = const Duration(seconds: 30),
    bool autoSave = false,
  }) async {
    final rig = await GatewayRig.create(dir, png, timeout: timeout);
    await rig.generation.toggleAutoSave(autoSave);
    // The styles are not what these tests are about.
    rig.generation.updateSettings(isStyleEnabled: false);
    addTearDown(rig.generation.dispose);
    return rig;
  }

  group('one generation at a time', () {
    test('a second generate is refused and submits nothing', () async {
      final r = await rig();
      final g = r.generation;
      g.promptController.text = '1girl';
      g.updateSettings(batchCount: 2);
      final first = g.generate(batchLimit: 2);
      await eventually(() => g.state.generatedImages.length == 2);
      final slots = g.state.generatedImages.map((item) => item.id).toList();
      expect(g.state.isGenerating, isTrue);

      final second = await g.generate(batchLimit: 2);

      expect(second.rejected, isTrue);
      expect(r.gateway.submissions, hasLength(1));
      expect(g.state.generatedImages.map((item) => item.id), slots);

      r.gateway.setAll('success');
      final outcome = await first;
      expect(outcome.succeeded, isTrue);
      expect(g.state.isGenerating, isFalse);
      expect(g.state.isLoading, isFalse);
    });

    test(
      'imports and single-image calls leave a running batch alone',
      () async {
        final r = await rig();
        final g = r.generation;
        g.promptController.text = '1girl';
        g.updateSettings(batchCount: 2);
        final run = g.generate(batchLimit: 2);
        await eventually(() => g.state.generatedImages.length == 2);
        final slots = g.state.generatedImages.map((item) => item.id).toList();

        // A dropped file: its settings apply, its picture does not replace the
        // images that are still arriving.
        g.applyImportedMetadata(
          MetadataImportResult(
            prompt: 'imported',
            negativePrompt: '',
            imageBytes: png,
          ),
          ImportCategory.values.toSet(),
        );
        g.setGeneratedImage(png);
        final edited = await g.generateImg2Img(_img2img());
        final previewed = await g.generateQuickPreview('tag');

        expect(g.promptController.text, 'imported');
        expect(edited, isNull);
        expect(previewed, isNull);
        expect(g.state.errorMessage, isNotNull);
        expect(g.state.generatedImages.map((item) => item.id), slots);
        expect(g.state.generatedImages.every((item) => item.isLoading), isTrue);
        expect(r.gateway.submissions, hasLength(1));

        r.gateway.setAll('success');
        expect((await run).succeeded, isTrue);
      },
    );
  });

  group('results go to their own slot', () {
    test('by item id, whatever order they finish in', () async {
      final r = await rig();
      final g = r.generation;
      g.promptController.text = '1girl';
      g.updateSettings(batchCount: 2);
      final run = g.generate(batchLimit: 2);
      await eventually(() => g.state.generatedImages.length == 2);

      r.gateway.status[r.gateway.itemIds[1]] = 'success';
      await eventually(() => g.state.generatedImages[1].isComplete);
      expect(g.state.generatedImages[0].isComplete, isFalse);
      expect(
        g.state.generatedImages[1].seed,
        r.gateway.submissions.single['seeds'][1],
      );

      r.gateway.status[r.gateway.itemIds[0]] = 'success';
      expect((await run).succeeded, isTrue);
    });

    test(
      'an image that arrives after the account changed is dropped',
      () async {
        final r = await rig();
        final g = r.generation;
        g.updateBackendUserId(1);
        g.promptController.text = '1girl';
        r.gateway.imageGate = Completer<void>();
        final run = g.generate();
        await eventually(() => g.state.generatedImages.length == 1);
        r.gateway.setAll('success');
        await eventually(() => r.gateway.imageRequests > 0);

        g.updateBackendUserId(2);
        expect(g.state.generatedImages, isEmpty);
        expect(g.state.isGenerating, isFalse);
        r.gateway.imageGate!.complete();
        await run;

        expect(g.state.generatedImages, isEmpty);
        expect(g.state.generatedImage, isNull);
      },
    );

    test('the saved metadata is the one of the submitted request', () async {
      final r = await rig();
      final g = r.generation;
      g.promptController.text = 'cat';
      r.gateway.imageGate = Completer<void>();
      final run = g.generate();
      await eventually(() => g.state.generatedImages.length == 1);

      // The form is edited while the image is still on its way.
      g.promptController.text = 'dog';
      g.updateSettings(steps: 12, scale: 9, isStyleEnabled: true);
      r.gateway.setAll('success');
      r.gateway.imageGate!.complete();
      await run;

      final metadata = g.state.generatedImages.single.metadata!;
      expect(metadata['prompt'], 'cat');
      expect(metadata['steps'], 28);
      expect(metadata['scale'], 5.0);
      expect(metadata['is_style_enabled'], isFalse);
      expect(metadata['seed'], r.gateway.submissions.single['seeds'].single);
    });
  });

  group('saving', () {
    test('keeps the image it was asked for when the selection moves', () async {
      final r = await rig();
      final g = r.generation;
      g.promptController.text = '1girl';
      g.updateSettings(batchCount: 2);
      r.gateway.autoComplete = true;
      await g.generate(batchLimit: 2);
      final first = g.state.generatedImages[0];
      final second = g.state.generatedImages[1];
      g.selectGeneratedImage(first.id);

      // SAVE on the first image; before the write finishes another is shown.
      final saving = g.saveImage(first.id);
      g.selectGeneratedImage(second.id);
      final basename = await saving;

      expect(g.state.generatedImages[0].saved, isTrue);
      expect(g.state.generatedImages[0].savedBasename, basename);
      expect(g.state.generatedImages[1].saved, isFalse);
      expect(r.savedFiles.map((file) => file.uri.pathSegments.last), [
        basename,
      ]);

      // Adding to an album saves once, not again each time.
      expect(await g.ensureSavedAndGetBasename(first.id), basename);
      expect(await g.ensureSavedAndGetBasename(first.id), basename);
      expect(r.savedFiles, hasLength(1));
      final other = await g.ensureSavedAndGetBasename(second.id);
      expect(other, isNot(basename));
      expect(g.state.generatedImages[1].saved, isTrue);
      expect(r.savedFiles, hasLength(2));
    });
  });

  group('cancelling and giving up', () {
    test('queued images of a gateway batch can be cancelled', () async {
      final r = await rig();
      final g = r.generation;
      g.promptController.text = '1girl';
      g.updateSettings(batchCount: 3);
      final run = g.generate(batchLimit: 3);
      await eventually(() => g.state.generatedImages.length == 3);
      r.gateway.status[r.gateway.itemIds[0]] = 'running';
      await eventually(
        () =>
            g.state.generatedImages[0].progress ==
            GenerationTaskProgress.generating,
      );
      expect(g.canCancelQueued, isTrue);

      await g.cancelQueued();

      expect(r.gateway.cancelCalls, 1);
      final items = g.state.generatedImages;
      expect(items[0].progress, GenerationTaskProgress.generating);
      expect(items[0].isLoading, isTrue);
      expect(items[1].progress, GenerationTaskProgress.cancelled);
      expect(items[2].progress, GenerationTaskProgress.cancelled);
      expect(g.canCancelQueued, isFalse);

      r.gateway.status[r.gateway.itemIds[0]] = 'success';
      final outcome = await run;
      expect(outcome.completed, 1);
      expect(outcome.failed, 2);
      expect(g.state.isGenerating, isFalse);
    });

    test('a batch the client stops following can be followed again', () async {
      final r = await rig(timeout: const Duration(milliseconds: 150));
      final g = r.generation;
      g.promptController.text = '1girl';

      final outcome = await g.generate();

      expect(outcome.succeeded, isFalse);
      expect(g.state.isGenerating, isFalse);
      expect(g.state.generatedImages.single.retryable, isTrue);
      expect(g.state.generatedImages.single.isLoading, isFalse);
      expect(g.canResumeWatching, isTrue);

      r.gateway.setAll('success');
      await g.resumeWatching();

      expect(g.state.generatedImages.single.isComplete, isTrue);
      expect(g.state.generatedImages.single.retryable, isFalse);
      expect(g.canResumeWatching, isFalse);
    });

    test('a failed item says why, from the server error code', () async {
      final r = await rig();
      final g = r.generation;
      g.promptController.text = '1girl';
      final run = g.generate();
      await eventually(() => g.state.generatedImages.length == 1);

      final id = r.gateway.itemIds.single;
      r.gateway.status[id] = 'failed';
      r.gateway.errorCode[id] = 'interrupted';
      final outcome = await run;

      expect(outcome.failed, 1);
      expect(
        g.state.generatedImages.single.progress,
        GenerationTaskProgress.failed,
      );
      expect(g.state.generatedImages.single.errorMessage, isNotEmpty);
      expect(g.state.generatedImages.single.retryable, isFalse);
    });
  });

  group('direct to NovelAI', () {
    Future<(RigGeneration, _DirectService)> direct() async {
      final service = _DirectService('', png);
      final g = RigGeneration(
        preferences: await testPreferences(),
        dir: dir.path,
        serviceFactory: (_) => service,
      );
      await g.initialized;
      await g.toggleAutoSave(false);
      g.updateSettings(isStyleEnabled: false);
      addTearDown(g.dispose);
      return (g, service);
    }

    test('a batch sends one request at a time', () async {
      final (g, service) = await direct();
      g.updateSettings(batchCount: 3);

      final outcome = await g.generate(batchLimit: 3);

      expect(outcome.completed, 3);
      expect(service.calls, 3);
      expect(service.maxInFlight, 1);
    });

    test('cancelling stops before the next request', () async {
      final (g, service) = await direct();
      g.updateSettings(batchCount: 3);
      service.gate = Completer<void>();
      final run = g.generate(batchLimit: 3);
      await eventually(() => service.inFlight == 1);
      expect(g.canCancelQueued, isTrue);

      await g.cancelQueued();
      service.gate!.complete();
      final outcome = await run;

      expect(service.calls, 1);
      expect(outcome.completed, 1);
      expect(
        g.state.generatedImages.map((item) => item.progress).skip(1),
        everyElement(GenerationTaskProgress.cancelled),
      );
    });
  });

  group('callers with their own prompts', () {
    test('leave the prompt boxes and the batch size alone', () async {
      final r = await rig();
      final g = r.generation;
      r.gateway.autoComplete = true;
      g.promptController.text = 'main prompt';
      g.negativePromptController.text = 'main negative';
      g.updateSettings(batchCount: 4);

      final outcome = await g.generate(
        prompt: 'photoshoot prompt',
        negativePrompt: 'photoshoot negative',
      );

      expect(outcome.succeeded, isTrue);
      final request = r.gateway.submissions.single['request'] as Map;
      expect(request['input'], 'photoshoot prompt');
      expect((request['parameters'] as Map)['uc'], 'photoshoot negative');
      expect(r.gateway.submissions.single['seeds'], hasLength(1));
      expect(g.promptController.text, 'main prompt');
      expect(g.negativePromptController.text, 'main negative');
      expect(g.state.batchCount, 4);
    });
  });

  group('seeds', () {
    test('a seed box that is not a seed stops the generation', () async {
      final r = await rig();
      final g = r.generation;
      g.promptController.text = '1girl';
      g.updateSettings(randomizeSeed: false);

      for (final text in ['', 'abc', '4294967296', '9223372036854775808']) {
        g.seedController.text = text;
        final outcome = await g.generate();
        expect(outcome.rejected, isTrue, reason: text);
      }
      expect(r.gateway.submissions, isEmpty);
      expect(g.state.errorMessage, isNotNull);
      expect(g.state.isGenerating, isFalse);
    });

    test('the box shows the seed of the selected image', () async {
      final r = await rig();
      final g = r.generation;
      g.promptController.text = '1girl';
      g.updateSettings(batchCount: 2);
      r.gateway.autoComplete = true;
      await g.generate(batchLimit: 2);
      final seeds = [for (final item in g.state.generatedImages) item.seed!];
      expect(g.seedController.text, '${seeds[1]}');

      g.selectGeneratedImage(g.state.generatedImages[0].id);
      expect(g.seedController.text, '${seeds[0]}');

      g.reuseSeed(g.state.generatedImages[0].id);
      expect(g.state.randomizeSeed, isFalse);
      expect(g.seedController.text, '${seeds[0]}');
    });
  });
}
