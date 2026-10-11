import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/features/generation/widgets/generation_mobile_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PreferencesService preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = PreferencesService(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
  });

  Widget themed(Widget app) {
    return ChangeNotifierProvider(
      create: (_) => ThemeNotifier(preferences),
      child: app,
    );
  }

  /// Sizes the test window like a phone. MaterialApp derives its MediaQuery
  /// from the window, so the Scaffold body sees the safe area and keyboard
  /// exactly as it does in the app.
  void setUpView(
    WidgetTester tester, {
    Size size = const Size(390, 700),
    double safeBottom = 20,
    double keyboard = 0,
  }) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewPadding = FakeViewPadding(bottom: safeBottom);
    tester.view.padding = FakeViewPadding(
      bottom: math.max(0, safeBottom - keyboard),
    );
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
  }

  GenerationMobileSheet sheet(
    GlobalKey<GenerationMobileSheetState> key, {
    Widget? prompt,
    Widget? inputs,
    Widget? parameters,
  }) {
    return GenerationMobileSheet(
      key: key,
      promptLabel: 'PROMPT',
      inputsLabel: 'INPUTS',
      parametersLabel: 'PARAMETERS',
      inputCount: 2,
      compactPrompt: const Text('COMPACT PROMPT'),
      compactActions: const SizedBox(width: 42, child: Text('GO')),
      prompt:
          prompt ??
          const ColoredBox(
            color: Colors.red,
            child: Center(child: Text('PROMPT BODY')),
          ),
      inputs:
          inputs ??
          const ColoredBox(
            color: Colors.green,
            child: Center(child: Text('INPUT BODY')),
          ),
      parameters:
          parameters ??
          const ColoredBox(
            color: Colors.blue,
            child: Center(child: Text('PARAMETER BODY')),
          ),
    );
  }

  Widget app(Widget body) {
    return themed(MaterialApp(home: Scaffold(body: body)));
  }

  Widget buildSheet(
    GlobalKey<GenerationMobileSheetState> key, {
    Widget? prompt,
  }) {
    return app(sheet(key, prompt: prompt));
  }

  Rect panelRect(WidgetTester tester) {
    return tester.getRect(find.byKey(GenerationMobileSheet.panelKey));
  }

  testWidgets('compact bar expands, changes tab, and collapses', (
    tester,
  ) async {
    setUpView(tester);
    final key = GlobalKey<GenerationMobileSheetState>();
    await tester.pumpWidget(buildSheet(key));

    expect(find.byKey(GenerationMobileSheet.compactKey), findsOneWidget);
    expect(find.byKey(GenerationMobileSheet.tabsKey), findsNothing);
    expect(find.text('COMPACT PROMPT'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byKey(GenerationMobileSheet.compactKey));
    await tester.pumpAndSettle();

    expect(find.byKey(GenerationMobileSheet.tabsKey), findsOneWidget);
    expect(find.text('PROMPT BODY'), findsOneWidget);

    await tester.tap(find.text('INPUTS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('INPUT BODY'), findsOneWidget);

    final collapse = key.currentState!.collapse();
    await tester.pumpAndSettle();
    await collapse;
    expect(find.byKey(GenerationMobileSheet.compactKey), findsOneWidget);
    expect(find.byKey(GenerationMobileSheet.tabsKey), findsNothing);
  });

  testWidgets('panel and input counters follow the theme tokens', (
    tester,
  ) async {
    setUpView(tester);
    final key = GlobalKey<GenerationMobileSheetState>();
    await tester.pumpWidget(buildSheet(key));
    final tokens = ThemeNotifier(preferences).tokens;

    final panel = tester.widget<Material>(
      find.byKey(GenerationMobileSheet.panelKey),
    );
    expect(panel.color, tokens.surfaceHigh);
    expect(tester.widget<Text>(find.text('2')).style?.color, tokens.accent);

    await tester.tap(find.byKey(GenerationMobileSheet.compactKey));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('2')).style?.color, tokens.accent);
  });

  testWidgets('compact height includes safe area without an extra footer', (
    tester,
  ) async {
    setUpView(tester);
    final key = GlobalKey<GenerationMobileSheetState>();
    await tester.pumpWidget(buildSheet(key));

    final panelRect = tester.getRect(
      find.byKey(GenerationMobileSheet.panelKey),
    );
    expect(panelRect.height, 76);
  });

  testWidgets('expanded sheet leaves a retreat target that dismisses focus', (
    tester,
  ) async {
    setUpView(tester);
    final key = GlobalKey<GenerationMobileSheetState>();
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      buildSheet(
        key,
        prompt: Center(child: TextField(focusNode: focusNode)),
      ),
    );

    final opening = key.currentState!.openTab(GenerationMobileTab.prompt);
    await tester.pumpAndSettle();
    await opening;
    focusNode.requestFocus();
    await tester.pump();

    final panelRect = tester.getRect(
      find.byKey(GenerationMobileSheet.panelKey),
    );
    expect(panelRect.top, greaterThan(0));
    expect(focusNode.hasFocus, isTrue);

    await tester.tapAt(Offset(12, panelRect.top / 2));
    await tester.pumpAndSettle();

    expect(focusNode.hasFocus, isFalse);
    expect(find.byKey(GenerationMobileSheet.compactKey), findsOneWidget);
  });

  testWidgets('a multi-frame drag follows the finger without snapping back', (
    tester,
  ) async {
    setUpView(tester);
    final key = GlobalKey<GenerationMobileSheetState>();
    final extents = <double>[];
    await tester.pumpWidget(
      app(
        NotificationListener<DraggableScrollableNotification>(
          onNotification: (notification) {
            extents.add(notification.extent);
            return false;
          },
          child: sheet(key),
        ),
      ),
    );
    final collapsedHeight = panelRect(tester).height;

    await tester.timedDrag(
      find.byKey(GenerationMobileSheet.compactKey),
      const Offset(0, -260),
      const Duration(milliseconds: 900),
    );
    final draggedHeight = extents.reduce(math.max) * 700;
    await tester.pumpAndSettle();

    expect(extents.length, greaterThan(20));
    for (var index = 1; index < extents.length; index++) {
      expect(
        extents[index],
        greaterThanOrEqualTo(extents[index - 1] - 1e-9),
        reason: 'the sheet moved back at notification $index: $extents',
      );
    }
    expect(draggedHeight, greaterThan(collapsedHeight + 220));
    // Released while moving up, it settles on the next stop up.
    expect(panelRect(tester).height, closeTo(700 * 0.72, 0.5));
  });

  for (final keyboard in [0.0, 120.0, 200.0, 260.0, 300.0]) {
    testWidgets(
      'an 800x300 window with a ${keyboard.toInt()}px keyboard keeps working',
      (tester) async {
        setUpView(
          tester,
          size: const Size(800, 300),
          safeBottom: 24,
          keyboard: keyboard,
        );
        final bodyHeight = 300 - keyboard;
        final key = GlobalKey<GenerationMobileSheetState>();
        await tester.pumpWidget(buildSheet(key));
        expect(tester.takeException(), isNull);
        expect(panelRect(tester).bottom, bodyHeight);

        unawaited(key.currentState!.openTab(GenerationMobileTab.parameters));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final opened = panelRect(tester);
        expect(opened.top, greaterThanOrEqualTo(0));
        expect(opened.bottom, bodyHeight);
        if (bodyHeight > GenerationMobileSheet.peekContentHeight) {
          expect(find.text('PARAMETER BODY'), findsOneWidget);
        }

        unawaited(key.currentState!.collapse());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // The keyboard covers the gesture bar, so the body has no safe area.
        final collapsedHeight =
            GenerationMobileSheet.peekContentHeight +
            math.max(0, 24 - keyboard);
        expect(
          panelRect(tester).height,
          closeTo(math.min(bodyHeight, collapsedHeight), 1e-6),
        );
      },
    );
  }

  testWidgets('sheet calls are safe after the sheet leaves the tree', (
    tester,
  ) async {
    setUpView(tester);
    final key = GlobalKey<GenerationMobileSheetState>();
    final showSheet = ValueNotifier<bool>(true);
    addTearDown(showSheet.dispose);
    await tester.pumpWidget(
      app(
        ValueListenableBuilder<bool>(
          valueListenable: showSheet,
          builder: (context, show, _) =>
              show ? sheet(key) : const SizedBox.shrink(),
        ),
      ),
    );
    final state = key.currentState!;

    unawaited(state.openTab(GenerationMobileTab.parameters));
    await tester.pump(const Duration(milliseconds: 100));
    // For example the window widens past the mobile layout mid-animation.
    showSheet.value = false;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await state.collapse();
    await state.expand();
    await state.openTab(GenerationMobileTab.prompt);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('main prompt participates in prompt page scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 300,
            child: GenerationMobilePromptPage(
              prompt: SizedBox(
                key: ValueKey<String>('scrolling-main-prompt'),
                height: 180,
              ),
              settings: SizedBox(height: 720),
            ),
          ),
        ),
      ),
    );

    final before = tester.getTopLeft(
      find.byKey(const ValueKey<String>('scrolling-main-prompt')),
    );
    await tester.drag(
      find.byKey(GenerationMobileSheet.promptScrollKey),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(
      find.byKey(const ValueKey<String>('scrolling-main-prompt')),
    );

    expect(after.dy, lessThan(before.dy - 150));
  });
}
