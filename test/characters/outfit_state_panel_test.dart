import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/characters/models/closet_outfit.dart';
import 'package:naiweaver/features/characters/outfit/widgets/outfit_state_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final prefsService = PreferencesService(prefs, const FlutterSecureStorage());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier(prefsService)),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('outfit-state panel shows rendered tags and updates on state change',
      (tester) async {
    final outfit = ClosetOutfit.create(
      name: 'Test Fit',
      tags: 'white shirt, blue jeans, brown boots',
    );
    String? appliedTags;
    bool? appliedDish;
    ClosetOutfit? changed;

    await _pump(
      tester,
      OutfitStatePanel(
        outfit: outfit,
        onChanged: (o) => changed = o,
        onApplyToPrompt: (tags, dish) {
          appliedTags = tags;
          appliedDish = dish;
        },
      ),
    );

    // Intact: rendered tags should contain the garments and no nsfw.
    expect(find.textContaining('white shirt'), findsWidgets);
    expect(find.text('DISHEVELLED'), findsNothing);

    // Change the top to "unbuttoned" via the dropdown.
    // There are several DropdownButton<String>; the first slot row is `top`.
    final dropdowns = find.byType(DropdownButton<String>);
    expect(dropdowns, findsWidgets);
    await tester.tap(dropdowns.first);
    await tester.pumpAndSettle();
    // Tap the "unbuttoned" menu item.
    await tester.tap(find.text('unbuttoned').last);
    await tester.pumpAndSettle();

    // The rendered-tags readout should now mention the verb tag, and the panel
    // should flag DISHEVELLED.
    expect(find.textContaining('unbuttoned shirt'), findsWidgets);
    expect(find.text('DISHEVELLED'), findsOneWidget);
    expect(changed, isNotNull);
    expect(changed!.items, isNotNull);

    // Apply to prompt.
    await tester.tap(find.text('APPLY TO PROMPT'));
    await tester.pumpAndSettle();
    expect(appliedTags, isNotNull);
    expect(appliedTags!.contains('unbuttoned shirt'), isTrue);
    expect(appliedDish, isTrue);
  });

  testWidgets('reset to intact clears states', (tester) async {
    final outfit = ClosetOutfit.create(name: 'F', tags: 'white shirt, red skirt');
    await _pump(
      tester,
      OutfitStatePanel(
        outfit: outfit,
        onChanged: (_) {},
        onApplyToPrompt: (_, _) {},
      ),
    );
    final dropdowns = find.byType(DropdownButton<String>);
    await tester.tap(dropdowns.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('open').last);
    await tester.pumpAndSettle();
    expect(find.text('DISHEVELLED'), findsOneWidget);

    await tester.tap(find.text('RESET'));
    await tester.pumpAndSettle();
    expect(find.text('DISHEVELLED'), findsNothing);
  });
}
