import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/gallery/services/gallery_import_service.dart';
import 'package:naiweaver/features/tools/img2img/providers/img2img_notifier.dart';
import 'package:naiweaver/features/tools/img2img/widgets/mask_toolbar.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Returns what a Web picker returns: bytes only, no filesystem path.
class _BytesOnlyFilePicker extends FilePicker {
  _BytesOnlyFilePicker(this.bytes);

  final Uint8List bytes;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(name: 'mask.png', size: bytes.length, bytes: bytes),
  ]);
}

class _RecordingImg2ImgNotifier extends Img2ImgNotifier {
  Uint8List? loadedMask;

  @override
  void loadMask(Uint8List pngBytes) => loadedMask = pngBytes;
}

final _png = Uint8List.fromList(File('assets/logo.png').readAsBytesSync());

void main() {
  test('gallery import accepts picks that only carry bytes', () async {
    final outputDir = await Directory.systemTemp.createTemp('c3_import_');
    addTearDown(() => outputDir.delete(recursive: true));
    final imported = <File>[];

    final result = await GalleryImportService().importFiles(
      [
        GalleryImportSource.picked(
          PlatformFile(name: 'photo.png', size: _png.length, bytes: _png),
        ),
        GalleryImportSource.picked(PlatformFile(name: 'empty.png', size: 0)),
      ],
      outputDir: outputDir.path,
      onFileImported: (file, _) => imported.add(file),
    );

    expect(result.total, 2);
    expect(result.succeeded, 1);
    expect(result.errors, ['empty.png']);
    expect(imported, hasLength(1));
    expect(p.dirname(imported.single.path), outputDir.path);
    expect(imported.single.existsSync(), isTrue);
  });

  testWidgets('load mask reads a bytes-only pick', (tester) async {
    FilePicker.platform = _BytesOnlyFilePicker(_png);
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final notifier = _RecordingImg2ImgNotifier();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeNotifier(preferences)),
          ChangeNotifierProvider<Img2ImgNotifier>.value(value: notifier),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: MaskToolbar()),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Load mask'));
    await tester.pump();

    expect(notifier.loadedMask, same(_png));
  });
}
