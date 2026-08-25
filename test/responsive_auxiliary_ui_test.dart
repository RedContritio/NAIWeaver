import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/core/widgets/pin_lock_gate.dart';
import 'package:naiweaver/features/tools/widgets/pack_manager.dart';
import 'package:naiweaver/features/tools/widgets/tag_library_manager.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<PreferencesService> _preferences({Map<String, Object> initial = const {}}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return PreferencesService(prefs, const FlutterSecureStorage());
}

Widget _testApp({
  required PreferencesService preferences,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
        create: (_) => ThemeNotifier(preferences),
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
      home: Scaffold(body: child),
    ),
  );
}

void _setSurfaceSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets('PIN entry remains usable on a short viewport', (tester) async {
    _setSurfaceSize(tester, const Size(320, 360));
    final preferences = await _preferences();

    await tester.pumpWidget(
      _testApp(
        preferences: preferences,
        child: PinEntryScreen(prefs: preferences, onUnlock: () {}),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('pin-entry-scroll-view')), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pack actions stack and scroll on a short narrow viewport',
      (tester) async {
    _setSurfaceSize(tester, const Size(360, 320));
    final preferences = await _preferences();

    await tester.pumpWidget(
      _testApp(preferences: preferences, child: const PackManager()),
    );
    await tester.pump();

    final exportCenter = tester.getCenter(find.byIcon(Icons.file_upload_outlined));
    final importCenter = tester.getCenter(find.byIcon(Icons.file_download_outlined));
    expect((exportCenter.dx - importCenter.dx).abs(), lessThan(1));
    expect(importCenter.dy, greaterThan(exportCenter.dy));

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick tag preview fits a short dialog and keeps a scroll viewport',
      (tester) async {
    _setSurfaceSize(tester, const Size(360, 300));
    final preferences = await _preferences();

    await tester.pumpWidget(
      _testApp(
        preferences: preferences,
        child: const Dialog(
          child: TagPreviewResponsiveLayout(
            header: SizedBox(height: 40, child: Text('Preview')),
            preview: ColoredBox(color: Colors.black),
            footer: SizedBox(height: 96, child: Text('Actions')),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('quick-tag-preview-scroll-view')),
      findsOneWidget,
    );
    expect(find.byType(AspectRatio), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
