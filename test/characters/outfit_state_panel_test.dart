import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/characters/models/closet_outfit.dart';
import 'package:naiweaver/features/characters/outfit/widgets/outfit_state_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    {Size size = const Size(800, 1000), double textScale = 1.0}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final prefsService = PreferencesService(prefs, const FlutterSecureStorage());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier(prefsService)),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Drives the new "state pill + bottom-sheet picker" UI to put the named slot
/// into [chosenState]. Picks the first matching pill by label text.
Future<void> _setSlotState(WidgetTester tester, String pillLabel, String chosenState) async {
  // The pill displays the current state label, e.g. "intact". We tap the first
  // one matching `pillLabel` to open the bottom sheet.
  final pill = find.text(pillLabel).first;
  await tester.tap(pill);
  await tester.pumpAndSettle();
  // Bottom sheet shows each valid state as a tap row; pick the one matching
  // [chosenState] (which is the human-readable label, e.g. "unbuttoned").
  await tester.tap(find.text(chosenState).last);
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

    expect(find.textContaining('white shirt'), findsWidgets);
    expect(find.text('DISHEVELLED'), findsNothing);

    // Each garment row shows an "intact" pill — tap the first to open the
    // bottom-sheet picker (the top slot row renders first by kRenderOrder).
    await _setSlotState(tester, 'intact', 'unbuttoned');

    expect(find.textContaining('unbuttoned shirt'), findsWidgets);
    expect(find.text('DISHEVELLED'), findsOneWidget);
    expect(changed, isNotNull);
    expect(changed!.items, isNotNull);

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

    await _setSlotState(tester, 'intact', 'open');
    expect(find.text('DISHEVELLED'), findsOneWidget);

    // Overflow menu hosts the reset.
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset to intact'));
    await tester.pumpAndSettle();
    expect(find.text('DISHEVELLED'), findsNothing);
  });

  testWidgets('renders cleanly on a 360dp Android-sized frame at textScale 1.3',
      (tester) async {
    final outfit = ClosetOutfit.create(
      name: 'Mobile Fit',
      tags:
          'navy blazer, white shirt, black skirt, white panties, black tights, black boots',
    );
    await _pump(
      tester,
      OutfitStatePanel(
        outfit: outfit,
        onChanged: (_) {},
        onApplyToPrompt: (_, _) {},
      ),
      size: const Size(360, 800),
      textScale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('OUTFIT STATE'), findsOneWidget);
    expect(find.text('APPLY TO PROMPT'), findsOneWidget);
  });

  testWidgets('persistent: false swaps the primary button label', (tester) async {
    final outfit = ClosetOutfit.create(name: 'F', tags: 'white shirt');
    await _pump(
      tester,
      OutfitStatePanel(
        outfit: outfit,
        persistent: false,
        onChanged: (_) {},
        onApplyToPrompt: (_, _) {},
      ),
    );
    expect(find.text('APPLY TO PROMPT'), findsNothing);
    expect(find.text('USE THESE TAGS'), findsOneWidget);
  });
}
