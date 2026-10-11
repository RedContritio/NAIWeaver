import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared setup for widget tests: English localizations, the theme provider
/// that `context.t` needs, and an optional fixed logical surface size.
Future<PreferencesService> testPreferences({
  Map<String, Object> initial = const {},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  return PreferencesService(
    await SharedPreferences.getInstance(),
    const FlutterSecureStorage(),
  );
}

void setSurfaceSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget harnessApp({
  required PreferencesService preferences,
  required Widget home,
  List<SingleChildWidget> providers = const [],
}) {
  return MultiProvider(
    providers: [
      Provider<PreferencesService>.value(value: preferences),
      ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(preferences),
      ),
      ...providers,
    ],
    child: MaterialApp(
      locale: const Locale('en'),
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

Future<void> pumpHarness(
  WidgetTester tester,
  Widget child, {
  List<SingleChildWidget> providers = const [],
  Size? size,
}) async {
  if (size != null) setSurfaceSize(tester, size);
  final preferences = await testPreferences();
  await tester.pumpWidget(
    harnessApp(
      preferences: preferences,
      providers: providers,
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}
