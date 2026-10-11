import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/core/utils/image_utils.dart';
import 'package:naiweaver/features/gallery/services/tool_result_saver.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _png = Uint8List.fromList(File('assets/logo.png').readAsBytesSync());

class _GalleryWrites {
  final calls = <(String, Uint8List?)>[];
  Object? failWith;

  Future<void> write(
    Uint8List bytes,
    String fileName, {
    Uint8List? sourceBytes,
  }) async {
    if (failWith != null) throw failWith!;
    calls.add((fileName, sourceBytes));
  }
}

class _Downloads {
  final names = <String>[];
  final payloads = <List<int>>[];
  bool started = true;

  bool download(List<int> bytes, String fileName) {
    names.add(fileName);
    payloads.add(bytes);
    return started;
  }
}

Future<void> _pumpHost(WidgetTester tester, WidgetBuilder onTap) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = PreferencesService(
    await SharedPreferences.getInstance(),
    const FlutterSecureStorage(),
  );
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
        home: Scaffold(body: Builder(builder: onTap)),
      ),
    ),
  );
}

void main() {
  group('native', () {
    test('writes into the gallery with the source metadata', () async {
      final gallery = _GalleryWrites();
      final downloads = _Downloads();
      final saver = ToolResultSaver(
        writeToGallery: gallery.write,
        web: false,
        download: downloads.download,
      );

      final outcome = await saver.save(_png, 'ENH_1.png', sourceBytes: _png);

      expect(outcome.succeeded, isTrue);
      expect(outcome.destination, ToolResultDestination.gallery);
      expect(gallery.calls.single.$1, 'ENH_1.png');
      expect(gallery.calls.single.$2, same(_png));
      expect(downloads.names, isEmpty);
    });

    test('a failed write is reported, not thrown', () async {
      final gallery = _GalleryWrites()
        ..failWith = const FileSystemException('disk full');
      final saver = ToolResultSaver(writeToGallery: gallery.write, web: false);

      final outcome = await saver.save(_png, 'ENH_1.png');

      expect(outcome.succeeded, isFalse);
      expect(outcome.destination, isNull);
      expect(outcome.error, isA<FileSystemException>());
    });
  });

  group('web', () {
    test('downloads instead of touching the gallery', () async {
      final gallery = _GalleryWrites();
      final downloads = _Downloads();
      final saver = ToolResultSaver(
        writeToGallery: gallery.write,
        web: true,
        download: downloads.download,
      );

      final source = injectMetadata({
        'bytes': _png,
        'metadata': {'prompt': 'cat'},
      });
      final outcome = await saver.save(
        _png,
        'NAI_UP_gen.png',
        sourceBytes: source,
      );

      expect(outcome.destination, ToolResultDestination.download);
      expect(gallery.calls, isEmpty);
      expect(downloads.names, ['NAI_UP_gen.png']);
      final carried = extractMetadata(
        Uint8List.fromList(downloads.payloads.single),
      );
      expect(carried?['Comment'], contains('"prompt":"cat"'));
    });

    test('a download that does not start is a failure', () async {
      final downloads = _Downloads()..started = false;
      final saver = ToolResultSaver(
        writeToGallery: _GalleryWrites().write,
        web: true,
        download: downloads.download,
      );

      final outcome = await saver.save(_png, 'BG_gen.png');

      expect(outcome.succeeded, isFalse);
    });
  });

  testWidgets('saveToolResult never claims success when saving failed', (
    tester,
  ) async {
    final gallery = _GalleryWrites()
      ..failWith = const FileSystemException('read-only');
    late ToolResultSaveOutcome outcome;

    await _pumpHost(
      tester,
      (context) => TextButton(
        onPressed: () async {
          outcome = await saveToolResult(
            context,
            bytes: _png,
            fileName: 'ENH_1.png',
            savedMessage: 'ENHANCED IMAGE SAVED TO GALLERY',
            saver: ToolResultSaver(writeToGallery: gallery.write, web: false),
          );
        },
        child: const Text('save'),
      ),
    );
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(outcome.succeeded, isFalse);
    expect(find.text('ENHANCED IMAGE SAVED TO GALLERY'), findsNothing);
    expect(find.textContaining('Result not saved'), findsOneWidget);
  });

  testWidgets('saveToolResult reports a gallery save and a web download', (
    tester,
  ) async {
    final gallery = _GalleryWrites();
    final downloads = _Downloads();
    late BuildContext hostContext;
    await _pumpHost(tester, (context) {
      hostContext = context;
      return const SizedBox();
    });

    await saveToolResult(
      hostContext,
      bytes: _png,
      fileName: 'ENH_1.png',
      savedMessage: 'ENHANCED IMAGE SAVED TO GALLERY',
      saver: ToolResultSaver(writeToGallery: gallery.write, web: false),
    );
    await tester.pump();
    expect(find.text('ENHANCED IMAGE SAVED TO GALLERY'), findsOneWidget);

    ScaffoldMessenger.of(hostContext).removeCurrentSnackBar();
    await saveToolResult(
      hostContext,
      bytes: _png,
      fileName: 'ENH_2.png',
      savedMessage: 'ENHANCED IMAGE SAVED TO GALLERY',
      saver: ToolResultSaver(
        writeToGallery: gallery.write,
        web: true,
        download: downloads.download,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Downloaded ENH_2.png'), findsOneWidget);
    expect(find.text('ENHANCED IMAGE SAVED TO GALLERY'), findsNothing);
  });
}
