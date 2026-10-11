@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui_web' as ui_web;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/backend_auth_api.dart';
import 'package:naiweaver/core/services/backend_history_api.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/services/wildcard_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/core/widgets/browser_native_text_area_web.dart';
import 'package:naiweaver/features/auth/backend_auth_notifier.dart';
import 'package:naiweaver/features/generation/providers/generation_notifier.dart';
import 'package:naiweaver/features/history/server_history_screen.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:naiweaver/main.dart';
import 'package:naiweaver/features/generation/widgets/generation_mobile_sheet.dart';
import 'package:naiweaver/features/tools/cascade/providers/cascade_notifier.dart';
import 'package:naiweaver/features/director_ref/providers/director_ref_notifier.dart';
import 'package:naiweaver/features/vibe_transfer/providers/vibe_transfer_notifier.dart';
import 'package:naiweaver/features/gallery/providers/gallery_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

// Widget tests do not forward platform-view creation to the browser engine.
// Invoke the registered factories so assertions inspect actual HTML elements.
class _Views implements ui_web.PlatformViewRegistry {
  final factories = <String, Function>{};
  final elements = <int, Object>{};
  @override
  bool registerViewFactory(
    String type,
    Function factory, {
    bool isVisible = true,
  }) {
    factories[type] = factory;
    return true;
  }

  @override
  Object getViewById(int id) => elements[id]!;
  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'create') {
      final args = call.arguments as Map;
      final id = args['id'] as int;
      elements[id] =
          Function.apply(factories[args['viewType']]!, [id]) as Object;
    } else if (call.method == 'dispose') {
      elements.remove(call.arguments);
    }
    return null;
  }
}

class _Tags extends TagService {
  _Tags(this.gate) : super(filePath: 'isolated-tags');
  final Future<void>? gate;
  @override
  Future<void> loadTags() async {
    await gate;
  }
}

class _Generation extends GenerationNotifier {
  _Generation(
    PreferencesService preferences, {
    Future<void>? initializationGate,
  }) : super(
         preferences: preferences,
         tagService: _Tags(initializationGate),
         wildcardService: WildcardService(wildcardDir: 'isolated-wildcards'),
         outputDir: 'isolated-output',
         presetsFilePath: 'isolated-presets',
         stylesFilePath: 'isolated-styles',
       );
  final initialized = Completer<void>();
  @override
  Future<void> fetchAnlas() async {
    initialized.complete();
  }
}

class _Auth extends BackendAuthNotifier {
  @override
  AuthUser? get user => const AuthUser(
    id: 7,
    username: 'fixture',
    isAdmin: false,
    permissions: ['history.read', 'image.generate.free'],
  );
}

class _History extends BackendHistoryApi {
  _History(this.batch);
  final bool batch;
  @override
  Future<Uint8List> fetchImageBytes(String id) async =>
      throw StateError('No image fetch allowed');
  @override
  Future<ServerHistoryPage> fetchHistoryPage({
    int limit = 20,
    int offset = 0,
    int? userId,
    bool allUsers = false,
    bool currentBatch = false,
  }) async => ServerHistoryPage(
    items: List.generate(
      batch ? 2 : 1,
      (i) => ServerHistoryItem.fromJson({
        'id': 'item-$i',
        'user_id': 7,
        'username': 'fixture',
        'status': 'failed',
        'prompt': 'database prompt',
        'negative_prompt': 'database negative',
        'width': 832,
        'height': 1216,
        'steps': 28,
        'scale': 5,
        'sampler': 'k_euler',
        'seed': 456 + i,
        if (batch) 'batch_id': 'batch-a',
        if (batch) 'batch_index': i,
        'request_json': {
          'input': 'database prompt',
          'parameters': {'uc': 'database negative'},
        },
      }),
    ),
    total: 1,
    limit: 20,
    offset: 0,
  );
}

