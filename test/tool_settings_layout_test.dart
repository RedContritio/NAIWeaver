import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/tools/widgets/tool_config_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = PreferencesService(
    await SharedPreferences.getInstance(),
    const FlutterSecureStorage(),
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(preferences),
      child: MaterialApp(
        home: Scaffold(
          body: ToolSettingsLayout(
            body: const Center(child: Text('workspace')),
            settingsTooltip: 'Settings',
            settingsBuilder: (_) => const Text('settings content'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  const dock = ValueKey<String>('tool-settings-dock');

  testWidgets('touch-sized windows reach the settings through the dock', (
    tester,
  ) async {
    await _pump(tester, const Size(700, 900));
    expect(find.byKey(dock), findsOneWidget);
    expect(find.text('settings content'), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('settings content'), findsOneWidget);
  });

  testWidgets('expanded windows keep the settings in a side panel', (
    tester,
  ) async {
    await _pump(tester, const Size(1000, 800));
    expect(find.byKey(dock), findsNothing);
    expect(find.text('settings content'), findsOneWidget);
    expect(find.text('workspace'), findsOneWidget);
  });
}
