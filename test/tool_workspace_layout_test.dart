import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/tools/img2img/providers/img2img_notifier.dart';
import 'package:naiweaver/features/tools/img2img/widgets/mask_toolbar.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pretends a mask is painted and records whether it was cleared.
class _MaskedImg2ImgNotifier extends Img2ImgNotifier {
  bool cleared = false;

  @override
  bool get hasMask => !cleared;

  @override
  void clearMask() {
    cleared = true;
    notifyListeners();
  }
}

Future<PreferencesService> _preferences() async {
  SharedPreferences.setMockInitialValues({});
  return PreferencesService(
    await SharedPreferences.getInstance(),
    const FlutterSecureStorage(),
  );
}

Widget _app(PreferencesService preferences, Widget home, {Object? notifier}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeNotifier(preferences)),
      ChangeNotifierProvider<Img2ImgNotifier>(
        create: (_) => notifier as Img2ImgNotifier? ?? Img2ImgNotifier(),
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
      home: home,
    ),
  );
}

void main() {
  testWidgets('clearing the mask asks first', (tester) async {
    final preferences = await _preferences();
    final notifier = _MaskedImg2ImgNotifier();

    await tester.pumpWidget(
      _app(
        preferences,
        const Scaffold(body: MaskToolbar()),
        notifier: notifier,
      ),
    );
    await tester.tap(find.byTooltip('Clear mask'));
    await tester.pumpAndSettle();
    expect(find.text('CLEAR MASK?'), findsOneWidget);

    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(notifier.cleared, isFalse);

    await tester.tap(find.byTooltip('Clear mask'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CLEAR'));
    await tester.pumpAndSettle();
    expect(notifier.cleared, isTrue);
  });

}
