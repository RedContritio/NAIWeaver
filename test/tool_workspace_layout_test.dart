import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/tools/img2img/providers/img2img_notifier.dart';
import 'package:naiweaver/features/tools/img2img/widgets/mask_toolbar.dart';
import 'package:naiweaver/features/tools/widgets/tool_config_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('mask toolbar remains reachable on a narrow viewport', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeNotifier(preferences)),
          ChangeNotifierProvider(create: (_) => Img2ImgNotifier()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(width: 320, child: MaskToolbar())),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('mask-toolbar-primary-scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byKey(const ValueKey<String>('mask-toolbar-primary-scroll')),
      const Offset(-260, 0),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Mask display settings'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('mask-toolbar-settings-scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tool settings dock participates in layout instead of overlaying',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PreferencesService(
        await SharedPreferences.getInstance(),
        const FlutterSecureStorage(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeNotifier(preferences),
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const Expanded(
                    child: ColoredBox(
                      key: ValueKey<String>('tool-workspace-content'),
                      color: Colors.black,
                    ),
                  ),
                  ToolSettingsDock(tooltip: 'Settings', onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final contentRect = tester.getRect(
        find.byKey(const ValueKey<String>('tool-workspace-content')),
      );
      final dockRect = tester.getRect(
        find.byKey(const ValueKey<String>('tool-settings-dock')),
      );
      expect(contentRect.bottom, dockRect.top);
      expect(tester.takeException(), isNull);
    },
  );
}
