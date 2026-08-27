import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/generation/widgets/generation_mobile_sheet.dart';

void main() {
  Widget buildSheet(
    GlobalKey<GenerationMobileSheetState> key, {
    Widget? prompt,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 700),
          viewPadding: EdgeInsets.only(bottom: 20),
        ),
        child: Scaffold(
          body: GenerationMobileSheet(
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
            parameters: const ColoredBox(
              color: Colors.blue,
              child: Center(child: Text('PARAMETER BODY')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('compact bar expands, changes tab, and collapses', (
    tester,
  ) async {
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

  testWidgets('compact height includes safe area without an extra footer', (
    tester,
  ) async {
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
