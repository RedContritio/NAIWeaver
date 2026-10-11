import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naiweaver/core/services/novel_ai_service.dart';
import 'package:naiweaver/core/services/path_service.dart';
import 'package:naiweaver/core/services/reference_library_service.dart';
import 'package:naiweaver/features/director_ref/models/director_reference.dart';
import 'package:naiweaver/features/director_ref/providers/director_ref_notifier.dart';
import 'package:naiweaver/features/director_ref/widgets/director_ref_manager.dart';
import 'package:naiweaver/features/director_ref/widgets/reference_add_actions.dart';
import 'package:naiweaver/features/director_ref/widgets/reference_fields.dart';
import 'package:naiweaver/features/director_ref/widgets/reference_library_manager.dart';
import 'package:naiweaver/features/vibe_transfer/models/vibe_transfer.dart';
import 'package:naiweaver/features/vibe_transfer/providers/vibe_transfer_notifier.dart';
import 'package:naiweaver/features/vibe_transfer/widgets/vibe_transfer_manager.dart';
import 'package:naiweaver/l10n/app_localizations_en.dart';
import 'package:provider/provider.dart';

import 'test_harness.dart';

final _png = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));

DirectorReference _ref(String id, {bool enabled = true}) => DirectorReference(
  id: id,
  originalImageBytes: _png,
  processedBase64: 'img',
  enabled: enabled,
);

/// Lets real file I/O started by the widget finish, then rebuilds.
Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<DirectorRefNotifier> _pumpDirectorManager(
  WidgetTester tester, {
  required String baseDir,
  List<DirectorReference> refs = const [],
  Size size = const Size(800, 900),
}) async {
  final notifier = DirectorRefNotifier();
  await notifier.setReferences(refs);
  await pumpHarness(
    tester,
    const DirectorRefManager(),
    size: size,
    providers: [
      Provider<PathService>.value(value: PathService(baseDir)),
      ChangeNotifierProvider<DirectorRefNotifier>.value(value: notifier),
    ],
  );
  await _settleIo(tester);
  return notifier;
}

