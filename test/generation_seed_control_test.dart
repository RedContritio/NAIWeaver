import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/generation/widgets/generation_seed_control.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('seed variants share validation and random-mode behavior', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var randomize = false;

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
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  GenerationSeedControl(
                    controller: controller,
                    randomize: randomize,
                    onRandomizeChanged: (value) =>
                        setState(() => randomize = value),
                    variant: GenerationSeedControlVariant.compact,
                  ),
                  GenerationSeedControl(
                    controller: controller,
                    randomize: randomize,
                    onRandomizeChanged: (value) =>
                        setState(() => randomize = value),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final compactField = find.byKey(
      const ValueKey<String>('generation-seed-field-compact'),
    );
    await tester.enterText(compactField, '12x34');
    expect(controller.text, '1234');

    await tester.tap(
      find.byKey(const ValueKey<String>('generation-seed-toggle-compact')),
    );
    await tester.pump();

    expect(randomize, isTrue);
    expect(tester.widget<TextField>(compactField).readOnly, isTrue);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('generation-seed-field-full')),
          )
          .readOnly,
      isTrue,
    );
  });
}
