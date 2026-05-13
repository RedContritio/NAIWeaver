import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/characters/gen/character_gen_data.dart';
import 'package:naiweaver/features/characters/gen/character_gen_service.dart';
import 'package:naiweaver/features/characters/gen/widgets/character_gen_dialog.dart';
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
Future<Future<CharacterGenForm?>> _open(WidgetTester tester, ThemeNotifier theme) async {
  late Future<CharacterGenForm?> pending;
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeNotifier>.value(
      value: theme,
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
  testWidgets('renders the form controls', (tester) async {
    final theme = await _theme();
    final pending = await _open(tester, theme);

    expect(find.text('GENERATE CHARACTER'), findsOneWidget);
    expect(find.text('✨ GENERATE'), findsOneWidget);
    expect(find.byType(DropdownButton<CharacterVibe>), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget); // gender
    expect(find.byType(DropdownButton<CharacterEra>), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget); // wardrobe count

    await tester.tap(find.text('CANCEL'));
    expect(await _closeAndRead(tester, pending), isNull);
  });

  testWidgets('Custom vibe gates Generate until the free-text field is filled', (tester) async {
    final theme = await _theme();
    final pending = await _open(tester, theme);

    await tester.tap(find.byType(DropdownButton<CharacterVibe>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Custom').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    ElevatedButton genButton() => tester.widget<ElevatedButton>(
        find.ancestor(of: find.text('✨ GENERATE'), matching: find.byType(ElevatedButton)));
    expect(genButton().onPressed, isNull);

    final customField = find.widgetWithText(
        TextField, 'describe the vibe — e.g. "weary war veteran turned baker"');
    expect(customField, findsOneWidget);
    await tester.enterText(customField, 'weary war veteran turned baker');
    await tester.pump();
    expect(genButton().onPressed, isNotNull);

    await tester.tap(find.text('✨ GENERATE'));
    final form = await _closeAndRead(tester, pending);
    expect(form, isNotNull);
    expect(form!.vibe.isCustom, isTrue);
    expect(form.customVibe, 'weary war veteran turned baker');
  });

  testWidgets('submitting with defaults returns a sensible form', (tester) async {
    final theme = await _theme();
    final pending = await _open(tester, theme);

    await tester.tap(find.text('✨ GENERATE'));
    final form = await _closeAndRead(tester, pending);
    expect(form, isNotNull);
    expect(form!.gender, 'any');
    expect(form.era.isModern, isTrue); // defaults to the modern era
    expect(form.wardrobeCount, 5);
    expect(form.imageStyle, CharacterImageStyle.anime);
  });
}
