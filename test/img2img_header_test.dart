import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/tools/img2img/widgets/img2img_header.dart';
import 'package:naiweaver/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpHeader(
  WidgetTester tester, {
  required double width,
  required bool mobile,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 640);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues({});
  final preferences = PreferencesService(
    await SharedPreferences.getInstance(),
    const FlutterSecureStorage(),
  );

  void noop() {}
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
          body: Column(
            children: [
              // Every optional tool at once: settings, canvas, two local
              // models plus segmentation, and the result toggle.
              Img2ImgHeader(
                mobile: mobile,
                onBack: noop,
                isLoading: false,
                onGenerate: noop,
                onOpenSettings: mobile ? noop : null,
                onOpenCanvas: noop,
                onRemoveBackground: noop,
                onUpscale: noop,
                onSegment: noop,
                onToggleResult: noop,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('img2img header does not overflow at 360dp', (tester) async {
    await _pumpHeader(tester, width: 360, mobile: true);

    expect(tester.takeException(), isNull);
    final generate = tester.getRect(find.byTooltip('GENERATE'));
    expect(generate.left, greaterThanOrEqualTo(0));
    expect(generate.right, lessThanOrEqualTo(360));
    final back = tester.getRect(find.byTooltip('Back to picker'));
    expect(back.left, greaterThanOrEqualTo(0));
    expect(back.right, lessThan(generate.left));

    // Tools that did not fit are reachable by scrolling the middle strip.
    await tester.drag(
      find.byKey(Img2ImgHeader.toolsScrollKey),
      const Offset(400, 0),
    );
    await tester.pump();
    final settings = tester.getRect(find.byTooltip('IMG2IMG SETTINGS'));
    expect(settings.left, greaterThanOrEqualTo(0));
    expect(tester.getRect(find.byTooltip('GENERATE')), generate);
  });

  testWidgets('on wide screens the tools sit next to Generate', (tester) async {
    await _pumpHeader(tester, width: 1200, mobile: false);

    expect(tester.takeException(), isNull);
    final generate = tester.getRect(
      find.ancestor(
        of: find.text('GENERATE'),
        matching: find.byType(ElevatedButton),
      ),
    );
    final toggle = tester.getRect(find.byTooltip('RESULT'));
    final back = tester.getRect(find.byTooltip('Back to picker'));
    expect(generate.right, lessThanOrEqualTo(1200 - 16));
    // Right-aligned like the old Spacer layout: the free space sits after
    // Back, and only a small gap separates the last tool from Generate.
    expect(toggle.left - back.right, greaterThan(500));
    expect(generate.left - toggle.right, inInclusiveRange(0, 12));
  });
}
