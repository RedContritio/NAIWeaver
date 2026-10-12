import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:naiweaver/core/gateway/backend_permissions.dart';
import 'package:naiweaver/core/gateway/backend_rules.dart';
import 'package:naiweaver/core/services/backend_history_api.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';
import 'package:naiweaver/core/services/styles.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/services/wildcard_service.dart';
import 'package:naiweaver/features/director_ref/models/director_reference.dart';
import 'package:naiweaver/features/director_ref/providers/director_ref_notifier.dart';
import 'package:naiweaver/features/generation/models/generation_quote.dart';
import 'package:naiweaver/features/generation/models/nai_character.dart';
import 'package:naiweaver/features/generation/providers/generation_notifier.dart';
import 'package:naiweaver/features/gallery/providers/gallery_notifier.dart';
import 'package:naiweaver/features/generation/services/reference_access_monitor.dart';
import 'package:naiweaver/features/generation/widgets/settings_panel.dart';
import 'package:naiweaver/features/vibe_transfer/models/vibe_transfer.dart';
import 'package:naiweaver/features/vibe_transfer/providers/vibe_transfer_notifier.dart';

import 'support/fake_gateway_adapter.dart';
import 'test_harness.dart';

class _Tags extends TagService {
  _Tags() : super(filePath: 'isolated-tags');

  @override
  Future<void> loadTags() async {}
}

class _Generation extends GenerationNotifier {
  _Generation({
    required super.preferences,
    required super.stylesFilePath,
    required super.serviceFactory,
    required super.historyApi,
  }) : super(
         tagService: _Tags(),
         wildcardService: WildcardService(wildcardDir: 'isolated-wildcards'),
         outputDir: 'isolated-output',
         presetsFilePath: 'isolated-presets',
       );

  @override
  Future<void> fetchAnlas() async {}
}

const _freeOnly = GenerationAccess(
  canFree: true,
  paid: PaidImageAccess.noPermission,
);
const _canPay = GenerationAccess(canFree: true, paid: PaidImageAccess.allowed);

Map<String, dynamic> _acceptedTask() => {
  'task_id': 'task-1',
  'status': 'queued',
  'items': [
    {'id': 'item-1', 'batch_index': 0, 'status': 'queued'},
  ],
};

/// The item has already failed, so the poll loop ends after one fetch.
Map<String, dynamic> _failedTask() => {
  'id': 'task-1',
  'status': 'failed',
  'items': [
    {
      'id': 'item-1',
      'batch_index': 0,
      'status': 'failed',
      'error_code': 'upstream_error',
    },
  ],
};

class _Rig {
  _Rig(this.generation, this.adapter, this.directors, this.vibes, this.monitor);

  final GenerationNotifier generation;
  final FakeGatewayAdapter adapter;
  final DirectorRefNotifier directors;
  final VibeTransferNotifier vibes;
  final ReferenceAccessMonitor monitor;

  /// The JSON bodies of the generation submissions, in order.
  List<Map<String, dynamic>> get submissions => [
    for (final r in adapter.requests)
      if (r.method == 'POST' && r.uri.path == '/api/generation-tasks')
        r.data as Map<String, dynamic>,
  ];
}

