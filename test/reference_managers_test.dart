import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naiweaver/core/gateway/backend_exception.dart';
import 'package:naiweaver/core/services/path_service.dart';
import 'package:naiweaver/core/services/reference_library_service.dart';
import 'package:naiweaver/features/director_ref/models/director_reference.dart';
import 'package:naiweaver/features/director_ref/providers/director_ref_notifier.dart';
import 'package:naiweaver/features/director_ref/widgets/director_ref_manager.dart';
import 'package:naiweaver/features/director_ref/widgets/reference_add_actions.dart';
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

/// Real file I/O finishes on its own schedule; wait for its outcome instead of
/// a fixed delay, which flaked under a loaded full-suite run.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<void> _saveFirstToLibrary(WidgetTester tester) async {
  await tester.tap(find.byTooltip('SAVE REFERENCE').first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'hero');
  await tester.tap(find.text('SAVE'));
  await tester.pump();
  await _pumpUntilFound(tester, find.byType(SnackBar));
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

  group('vibe encode errors', () {
    final l = AppLocalizationsEn();
    BackendException failure(String code, [int? status]) =>
        BackendException(statusCode: status, code: code);

    test('gateway failures are told apart by their code', () {
      String message(Object error) =>
          vibeEncodeErrorMessage(l, error, gateway: true);

      expect(
        message(failure(BackendErrorCode.pointsInsufficient, 409)),
        l.refErrorPointsInsufficient,
      );
      expect(
        message(const QuoteChangedException(statusCode: 409)),
        l.gatewayErrQuoteChanged,
      );
      expect(
        message(failure(BackendErrorCode.permissionDenied, 403)),
        l.refVibeNoPermission,
      );
      expect(
        message(failure(BackendErrorCode.notAuthenticated, 401)),
        l.refErrorSessionExpired,
      );
      expect(
        message(failure(BackendErrorCode.upstreamError, 502)),
        l.refErrorServiceUnavailable,
      );
      expect(message(failure(BackendErrorCode.network)), l.refErrorNetwork);
      expect(
        message(Exception('DioException [bad response]: raw')),
        l.refVibeEncodeFailed,
      );
    });
  });
}
