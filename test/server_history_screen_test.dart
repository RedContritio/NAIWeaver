import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/backend_auth_api.dart';
import 'package:naiweaver/core/services/backend_history_api.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/auth/backend_auth_notifier.dart';
import 'package:naiweaver/features/generation/providers/generation_notifier.dart';
import 'package:naiweaver/features/generation/services/metadata_import_service.dart';
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
      Uint8List.fromList([1, 2, 3]);
}

class _FakeGenerationNotifier extends ChangeNotifier
    implements GenerationNotifier {
  @override
  GenerationState state = GenerationState();

  @override
  final TextEditingController seedController = TextEditingController();

  Set<ImportCategory>? importedCategories;

  @override
  Future<MetadataImportResult> parseImageMetadataBytes(Uint8List bytes) async {
    return MetadataImportResult(
      prompt: 'prompt',
      negativePrompt: '',
      imageBytes: bytes,
    );
  }

  @override
  void applyImportedMetadata(
    MetadataImportResult result,
    Set<ImportCategory> categories,
  ) {
    importedCategories = categories;
  }

  @override
  void dispose() {
    seedController.dispose();
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

ServerHistoryItem _item({
  required String id,
  String? batchId,
  int? batchIndex,
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
    seed: seed ?? batchIndex ?? 42,
    hasImage: hasImage,
    createdAt: '2026-08-25T12:00:00Z',
    completedAt: null,
    batchId: batchId,
    batchIndex: batchIndex,
    errorMessage: 'failed',
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
          _item(id: 'batch-1', batchId: 'batch-a', batchIndex: 0),
          _item(id: 'batch-2', batchId: 'batch-a', batchIndex: 1),
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
      expect(find.text('shared prompt'), findsNWidgets(2));

      await tester.tap(
        find.byKey(const ValueKey('history-entry-batch:batch-a')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ResultSetViewer), findsOneWidget);
      expect(
        find.byKey(const ValueKey('result-set-thumbnail-batch-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('result-set-thumbnail-batch-2')),
        findsOneWidget,
      );
      final viewerActions = find.byKey(
        const ValueKey<String>('history-viewer-actions'),
      );
      expect(viewerActions, findsOneWidget);
      expect(
        find.descendant(
          of: viewerActions,
          matching: find.byIcon(Icons.layers_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: viewerActions,
          matching: find.byIcon(Icons.image_outlined),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('image-level import applies the selected history seed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final generation = _FakeGenerationNotifier();
    addTearDown(generation.dispose);
    final page = ServerHistoryPage(
      items: [_item(id: 'single', hasImage: true, seed: 987654)],
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
          ChangeNotifierProvider<GenerationNotifier>.value(value: generation),
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
    await tester.tap(
      find.descendant(of: card, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import Parameters'));
    await tester.pumpAndSettle();

    expect(generation.importedCategories, contains(ImportCategory.seed));
    expect(generation.seedController.text, '987654');
  });
}
