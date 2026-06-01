import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/characters/gen/character_gen_data.dart';
import 'package:naiweaver/features/characters/gen/character_gen_service.dart';
import 'package:naiweaver/features/characters/gen/widgets/character_gen_dialog.dart';
import 'package:naiweaver/features/characters/providers/character_library_notifier.dart';
import 'package:naiweaver/features/characters/services/character_library_service.dart';
import 'package:naiweaver/features/characters/services/closet_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ThemeNotifier> _theme() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ThemeNotifier(PreferencesService(prefs, const FlutterSecureStorage()));
}

/// Opens [CharacterGenDialog] via `showDialog` and returns the future that
/// resolves with the dialog's result. We pump fixed durations rather than
/// `pumpAndSettle` so a perpetually-rebuilding child can't make the test hang.
///
/// The dialog's artist field is a [TagTextField], which reads a [TagService]
/// and a [CharacterLibraryNotifier] from the tree — both are provided here. The
/// TagService points at a non-existent file so it loads no suggestions (the
/// service no-ops gracefully when the file is missing).
Future<Future<CharacterGenForm?>> _open(
  WidgetTester tester,
  ThemeNotifier theme,
  CharacterLibraryNotifier library,
) async {
  late Future<CharacterGenForm?> pending;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>.value(value: theme),
        ChangeNotifierProvider<CharacterLibraryNotifier>.value(value: library),
        Provider<TagService>.value(
            value: TagService(filePath: '/does/not/exist/tags.json')),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) {
            return TextButton(
              onPressed: () {
                pending = showDialog<CharacterGenForm>(
                  context: ctx,
                  builder: (_) => const CharacterGenDialog(eras: kFallbackEras),
                );
              },
              child: const Text('open'),
            );
          }),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  // Settle the dialog entrance without pumpAndSettle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return pending;
}

Future<CharacterGenForm?> _closeAndRead(WidgetTester tester, Future<CharacterGenForm?> pending) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return pending;
}

void main() {
  late Directory tmp;
  late CharacterLibraryNotifier library;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('naiweaver_chargen_dialog_test');
    library = CharacterLibraryNotifier(
      service: CharacterLibraryService(charactersDir: tmp.path),
      closetService: ClosetService(charactersDir: tmp.path),
    );
    await library.loadAll();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('renders the form controls', (tester) async {
    final theme = await _theme();
    final pending = await _open(tester, theme, library);

    expect(find.text('GENERATE CHARACTER'), findsOneWidget);
    expect(find.text('✨ GENERATE'), findsOneWidget);
    // Vibe is now a free-text field, not a dropdown.
    expect(find.byType(DropdownButton<CharacterVibe>), findsNothing);
    expect(find.byType(DropdownButton<String>), findsOneWidget); // gender
    expect(find.byType(DropdownButton<CharacterEra>), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget); // wardrobe count
    // Style field (artist-tag autosuggest) replaced the anime/realistic chooser.
    expect(find.text('STYLE (OPTIONAL)'), findsOneWidget);

    await tester.tap(find.text('CANCEL'));
    expect(await _closeAndRead(tester, pending), isNull);
  });

  testWidgets('submitting with defaults returns a sensible form', (tester) async {
    final theme = await _theme();
    final pending = await _open(tester, theme, library);

    await tester.tap(find.text('✨ GENERATE'));
    final form = await _closeAndRead(tester, pending);
    expect(form, isNotNull);
    expect(form!.gender, 'any');
    expect(form.era.isModern, isTrue); // defaults to the modern era
    expect(form.wardrobeCount, 2); // starter wardrobe slider default (range 0-3)
    expect(form.vibe.isCustom, isTrue); // free-text vibe routes through `custom`
    expect(form.customVibe, isEmpty); // blank => model picks
    expect(form.artist, isEmpty);
  });

  testWidgets('typed vibe and artist flow into the form', (tester) async {
    final theme = await _theme();
    final pending = await _open(tester, theme, library);

    final vibeField = find.widgetWithText(TextField,
        'describe the vibe — e.g. "weary war veteran turned baker" — blank lets the model pick');
    expect(vibeField, findsOneWidget);
    await tester.enterText(vibeField, 'weary war veteran turned baker');
    await tester.pump();

    final artistField = find.widgetWithText(
        TextField, 'e.g. an artist tag — blank lets the model pick');
    expect(artistField, findsOneWidget);
    await tester.enterText(artistField, 'utsunomiya tsumire');
    await tester.pump();

    await tester.tap(find.text('✨ GENERATE'));
    final form = await _closeAndRead(tester, pending);
    expect(form, isNotNull);
    expect(form!.vibe.isCustom, isTrue);
    expect(form.customVibe, 'weary war veteran turned baker');
    expect(form.artist, 'utsunomiya tsumire');
  });
}