Future<_Rig> _rig(
  Directory dir,
  ResponseBody Function(RequestOptions options) onSubmit, {
  GenerationAccess access = _canPay,
  List<PromptStyle> styles = const [],
}) async {
  final adapter = FakeGatewayAdapter((options) {
    if (options.method == 'POST' &&
        options.uri.path == '/api/generation-tasks') {
      return onSubmit(options);
    }
    if (options.uri.path == '/api/generation-tasks/task-1') {
      return jsonResponse(_failedTask());
    }
    return jsonResponse(gatewayError('not_found'), status: 404);
  });
  final client = clientOver(adapter);
  final stylesPath = '${dir.path}/styles.json';
  await StyleStorage.saveStyles(stylesPath, styles);
  final generation = _Generation(
    preferences: await testPreferences(),
    stylesFilePath: stylesPath,
    serviceFactory: (key) => NovelAIService(key, client: client, gateway: true),
    historyApi: BackendHistoryApi(client: client),
  );
  // Not disposed: its initial load is still finishing when the test ends.
  final directors = DirectorRefNotifier();
  final vibes = VibeTransferNotifier();
  generation.updateDirectorRefNotifier(directors);
  generation.updateVibeTransferNotifier(vibes);
  generation.updateGatewayAccess(ImageRules.tryParse(rulesJson()), access);
  // The initial data (styles) loads asynchronously.
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (generation.state.styles.length != styles.length) {
    if (DateTime.now().isAfter(deadline)) fail('styles never loaded');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  final monitor = ReferenceAccessMonitor(references: directors, vibes: vibes)
    ..update(access.paid);
  return _Rig(generation, adapter, directors, vibes, monitor);
}

DirectorReference _reference(String id, {bool enabled = true}) =>
    DirectorReference(
      id: id,
      originalImageBytes: Uint8List.fromList([1]),
      processedBase64: 'processed-$id',
      enabled: enabled,
    );

VibeTransfer _vibe(String id, {bool enabled = true}) => VibeTransfer(
  id: id,
  originalImageBytes: Uint8List.fromList([1]),
  processedPreview: Uint8List.fromList([1]),
  vibeVectorBase64: 'vector-$id',
  enabled: enabled,
);

NaiCharacter _character(String prompt) =>
    NaiCharacter(prompt: prompt, uc: '', center: NaiCoordinate(x: 0.5, y: 0.5));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('naiweaver_billing'));
  tearDown(() => dir.deleteSync(recursive: true));

  ResponseBody accept(RequestOptions _) =>
      jsonResponse(_acceptedTask(), status: 202);

  group('the request that is sent', () {
    test('merges only the active styles and the negative prompts', () async {
      final rig = await _rig(
        dir,
        accept,
        styles: [
          PromptStyle(
            name: 'On',
            prefix: 'pre, ',
            suffix: ', suf',
            negativeContent: 'style-neg',
          ),
          PromptStyle(
            name: 'Off',
            prefix: 'other-pre, ',
            negativeContent: 'other-neg',
          ),
        ],
      );
      final generation = rig.generation;
      generation.promptController.text = '1girl';
      generation.negativePromptController.text = 'lowres';
      generation.updateSettings(
        activeStyleNames: ['On'],
        characters: [_character('boy'), _character('cat')],
      );

      await generation.generate(batchLimit: 1);

      final request = rig.submissions.single['request'] as Map<String, dynamic>;
      final parameters = request['parameters'] as Map<String, dynamic>;
      expect(request['input'], 'pre, 1girl, suf');
      expect(parameters['uc'], 'lowres, style-neg');
      expect((parameters['characterPrompts'] as List).map((c) => c['prompt']), [
        'boy',
        'cat',
      ]);

      generation.updateSettings(isStyleEnabled: false);
      await generation.generate(batchLimit: 1);
      final plain = rig.submissions.last['request'] as Map<String, dynamic>;
      expect(plain['input'], '1girl');
      expect((plain['parameters'] as Map<String, dynamic>)['uc'], 'lowres');
    });

    test('carries only the references the account can send', () async {
      final rig = await _rig(dir, accept);
      await rig.directors.setReferences([
        _reference('on'),
        _reference('off', enabled: false),
      ]);
      rig.vibes.setVibes([_vibe('on')]);
      rig.generation.promptController.text = '1girl';

      await rig.generation.generate(batchLimit: 1);
      var parameters =
          (rig.submissions.last['request']
                  as Map<String, dynamic>)['parameters']
              as Map<String, dynamic>;
      expect(parameters['director_reference_images'], ['processed-on']);
      expect(parameters['reference_image_multiple'], ['vector-on']);

      rig.monitor.update(PaidImageAccess.noRedPoints);
      await rig.generation.generate(batchLimit: 1);
      parameters =
          (rig.submissions.last['request']
                  as Map<String, dynamic>)['parameters']
              as Map<String, dynamic>;
      expect(parameters, isNot(contains('director_reference_images')));
      expect(parameters, isNot(contains('reference_image_multiple')));
      // The user's own switches and the items themselves are untouched.
      expect(rig.directors.references.map((r) => r.enabled), [true, false]);
      expect(rig.vibes.vibes.map((v) => v.enabled), [true]);

      rig.monitor.update(PaidImageAccess.allowed);
      await rig.generation.generate(batchLimit: 1);
      parameters =
          (rig.submissions.last['request']
                  as Map<String, dynamic>)['parameters']
              as Map<String, dynamic>;
      expect(parameters['director_reference_images'], ['processed-on']);
      expect(parameters['reference_image_multiple'], ['vector-on']);
    });
  });

  group('the price', () {
    test('is what the request costs, and it is submitted', () async {
      final rig = await _rig(dir, accept);
      await rig.directors.setReferences([_reference('a'), _reference('b')]);
      rig.generation.promptController.text = '1girl';

      final shown = rig.generation.quote!.quote!;
      expect(shown.directorRefs, 10);

      await rig.generation.generate(batchLimit: 1);

      expect(rig.submissions.single['expected_quote'], {
        'mode': shown.mode,
        'points': shown.points,
      });
    });

    test(
      'a paused reference does not make the request cost red points',
      () async {
        final rig = await _rig(dir, accept, access: _freeOnly);
        await rig.directors.setReferences([_reference('a')]);

        final quote = rig.generation.quote!;
        expect(quote.quote!.isPaid, isFalse);
        expect(quote.blocked, isFalse);
      },
    );

    test('a free-only account is blocked until the user adjusts', () async {
      final rig = await _rig(dir, accept, access: _freeOnly);
      rig.generation.updateSettings(width: 1536, height: 1024, steps: 40);

      var quote = rig.generation.quote!;
      expect(quote.blocked, isTrue);
      expect(quote.canAdjustToFree, isTrue);
      // Building and reading the quote changed nothing.
      expect(rig.generation.state.width, 1536);
      expect(rig.generation.state.steps, 40);

      rig.generation.adjustToFreeParameters();
      quote = rig.generation.quote!;
      expect(quote.blocked, isFalse);
      expect(rig.generation.state.steps, 28);
    });
  });

  group('when the gateway prices the request differently', () {
    ResponseBody changeThenAccept(RequestOptions options) {
      final first = options.data['expected_quote']['points'] != 30;
      return first
          ? jsonResponse(
              gatewayError(
                'quote_changed',
                extra: {
                  'quote': {
                    'mode': 'paid',
                    'points': 30,
                    'reasons': ['allowance_exhausted'],
                  },
                },
              ),
              status: 409,
            )
          : jsonResponse(_acceptedTask(), status: 202);
    }

    test('submits again at the gateway price once the user agrees', () async {
      final rig = await _rig(dir, changeThenAccept);
      rig.generation.promptController.text = '1girl';
      QuoteConfirmation? asked;

      await rig.generation.generate(
        batchLimit: 1,
        confirmQuote: (confirmation) async {
          asked = confirmation;
          return true;
        },
      );

      expect(asked!.serverPoints, 30);
      expect(asked!.allowanceExhausted, isTrue);
      expect(rig.submissions, hasLength(2));
      expect(rig.submissions.last['expected_quote'], {
        'mode': 'paid',
        'points': 30,
      });
      expect(rig.generation.state.errorMessage, isNull);
    });

    test('submits nothing more when the user declines', () async {
      final rig = await _rig(dir, changeThenAccept);
      rig.generation.promptController.text = '1girl';

      await rig.generation.generate(
        batchLimit: 1,
        confirmQuote: (_) async => false,
      );

      expect(rig.submissions, hasLength(1));
      expect(rig.generation.state.errorMessage, isNull);
    });

    test('does not offer red points to an account that cannot pay', () async {
      final rig = await _rig(
        dir,
        (_) => jsonResponse(
          gatewayError(
            'free_allowance_exhausted',
            extra: {
              'quote': {'mode': 'paid', 'points': 30},
            },
          ),
          status: 409,
        ),
        access: _freeOnly,
      );
      rig.generation.promptController.text = '1girl';
      var asked = false;

      await rig.generation.generate(
        batchLimit: 1,
        confirmQuote: (_) async => asked = true,
      );

      expect(asked, isFalse);
      expect(rig.submissions, hasLength(1));
      expect(rig.generation.state.errorMessage, isNotNull);
    });

    test('shows a full queue without asking', () async {
      final rig = await _rig(
        dir,
        (_) => jsonResponse(
          gatewayError('queue_full', extra: {'limit': 3}),
          status: 429,
        ),
      );
      rig.generation.promptController.text = '1girl';
      var asked = false;

      await rig.generation.generate(
        batchLimit: 1,
        confirmQuote: (_) async => asked = true,
      );

      expect(asked, isFalse);
      expect(rig.generation.state.errorMessage, isNotNull);
    });
  });

  group('access changes', () {
    test('are announced once, never deleting anything', () async {
      final rig = await _rig(dir, accept);
      await rig.directors.setReferences([_reference('a'), _reference('b')]);
      rig.vibes.setVibes([_vibe('a')]);
      var notices = 0;
      rig.monitor.addListener(() => notices++);

      rig.monitor.update(PaidImageAccess.noRedPoints);
      expect(notices, 1);
      expect(rig.monitor.notice!.references, 2);
      expect(rig.monitor.notice!.vibes, 1);
      expect(rig.monitor.notice!.resumed, isFalse);
      rig.monitor.acknowledge();

      // Still without access (even for another reason): nothing new to say.
      rig.monitor.update(PaidImageAccess.noPermission);
      rig.monitor.update(PaidImageAccess.noPermission);
      expect(notices, 1);

      rig.monitor.update(PaidImageAccess.allowed);
      expect(notices, 2);
      expect(rig.monitor.notice!.resumed, isTrue);
      expect(rig.directors.references, hasLength(2));
      expect(rig.vibes.vibes, hasLength(1));
    });

    testWidgets(
      'building the settings never changes the parameters or inputs',
      (tester) async {
        final rig = await tester.runAsync(
          () => _rig(dir, accept, access: _freeOnly),
        );
        final generation = rig!.generation;
        await tester.runAsync(
          () => rig.directors.setReferences([_reference('a')]),
        );
        rig.vibes.setVibes([_vibe('a')]);
        generation.updateSettings(width: 1536, height: 1024, steps: 40);

        final gallery = GalleryNotifier(
          outputDir: dir.path,
          prefs: await testPreferences(),
        );
        await pumpHarness(
          tester,
          ExpandedSettingsContent(
            group: GenerationSettingsGroup.parameters,
            onManageStyles: () {},
            onSavePreset: () {},
          ),
          size: const Size(1800, 1400),
          providers: [
            ChangeNotifierProvider.value(value: generation),
            ChangeNotifierProvider.value(value: rig.directors),
            ChangeNotifierProvider.value(value: rig.vibes),
            ChangeNotifierProvider.value(value: gallery),
          ],
        );
        await tester.pump();

        // The account can only generate for free: it is told so and offered the
        // adjustment, but nothing was changed on its behalf.
        expect(find.text('ADJUST TO FREE PARAMETERS'), findsOneWidget);
        expect(generation.state.width, 1536);
        expect(generation.state.height, 1024);
        expect(generation.state.steps, 40);
        expect(rig.directors.references, hasLength(1));
        expect(rig.vibes.vibes, hasLength(1));

        await tester.tap(find.text('ADJUST TO FREE PARAMETERS'));
        await tester.pump();
        expect(generation.state.steps, 28);
        expect(find.text('ADJUST TO FREE PARAMETERS'), findsNothing);
      },
    );
  });
}
