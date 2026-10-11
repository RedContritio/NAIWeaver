import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/tools/img2img/providers/img2img_notifier.dart';
import 'package:naiweaver/features/tools/img2img/widgets/mask_toolbar.dart';
import 'package:naiweaver/features/tools/widgets/tool_config_bottom_sheet.dart';
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
  testWidgets('mask toolbar keeps its file actions right-aligned when wide', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final preferences = await _preferences();

    await tester.pumpWidget(
      _app(preferences, const Scaffold(body: MaskToolbar())),
    );
    await tester.pump();

    final load = tester.getRect(find.byTooltip('Load mask'));
    final size = tester.getRect(find.byTooltip('Square brush'));
    // 16px container padding; the button is flush with the right edge.
    expect(load.right, closeTo(1200 - 16, 4));
    expect(load.left - size.right, greaterThan(600));
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('tool settings sheet rises above the keyboard and follows '
      'the notifier it watches', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final preferences = await _preferences();
    final notifier = _MaskedImg2ImgNotifier();

    await tester.pumpWidget(
      _app(
        preferences,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showToolConfigBottomSheet(
                context: context,
                contentBuilder: (sheetContext) => Column(
                  children: [
                    Text(
                      sheetContext.watch<Img2ImgNotifier>().hasMask
                          ? 'mask: on'
                          : 'mask: off',
                    ),
                    const TextField(key: ValueKey<String>('sheet-field')),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        notifier: notifier,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('mask: on'), findsOneWidget);

    notifier.clearMask();
    await tester.pump();
    expect(find.text('mask: off'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    // The sheet itself ends where the keyboard starts.
    final sheet = tester.getRect(find.byType(DraggableScrollableSheet));
    expect(sheet.bottom, 800 - 300);
    final field = tester.getRect(
      find.byKey(const ValueKey<String>('sheet-field')),
    );
    expect(field.bottom, lessThanOrEqualTo(800 - 300));
  });

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
