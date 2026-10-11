import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/backend_auth_api.dart';
import 'package:naiweaver/core/services/backend_history_api.dart';
import 'package:naiweaver/core/services/client_diagnostics.dart';
import 'package:naiweaver/core/widgets/syntax_highlight_controller.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/auth/backend_auth_notifier.dart';
import 'package:naiweaver/features/generation/providers/generation_notifier.dart';
import 'package:naiweaver/features/generation/services/metadata_import_service.dart';
import 'package:naiweaver/features/generation/widgets/generation_results_workspace.dart';
import 'package:naiweaver/features/generation/widgets/result_set_viewer.dart';
import 'package:naiweaver/features/history/server_history_screen.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHistoryApi extends BackendHistoryApi {
  _FakeHistoryApi(this.page);

  final ServerHistoryPage page;

  @override
  Future<ServerHistoryPage> fetchHistoryPage({
    int limit = 20,
    int offset = 0,
    int? userId,
    bool allUsers = false,
    bool currentBatch = false,
  }) async => page;

  @override
  Future<Uint8List> fetchImageBytes(String id) async =>
      throw StateError('Parameter import must not fetch an image');
}

class _FakeGenerationNotifier extends ChangeNotifier
    implements GenerationNotifier {
  _FakeGenerationNotifier({this.failParsing = false});
  final bool failParsing;
  @override
  final SyntaxHighlightController promptController =
      SyntaxHighlightController();
  @override
  final SyntaxHighlightController negativePromptController =
      SyntaxHighlightController();
  @override
  GenerationState state = GenerationState();

  @override
  final TextEditingController seedController = TextEditingController();

  Set<ImportCategory>? importedCategories;
  MetadataImportResult? importedResult;

  @override
  MetadataImportResult parseHistoryParameters(ServerHistoryItem item) {
    if (failParsing) throw const FormatException('isolated fixture error');
    return MetadataImportService().parseGenerationParameters(
      item.generationMetadata,
    );
  }

  @override
  void applyImportedMetadata(
    MetadataImportResult result,
    Set<ImportCategory> categories,
  ) {
    importedCategories = categories;
    importedResult = result;
    promptController.text = result.prompt;
    negativePromptController.text = result.negativePrompt;
  }

  @override
  void dispose() {
    seedController.dispose();
    promptController.dispose();
    negativePromptController.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthNotifier extends BackendAuthNotifier {
  @override
  AuthUser? get user =>
      const AuthUser(id: 7, username: 'owner', isAdmin: false, permissions: []);
}

/// A row as the gateway returns it: every item has a `batch_id`, and only a
/// batch of several images has `batch_size > 1`.
ServerHistoryItem _item({
  required String id,
  String? batchId,
  int batchIndex = 0,
  int batchSize = 1,
  bool hasImage = false,
  int? seed,
}) {
  return ServerHistoryItem(
    id: id,
    userId: 7,
    username: 'owner',
    mode: 'generate',
    status: 'failed',
    prompt: 'shared prompt',
    negativePrompt: '',
    width: 832,
    height: 1216,
    steps: 28,
    scale: 5,
    sampler: 'k_euler',
    seed: seed ?? batchIndex,
    hasImage: hasImage,
    createdAt: '2026-08-25T12:00:00Z',
    completedAt: null,
    batchId: batchId ?? 'batch-of-$id',
    batchIndex: batchIndex,
    batchSize: batchSize,
    errorCode: 'upstream_error',
  );
}

void main() {
  testWidgets(
    'history renders one grid cell per batch and opens shared viewer',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PreferencesService(
        await SharedPreferences.getInstance(),
        const FlutterSecureStorage(),
      );
      final page = ServerHistoryPage(
        items: [
          _item(
            id: 'batch-1',
            batchId: 'batch-a',
            batchIndex: 0,
            batchSize: 4,
            hasImage: true,
          ),
          _item(
            id: 'batch-2',
            batchId: 'batch-a',
            batchIndex: 1,
            batchSize: 4,
            hasImage: true,
          ),
          _item(
            id: 'batch-3',
            batchId: 'batch-a',
            batchIndex: 2,
            batchSize: 4,
            hasImage: true,
          ),
          _item(
            id: 'batch-4',
            batchId: 'batch-a',
            batchIndex: 3,
            batchSize: 4,
            hasImage: true,
          ),
          _item(id: 'single'),
        ],
        total: 2,
        limit: 20,
        offset: 0,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
              create: (_) => ThemeNotifier(preferences),
            ),
            ChangeNotifierProvider<BackendAuthNotifier>(
              create: (_) => _FakeAuthNotifier(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: ServerHistoryScreen(api: _FakeHistoryApi(page)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('history-entry-batch:batch-a')),
        findsOne,
      );
      expect(find.byKey(const ValueKey('history-entry-item:single')), findsOne);
      expect(find.text('shared prompt'), findsNothing);
      final batchCard = find.byKey(
        const ValueKey('history-entry-batch:batch-a'),
      );
      for (var index = 1; index <= 4; index += 1) {
        expect(
          find.byKey(
            ValueKey<String>('history-collage-batch:batch-a-batch-$index'),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: batchCard, matching: find.byIcon(Icons.more_horiz)),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('history-entry-batch:batch-a')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ResultSetWorkspace), findsOneWidget);
      expect(find.byType(ResultSetViewer), findsNothing);
      expect(
        find.byKey(const ValueKey('result-set-thumbnail-batch-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('result-set-thumbnail-batch-2')),
        findsOneWidget,
      );
      final batchActions = find.byKey(
        const ValueKey<String>('history-batch-actions'),
      );
      final firstItemActions = find.byKey(
        const ValueKey<String>('history-grid-item-actions-batch-1'),
      );
      expect(batchActions, findsOneWidget);
      expect(firstItemActions, findsOneWidget);
      for (var index = 1; index <= 4; index += 1) {
        expect(
          find.byKey(
            ValueKey<String>('history-grid-item-actions-batch-$index'),
          ),
          findsOneWidget,
        );
      }

      await tester.tap(firstItemActions);
      await tester.pumpAndSettle();
      expect(find.text('Import Parameters'), findsOneWidget);
      expect(find.text('Import Batch Parameters'), findsNothing);
      await tester.tapAt(const Offset(8, 300));
      await tester.pumpAndSettle();

      await tester.tap(batchActions);
      await tester.pumpAndSettle();
      expect(find.text('Import Batch Parameters'), findsOneWidget);
      expect(find.text('Import Parameters'), findsNothing);
      await tester.tapAt(const Offset(8, 300));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Viewer'));
      await tester.pumpAndSettle();
      expect(find.byType(ResultSetViewer), findsOneWidget);
      expect(batchActions, findsNothing);
      expect(firstItemActions, findsNothing);

      final itemActions = find.byKey(
        const ValueKey<String>('history-item-actions'),
      );
      expect(itemActions, findsOneWidget);
      await tester.tap(itemActions);
      await tester.pumpAndSettle();
      expect(find.text('Import Parameters'), findsOneWidget);
      expect(find.text('Import Batch Parameters'), findsNothing);
    },
  );

  for (final failParsing in [false, true]) {
    testWidgets(
      failParsing
          ? 'import failure records its stage without prompt contents'
          : 'image-level import applies the selected history seed',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final preferences = PreferencesService(
          await SharedPreferences.getInstance(),
          const FlutterSecureStorage(),
        );
        ClientDiagnostics.instance.clear();
        final generation = _FakeGenerationNotifier(failParsing: failParsing);
        addTearDown(generation.dispose);
        final page = ServerHistoryPage(
          items: [_item(id: 'single', hasImage: false, seed: 987654)],
          total: 1,
          limit: 20,
          offset: 0,
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeNotifier>(
                create: (_) => ThemeNotifier(preferences),
              ),
              ChangeNotifierProvider<BackendAuthNotifier>(
                create: (_) => _FakeAuthNotifier(),
              ),
              ChangeNotifierProvider<GenerationNotifier>.value(
                value: generation,
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: ServerHistoryScreen(api: _FakeHistoryApi(page)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final card = find.byKey(const ValueKey('history-entry-item:single'));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        final menu = find.descendant(
          of: card,
          matching: find.byType(PopupMenuButton<String>),
        );
        await mouse.moveTo(tester.getCenter(menu));
        await tester.pumpAndSettle();
        await mouse.down(tester.getCenter(menu));
        await mouse.up();
        await tester.pumpAndSettle();
        final importAction = find.text('Import Parameters');
        await mouse.moveTo(tester.getCenter(importAction));
        await tester.pumpAndSettle();
        await mouse.down(tester.getCenter(importAction));
        await mouse.up();
        await tester.pumpAndSettle();

        final events = ClientDiagnostics.instance.snapshot();
        if (failParsing) {
          final failure = events.singleWhere(
            (e) => e['event'] == 'history_parameter_import_failed',
          );
          expect(failure['details']['stage'], 'parse_parameters');
          expect(failure['details']['error_category'], 'format');
          expect(events.toString(), isNot(contains('shared prompt')));
          expect(generation.importedCategories, isNull);
          return;
        }
        expect(
          events.where((e) => e['event'] == 'history_parameter_import_applied'),
          hasLength(1),
        );
        expect(
          events.where((e) => e['event'] == 'history_parameter_import_failed'),
          isEmpty,
        );
        expect(generation.importedCategories, contains(ImportCategory.seed));
        expect(generation.seedController.text, '987654');
        expect(generation.importedResult?.prompt, 'shared prompt');
        expect(generation.importedResult?.width, 832);
        expect(generation.importedResult?.height, 1216);
        expect(generation.importedResult?.steps, 28);
        expect(generation.importedResult?.scale, 5);
        expect(generation.importedResult?.sampler, 'k_euler');
      },
    );
  }
}