void main() {
  setUp(() {
    final views = _Views();
    ui_web.debugOverridePlatformViewRegistry(views);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, views.handle);
  });
  tearDown(() => ui_web.debugOverridePlatformViewRegistry(null));
  testWidgets('startup still restores the saved session without an import', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_prompt_styles': '[]',
      'saved_generation_presets': '[]',
      'session_snapshot':
          '{"prompt":"saved prompt","negative_prompt":"saved negative","seed":"123"}',
    });
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final generation = _Generation(preferences);
    await tester.pumpAndSettle();
    expect(generation.initialized.isCompleted, isTrue);
    expect(generation.promptController.text, 'saved prompt');
    expect(generation.negativePromptController.text, 'saved negative');
    expect(generation.seedController.text, '123');
    generation.dispose();
  });
  for (final scenario in [
    (false, false, false, false),
    (true, false, false, false),
    (false, true, false, false),
    (true, true, false, false),
    (false, false, true, false),
    (true, false, true, false),
    (false, true, true, false),
    (true, true, true, false),
    (false, false, false, true),
    (true, false, false, true),
    (false, true, false, true),
    (true, true, false, true),
  ]) {
    final (batch, details, slowInitialization, compact) = scenario;
    testWidgets(
      '${batch ? 'batch' : 'single'} import from ${details ? 'details' : 'history'} fills ${compact ? 'compact' : 'desktop'} home browser prompt${slowInitialization ? ' before startup finishes' : ''}',
      (tester) async {
        tester.view.physicalSize = compact
            ? const Size(390, 844)
            : const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'saved_prompt_styles':
              '[{"name":"fixture style","prefix":"style prefix"}]',
          'saved_generation_presets': '[]',
          if (slowInitialization)
            'session_snapshot': '{"prompt":"","negative_prompt":"","seed":""}',
        });
        final preferences = PreferencesService(
          await SharedPreferences.getInstance(),
          const FlutterSecureStorage(),
        );
        final initializationGate = slowInitialization
            ? Completer<void>()
            : null;
        final generation = _Generation(
          preferences,
          initializationGate: initializationGate?.future,
        );
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<PreferencesService>.value(value: preferences),
              ChangeNotifierProvider(create: (_) => CascadeNotifier()),
              ChangeNotifierProvider(create: (_) => DirectorRefNotifier()),
              ChangeNotifierProvider(create: (_) => VibeTransferNotifier()),
              ChangeNotifierProvider(
                create: (_) => GalleryNotifier(
                  outputDir: 'isolated-output',
                  prefs: preferences,
                ),
              ),
              ChangeNotifierProvider<ThemeNotifier>(
                create: (_) => ThemeNotifier(preferences),
              ),
              ChangeNotifierProvider<BackendAuthNotifier>(
                create: (_) => _Auth(),
              ),
              ChangeNotifierProvider<GenerationNotifier>.value(
                value: generation,
              ),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: SimpleGeneratorApp(historyApi: _History(batch)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final mouse = compact
            ? null
            : await tester.createGesture(kind: PointerDeviceKind.mouse);
        if (mouse != null) {
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
        }
        Future<void> click(Finder target) async {
          if (mouse == null) {
            await tester.tap(target);
          } else {
            await mouse.moveTo(tester.getCenter(target));
            await tester.pumpAndSettle();
            await mouse.down(tester.getCenter(target));
            await mouse.up();
          }
        }

        generation.promptController.text = 'before import';
        generation.seedController.text = '999';
        await click(find.text('HISTORY'));
        await tester.pumpAndSettle();
        final card = find.byKey(
          ValueKey(
            batch ? 'history-entry-batch:batch-a' : 'history-entry-item:item-0',
          ),
        );
        if (details) {
          await click(card);
          await tester.pumpAndSettle();
          await click(
            find.byKey(
              ValueKey(
                batch ? 'history-batch-actions' : 'history-item-actions',
              ),
            ),
          );
        } else {
          await click(
            find.descendant(
              of: card,
              matching: find.byType(PopupMenuButton<String>),
            ),
          );
        }
        await tester.pumpAndSettle();
        await click(
          find.text(batch ? 'Import Batch Parameters' : 'Import Parameters'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ServerHistoryScreen), findsNothing);
        initializationGate?.complete();
        await tester.pumpAndSettle();
        expect(
          generation.initialized.isCompleted,
          isTrue,
          reason: 'Startup must finish before checking imported values',
        );
        await tester.pumpAndSettle();
        expect(generation.promptController.text, 'database prompt');
        expect(generation.negativePromptController.text, 'database negative');
        expect(generation.seedController.text, batch ? '999' : '456');
        final prompt = find.byWidgetPredicate(
          (widget) =>
              widget is BrowserNativeTextArea &&
              identical(widget.controller, generation.promptController),
        );
        expect(prompt, findsOneWidget);
        if (compact) {
          expect(
            tester
                .state<GenerationMobileSheetState>(
                  find.byType(GenerationMobileSheet),
                )
                .isExpanded,
            isTrue,
          );
        }
        final surface = tester.widget<PlatformViewSurface>(
          find.descendant(
            of: prompt,
            matching: find.byType(PlatformViewSurface),
          ),
        );
        final textarea =
            ui_web.platformViewRegistry.getViewById(surface.controller.viewId)
                as web.HTMLTextAreaElement;
        expect(textarea.value, 'database prompt');
        expect(generation.state.activeStyleNames, isEmpty);
        expect(generation.state.isStyleEnabled, isFalse);
        expect(generation.state.width, 832);
        if (slowInitialization) {
          await tester.pump(const Duration(seconds: 5));
          final saved =
              jsonDecode(
                    (await SharedPreferences.getInstance()).getString(
                      'session_snapshot',
                    )!,
                  )
                  as Map;
          expect(saved['prompt'], 'database prompt');
          expect(saved['negative_prompt'], 'database negative');
          expect(saved['seed'], batch ? '999' : '456');
        }
        await tester.pumpWidget(const SizedBox());
        generation.dispose();
      },
    );
  }
}
