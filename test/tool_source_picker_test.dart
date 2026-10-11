import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/core/widgets/syntax_highlight_controller.dart';
import 'package:naiweaver/features/gallery/providers/gallery_notifier.dart';
import 'package:naiweaver/features/generation/providers/generation_notifier.dart';
import 'package:naiweaver/features/tools/widgets/tool_source_picker.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Returns what a Web picker returns: bytes only, no filesystem path.
class _BytesOnlyFilePicker extends FilePicker {
  _BytesOnlyFilePicker(this._result);

  final Future<Uint8List> _result;
  int calls = 0;

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
  }) async {
    calls++;
    final bytes = await _result;
    return FilePickerResult([
      PlatformFile(name: 'picked.png', size: bytes.length, bytes: bytes),
    ]);
  }
}

class _FakeGenerationNotifier extends ChangeNotifier
    implements GenerationNotifier {
  _FakeGenerationNotifier(Uint8List? current)
    : state = GenerationState(
        generatedImages: [
          if (current != null)
            GeneratedImageItem(
              id: 'current',
              batchIndex: 1,
              batchCount: 1,
              bytes: current,
            ),
        ],
        selectedGeneratedImageId: current == null ? null : 'current',
      );

  @override
  GenerationState state;

  @override
  final SyntaxHighlightController promptController = SyntaxHighlightController(
    text: 'main prompt',
  );

  @override
  final SyntaxHighlightController negativePromptController =
      SyntaxHighlightController(text: 'main uc');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyGalleryNotifier extends ChangeNotifier implements GalleryNotifier {
  @override
  List<GalleryItem> get items => const [];

  @override
  bool get demoMode => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _png = Uint8List.fromList(File('assets/logo.png').readAsBytesSync());

Future<void> _pumpPicker(
  WidgetTester tester, {
  required ToolSourcePromptImport promptImport,
  required ValueChanged<ToolSourceSelection> onSelected,
  Uint8List? currentImage,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = PreferencesService(
    await SharedPreferences.getInstance(),
    const FlutterSecureStorage(),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<PreferencesService>.value(value: preferences),
        ChangeNotifierProvider(create: (_) => ThemeNotifier(preferences)),
        ChangeNotifierProvider<GenerationNotifier>(
          create: (_) => _FakeGenerationNotifier(currentImage),
        ),
        ChangeNotifierProvider<GalleryNotifier>(
          create: (_) => _EmptyGalleryNotifier(),
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
        home: Scaffold(
          body: ToolSourcePicker(
            icon: Icons.hd,
            title: 'TITLE',
            description: 'Description',
            useCurrentLabel: 'USE CURRENT',
            useCurrentDescription: 'Use current',
            promptImport: promptImport,
            onSelected: onSelected,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('upload from device accepts a bytes-only pick', (tester) async {
    final picker = _BytesOnlyFilePicker(Future.value(_png));
    FilePicker.platform = picker;
    final selections = <ToolSourceSelection>[];

    await _pumpPicker(
      tester,
      promptImport: ToolSourcePromptImport.none,
      onSelected: selections.add,
    );
    await tester.tap(find.text('UPLOAD FROM DEVICE'));
    await tester.pump();

    expect(picker.calls, 1);
    expect(selections, hasLength(1));
    expect(selections.single.bytes, same(_png));
    expect(selections.single.origin, ToolSourceOrigin.device);
    expect(selections.single.filePath, isNull);
  });

  testWidgets('a pick that lands after the tool was switched is dropped', (
    tester,
  ) async {
    final pending = Completer<Uint8List>();
    FilePicker.platform = _BytesOnlyFilePicker(pending.future);
    final selections = <ToolSourceSelection>[];

    await _pumpPicker(
      tester,
      promptImport: ToolSourcePromptImport.none,
      onSelected: selections.add,
    );
    await tester.tap(find.text('UPLOAD FROM DEVICE'));
    await tester.pump();

    // The user switches tools while the file dialog is still open.
    await tester.pumpWidget(const SizedBox());
    pending.complete(_png);
    await tester.pump();

    expect(selections, isEmpty);
  });

  testWidgets('each tool keeps its own prompt import rule', (tester) async {
    Future<ToolSourceSelection> useCurrent(ToolSourcePromptImport mode) async {
      late ToolSourceSelection selection;
      await _pumpPicker(
        tester,
        promptImport: mode,
        currentImage: _png,
        onSelected: (s) => selection = s,
      );
      await tester.tap(find.text('USE CURRENT'));
      await tester.pump();
      return selection;
    }

    final director = await useCurrent(ToolSourcePromptImport.none);
    expect(director.origin, ToolSourceOrigin.currentGeneration);
    expect(director.prompt, isNull);
    expect(director.negativePrompt, isNull);

    final enhance = await useCurrent(
      ToolSourcePromptImport.mainPromptForCurrentGeneration,
    );
    expect(enhance.prompt, 'main prompt');
    expect(enhance.negativePrompt, isNull);

    final img2img = await useCurrent(ToolSourcePromptImport.preferenceGated);
    expect(img2img.prompt, 'main prompt');
    expect(img2img.negativePrompt, 'main uc');
  });
}
