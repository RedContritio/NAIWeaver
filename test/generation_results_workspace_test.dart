import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/generation/providers/generation_notifier.dart';
import 'package:naiweaver/features/generation/widgets/generation_results_workspace.dart';
import 'package:naiweaver/features/generation/widgets/browser_photo_swipe_viewer.dart';
import 'package:naiweaver/features/generation/widgets/image_viewer.dart';
import 'package:naiweaver/features/generation/widgets/result_set_viewer.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGenerationNotifier extends ChangeNotifier
    implements GenerationNotifier {
  @override
  GenerationState state;

  _FakeGenerationNotifier(this.state);

  @override
  void selectGeneratedImage(String id, {bool userInitiated = true}) {
    final selected = state.generatedImages.singleWhere((item) => item.id == id);
    state = state.copyWith(
      selectedGeneratedImageId: id,
      generatedImage: selected.bytes,
      clearGeneratedImage: selected.bytes == null,
    );
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'selected pending batch item does not show another completed image',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PreferencesService(
        await SharedPreferences.getInstance(),
        const FlutterSecureStorage(),
      );
      final bytes = File('assets/logo.png').readAsBytesSync();

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeNotifier(preferences),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ResultSetViewer(
                items: [
                  ResultSetViewItem(
                    id: 'complete',
                    position: 1,
                    count: 2,
                    previewImage: MemoryImage(bytes),
                    imageBytes: bytes,
                  ),
                  const ResultSetViewItem(
                    id: 'pending',
                    position: 2,
                    count: 2,
                    isGenerating: true,
                  ),
                ],
                selectedId: 'pending',
                onSelect: (_) {},
                mobile: true,
                pulseAnimation: const AlwaysStoppedAnimation(0),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(BrowserPhotoSwipeViewer), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('result-set-preview-status')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'batch preview and thumbnails share one framed result component',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PreferencesService(
        await SharedPreferences.getInstance(),
        const FlutterSecureStorage(),
      );
      final bytes = File('assets/logo.png').readAsBytesSync();

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeNotifier(preferences),
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ResultSetViewer(
                items: [
                  ResultSetViewItem(
                    id: 'first',
                    position: 1,
                    count: 2,
                    previewImage: MemoryImage(bytes),
                  ),
                  ResultSetViewItem(
                    id: 'second',
                    position: 2,
                    count: 2,
                    previewImage: MemoryImage(bytes),
                  ),
                ],
                selectedId: 'first',
                onSelect: (_) {},
                mobile: true,
                pulseAnimation: const AlwaysStoppedAnimation(0),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final frameFinder = find.byKey(
        const ValueKey<String>('result-set-frame'),
      );
      final previewFinder = find.byKey(
        const ValueKey<String>('result-set-preview'),
      );
      final footerFinder = find.byKey(
        const ValueKey<String>('result-set-thumbnail-footer'),
      );
      final stripFinder = find.byKey(
        const ValueKey<String>('result-set-thumbnail-strip'),
      );
      expect(frameFinder, findsOneWidget);
      expect(previewFinder, findsOneWidget);
      expect(footerFinder, findsOneWidget);
      expect(stripFinder, findsOneWidget);
      expect(
        find.ancestor(of: previewFinder, matching: frameFinder),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: footerFinder, matching: frameFinder),
        findsOneWidget,
      );
      expect(
        tester.getRect(previewFinder).left,
        tester.getRect(footerFinder).left,
      );
      expect(
        tester.getRect(previewFinder).right,
        tester.getRect(footerFinder).right,
      );
      expect(
        tester
            .widget<ImagePreviewViewer>(find.byType(ImagePreviewViewer))
            .framed,
        isFalse,
      );
    },
  );

  testWidgets('grid single tap opens the selected batch image', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final firstBytes = File('assets/logo.png').readAsBytesSync();
    final secondBytes = Uint8List.fromList(firstBytes);
    final notifier = _FakeGenerationNotifier(
      GenerationState(
        generatedImage: firstBytes,
        generatedImages: [
          GeneratedImageItem(
            id: 'first',
            batchIndex: 1,
            batchCount: 2,
            bytes: firstBytes,
            seed: 1,
          ),
          GeneratedImageItem(
            id: 'second',
            batchIndex: 2,
            batchCount: 2,
            bytes: secondBytes,
            seed: 2,
          ),
        ],
        selectedGeneratedImageId: 'first',
      ),
    );
    final promptFocus = FocusNode();
    addTearDown(promptFocus.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
            create: (_) => ThemeNotifier(preferences),
          ),
          ChangeNotifierProvider<GenerationNotifier>.value(value: notifier),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: promptFocus),
                Expanded(
                  child: ListenableBuilder(
                    listenable: notifier,
                    builder: (context, _) => GenerationResultsWorkspace(
                      notifier: notifier,
                      state: notifier.state,
                      mobile: true,
                      pulseAnimation: const AlwaysStoppedAnimation(0),
                      showQuickActions: false,
                      onSelectImage: (id) {
                        promptFocus.unfocus();
                        notifier.selectGeneratedImage(id);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    promptFocus.requestFocus();
    await tester.pump();
    expect(promptFocus.hasFocus, isTrue);

    await tester.tap(find.byKey(const ValueKey('result-set-thumbnail-second')));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(ImagePreviewViewer), findsOneWidget);
    expect(notifier.state.selectedGeneratedImageId, 'second');
    expect(promptFocus.hasFocus, isFalse);
    final photoView = tester.widget<PhotoView>(find.byType(PhotoView));
    expect(photoView.key, const ValueKey<Object>('second'));
    expect((photoView.imageProvider as MemoryImage).bytes, same(secondBytes));

    notifier.state = GenerationState(
      generatedImages: [
        GeneratedImageItem(
          id: 'next-first',
          batchIndex: 1,
          batchCount: 2,
          bytes: firstBytes,
          seed: 3,
        ),
        GeneratedImageItem(
          id: 'next-second',
          batchIndex: 2,
          batchCount: 2,
          bytes: secondBytes,
          seed: 4,
        ),
      ],
      selectedGeneratedImageId: 'next-first',
    );
    notifier.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.byType(ImagePreviewViewer), findsNothing);
    expect(find.byType(ResultSetThumbnail), findsNWidgets(2));
  });
}
