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
      inputs: const ColoredBox(
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
    Widget? parameters,
  }) {
    return app(sheet(key, prompt: prompt, parameters: parameters));
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

  testWidgets('pages keep their state through collapsing and tab switches', (
    tester,
  ) async {
    setUpView(tester);
    final key = GlobalKey<GenerationMobileSheetState>();
    final lifecycle = <String>[];
    const listKey = ValueKey<String>('parameter-list');
    await tester.pumpWidget(
      buildSheet(
        key,
        prompt: _LifecycleProbe(
          log: lifecycle,
          child: const Center(
            child: TextField(key: ValueKey<String>('prompt-field')),
          ),
        ),
        parameters: ListView(
          key: listKey,
          children: [
            for (var row = 0; row < 40; row++)
              SizedBox(height: 50, child: Text('ROW $row')),
          ],
        ),
      ),
    );
    final state = key.currentState!;
    double listOffset() => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(listKey),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;

    unawaited(state.openTab(GenerationMobileTab.prompt));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('prompt-field')),
      'kept draft',
    );
    unawaited(state.openTab(GenerationMobileTab.parameters));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(listKey), const Offset(0, -400));
    await tester.pumpAndSettle();
    final scrolled = listOffset();
    expect(scrolled, greaterThan(300));

    // Every generation collapses the sheet.
    unawaited(state.collapse());
    await tester.pumpAndSettle();
    expect(state.isExpanded, isFalse);
    unawaited(state.openTab(GenerationMobileTab.parameters));
    await tester.pumpAndSettle();
    expect(listOffset(), scrolled);

    unawaited(state.openTab(GenerationMobileTab.prompt));
    await tester.pumpAndSettle();
    expect(find.text('kept draft'), findsOneWidget);
    expect(lifecycle, ['init']);
  });

}

/// Records whether its subtree was rebuilt from scratch.
class _LifecycleProbe extends StatefulWidget {
  const _LifecycleProbe({required this.log, required this.child});

  final List<String> log;
  final Widget child;

  @override
  State<_LifecycleProbe> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbe> {
  @override
  void initState() {
    super.initState();
    widget.log.add('init');
  }

  @override
  void dispose() {
    widget.log.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