Future<void> _saveFirstToLibrary(WidgetTester tester) async {
  await tester.tap(find.byTooltip('SAVE REFERENCE').first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'hero');
  await tester.tap(find.text('SAVE'));
  await tester.pump();
  await _settleIo(tester);
  // Let the dialog finish closing so only the library lists the name.
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('naiweaver_refs'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('saving to the library', () {
    testWidgets('a failed write reports the failure, never success', (
      tester,
    ) async {
      // The library would live inside a regular file, so it cannot be written.
      final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
      await _pumpDirectorManager(
        tester,
        baseDir: blocker.path,
        refs: [_ref('ref_0')],
      );

      await _saveFirstToLibrary(tester);

      expect(
        find.text('Could not update the library. Storage may be full.'),
        findsOneWidget,
      );
      expect(find.text('Saved to the library'), findsNothing);
      expect(find.text('SAVED'), findsNothing);
    });

    testWidgets('a successful write confirms and lists the entry', (
      tester,
    ) async {
      await _pumpDirectorManager(
        tester,
        baseDir: dir.path,
        refs: [_ref('ref_0')],
      );

      await _saveFirstToLibrary(tester);

      expect(find.text('Saved to the library'), findsOneWidget);
      expect(find.text('hero'), findsOneWidget);
      final stored = await tester.runAsync(
        () =>
            ReferenceLibraryService.load('${dir.path}/reference_library.json'),
      );
      expect(stored!.directorRefs.single.name, 'hero');
    });

    testWidgets(
      'leaving the tab while saving does not touch the disposed page',
      (tester) async {
        await _pumpDirectorManager(
          tester,
          baseDir: dir.path,
          refs: [_ref('ref_0')],
        );
        await tester.tap(find.byTooltip('SAVE REFERENCE').first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'hero');
        await tester.tap(find.text('SAVE'));
        await tester.pump();

        // The write is still pending; the tab is torn down meanwhile.
        await tester.pumpWidget(const SizedBox.shrink());
        await _settleIo(tester);

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('current entries', () {
    testWidgets('a disabled reference is dimmed and can be re-enabled here', (
      tester,
    ) async {
      final notifier = await _pumpDirectorManager(
        tester,
        baseDir: dir.path,
        refs: [_ref('ref_0', enabled: false)],
      );

      final dimmed = tester.widgetList<Opacity>(
        find.descendant(
          of: find.byType(ReferenceItemCard),
          matching: find.byType(Opacity),
        ),
      );
      expect(
        dimmed.map((o) => o.opacity),
        everyElement(ReferenceItemCard.disabledOpacity),
      );
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      await tester.tap(find.text('ENABLED'));
      await tester.pump();

      expect(notifier.references.single.enabled, isTrue);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    for (final width in [360.0, 600.0, 680.0]) {
      testWidgets('reference cards fit ${width.toInt()} px', (tester) async {
        await _pumpDirectorManager(
          tester,
          baseDir: dir.path,
          refs: [_ref('ref_0'), _ref('ref_1', enabled: false)],
          size: Size(width, 900),
        );
        expect(find.byType(DirectorRefTypeSelector), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('adding vibes', () {
    Future<List<String>> pumpGeneric(
      WidgetTester tester, {
      String? disabledReason,
    }) async {
      final calls = <String>[];
      await pumpHarness(
        tester,
        ReferenceLibraryManager<VibeTransfer, SavedVibeTransfer>(
          items: const [],
          itemBuilder: (_, _, _) => const SizedBox.shrink(),
          countLabel: '0 VIBES',
          onClearAll: null,
          emptyIcon: Icons.music_note_outlined,
          emptyTitle: 'NO VIBES ADDED',
          emptyDescription: '',
          addLabel: 'ADD VIBE',
          onAdd: () async => calls.add('add'),
          addDisabledReason: disabledReason,
          isProcessing: false,
          slot: ReferenceLibrarySlot.vibeTransfers,
          saveTitle: 'SAVE VIBE',
          toSaved: (vibe, name) => SavedVibeTransfer(
            name: name,
            vibe: vibe,
            savedAt: DateTime(2026),
          ),
          onLoadSaved: (_) async {},
          savedName: (s) => s.name,
          savedImage: (s) => s.vibe.originalImageBytes,
          savedSummary: (s) => '',
          accent: Colors.green,
        ),
        providers: [Provider<PathService>.value(value: PathService(dir.path))],
      );
      await _settleIo(tester);
      return calls;
    }

    testWidgets('the add button is disabled with a reason without permission', (
      tester,
    ) async {
      final calls = await pumpGeneric(
        tester,
        disabledReason: 'Your account is not allowed to encode vibes.',
      );

      final button = tester.widget<ElevatedButton>(
        find.byKey(ReferenceLibraryManager.addButtonKey),
      );
      expect(button.onPressed, isNull);
      expect(
        find.byKey(ReferenceLibraryManager.disabledReasonKey),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ReferenceLibraryManager.addButtonKey));
      expect(calls, isEmpty);
    });

    testWidgets('the vibe tab keeps adding enabled when encoding is allowed', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        const VibeTransferManager(),
        providers: [
          Provider<PathService>.value(value: PathService(dir.path)),
          ChangeNotifierProvider(create: (_) => VibeTransferNotifier()),
        ],
      );
      await _settleIo(tester);

      final button = tester.widget<ElevatedButton>(
        find.byKey(ReferenceLibraryManager.addButtonKey),
      );
      expect(button.onPressed, isNotNull);
      expect(
        find.byKey(ReferenceLibraryManager.disabledReasonKey),
        findsNothing,
      );
    });
  });

  group('vibe encode errors', () {
    final l = AppLocalizationsEn();
    GenerationRequestException http(int? status, [String code = '']) =>
        GenerationRequestException(
          statusCode: status,
          code: code,
          message: 'Generation request failed',
        );

    test('gateway failures map to readable categories', () {
      String message(Object error) =>
          vibeEncodeErrorMessage(l, error, gateway: true);

      expect(
        message(http(409, 'points_insufficient')),
        l.refErrorPointsInsufficient,
      );
      expect(message(http(409)), l.refErrorPointsInsufficient);
      expect(message(http(403)), l.refVibeNoPermission);
      expect(message(http(403, 'permission_denied')), l.refVibeNoPermission);
      expect(message(UnauthorizedException()), l.refErrorSessionExpired);
      expect(message(http(null)), l.refErrorNetwork);
      expect(message(http(502)), l.refErrorServiceUnavailable);
      expect(
        message(Exception('DioException [bad response]: raw')),
        l.refVibeEncodeFailed,
      );
    });

    test('direct NovelAI keeps the API-key hint for 401', () {
      expect(
        vibeEncodeErrorMessage(l, UnauthorizedException(), gateway: false),
        l.refApiKeyMissing,
      );
      expect(
        vibeEncodeErrorMessage(l, http(402), gateway: false),
        l.refErrorPointsInsufficient,
      );
    });
  });
}
