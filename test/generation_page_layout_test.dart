import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/features/generation/widgets/generation_page_layout.dart';
import 'package:naiweaver/features/generation/widgets/settings_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('results and prompt regions never overlap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: GenerationPageLayout(
              overlayReservedHeight: 48,
              results: ColoredBox(color: Colors.black),
              footer: SizedBox(
                height: 180,
                child: ColoredBox(color: Colors.red),
              ),
              overlay: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 48,
                  child: ColoredBox(color: Colors.blue),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final resultsRect = tester.getRect(
      find.byKey(GenerationPageLayout.resultsRegionKey),
    );
    final footerRect = tester.getRect(
      find.byKey(GenerationPageLayout.footerRegionKey),
    );

    expect(resultsRect.bottom, footerRect.top);
    expect(footerRect.bottom, 552);
  });

  testWidgets('composer gives prompt and action the same height', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: GenerationComposerRow(
              promptLines: 4,
              promptFontSize: 12,
              actionWidth: 72,
              promptInput: ColoredBox(color: Colors.red),
              action: PromptGenerationAction(
                estimateHeight: 23,
                estimate: ColoredBox(color: Colors.green),
                generateButton: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );

    final region = tester.getRect(find.byKey(PromptGenerationAction.regionKey));
    final estimate = tester.getRect(
      find.byKey(PromptGenerationAction.estimateKey),
    );
    final button = tester.getRect(find.byKey(PromptGenerationAction.buttonKey));
    final prompt = tester.getRect(find.byKey(GenerationComposerRow.promptKey));

    expect(region.height, prompt.height);
    expect(estimate.top, region.top);
    expect(button.top, estimate.bottom + 4);
    expect(button.bottom, region.bottom);
  });

  testWidgets('composer scales prompt and action together', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: GenerationComposerRow(
              promptLines: 5,
              promptFontSize: 12,
              actionWidth: 68,
              promptInput: ColoredBox(color: Colors.red),
              action: PromptGenerationAction(
                generateButton: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );

    final prompt = tester.getRect(find.byKey(GenerationComposerRow.promptKey));
    final action = tester.getRect(find.byKey(GenerationComposerRow.actionKey));
    expect(prompt.height, action.height);
    expect(prompt.height, 12 * 1.8 * 1.2 * 5 + 24);
  });

  testWidgets('resizable composer grows the prompt and reports final lines', (
    tester,
  ) async {
    var lines = 3;
    int? completedLines;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: StatefulBuilder(
              builder: (context, setState) {
                return ResizableGenerationComposer(
                  promptLines: lines,
                  promptFontSize: 12,
                  actionWidth: 68,
                  promptInput: const ColoredBox(color: Colors.red),
                  action: const ColoredBox(color: Colors.blue),
                  resizeHandleColor: Colors.grey,
                  onPromptLinesChanged: (next) {
                    setState(() => lines = next);
                  },
                  onPromptResizeDone: (next) => completedLines = next,
                );
              },
            ),
          ),
        ),
      ),
    );

    final before = tester.getRect(find.byKey(GenerationComposerRow.promptKey));
    await tester.drag(
      find.byKey(ResizableGenerationComposer.resizeHandleKey),
      const Offset(0, -48),
    );
    await tester.pump();

    final after = tester.getRect(find.byKey(GenerationComposerRow.promptKey));
    expect(lines, greaterThan(3));
    expect(completedLines, lines);
    expect(after.height, greaterThan(before.height));
  });

  testWidgets('resizable composer puts its handle above the prompt', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ResizableGenerationComposer(
              promptLines: 3,
              promptFontSize: 12,
              actionWidth: 68,
              promptInput: const ColoredBox(color: Colors.red),
              action: const ColoredBox(color: Colors.blue),
              resizeHandleColor: Colors.grey,
              onPromptLinesChanged: (_) {},
              onPromptResizeDone: (_) {},
            ),
          ),
        ),
      ),
    );

    final prompt = tester.getRect(find.byKey(GenerationComposerRow.promptKey));
    final handle = tester.getRect(
      find.byKey(ResizableGenerationComposer.resizeHandleKey),
    );
    expect(handle.bottom, prompt.top);
  });

  testWidgets('resize handle only spans the prompt column', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ResizableGenerationComposer(
              promptLines: 3,
              promptFontSize: 12,
              actionWidth: 68,
              promptInput: const ColoredBox(color: Colors.red),
              action: const ColoredBox(color: Colors.blue),
              resizeHandleColor: Colors.grey,
              onPromptLinesChanged: (_) {},
              onPromptResizeDone: (_) {},
            ),
          ),
        ),
      ),
    );

    final prompt = tester.getRect(find.byKey(GenerationComposerRow.promptKey));
    final handle = tester.getRect(
      find.byKey(ResizableGenerationComposer.resizeHandleKey),
    );
    expect(handle.left, prompt.left);
    expect(handle.right, prompt.right);
  });

  group('main prompt resize handle', () {
    late PreferencesService preferences;
    late int lines;
    late List<int> reported;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = PreferencesService(
        await SharedPreferences.getInstance(),
        const FlutterSecureStorage(),
      );
      lines = 6;
      reported = [];
    });

    // Mirrors the main screen wiring: live sizes only rebuild, the final size
    // is persisted. On the mobile sheet the composer sits inside a vertical
    // scroll view, whose drag recognizer competes for every press.
    Widget buildComposer({bool insideScrollView = false}) {
      Widget wrap(Widget composer) => insideScrollView
          ? SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: composer,
            )
          : composer;
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: StatefulBuilder(
              builder: (context, setState) {
                return wrap(
                  ResizableGenerationComposer(
                    promptLines: lines,
                    promptFontSize: 12,
                    actionWidth: 68,
                    promptInput: const ColoredBox(color: Colors.red),
                    action: const ColoredBox(color: Colors.blue),
                    resizeHandleColor: Colors.grey,
                    onPromptLinesChanged: (next) {
                      setState(() => lines = next);
                    },
                    onPromptResizeDone: (next) {
                      reported.add(next);
                      setState(() => lines = next);
                      unawaited(preferences.setUiMainPromptLines(next));
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    Finder handle() => find.byKey(ResizableGenerationComposer.resizeHandleKey);

    for (final insideScrollView in [false, true]) {
      final where = insideScrollView ? 'inside a scroll view' : 'on its own';

      testWidgets('a tap $where keeps the size and persists nothing', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildComposer(insideScrollView: insideScrollView),
        );
        final before = tester.getRect(
          find.byKey(GenerationComposerRow.promptKey),
        );

        await tester.tap(handle());
        await tester.pumpAndSettle();
        final press = await tester.startGesture(tester.getCenter(handle()));
        await tester.pump(const Duration(milliseconds: 600));
        await press.up();
        await tester.pumpAndSettle();

        expect(reported, isEmpty);
        expect(lines, 6);
        expect(preferences.uiMainPromptLines, isNull);
        expect(
          tester.getRect(find.byKey(GenerationComposerRow.promptKey)),
          before,
        );
      });

      testWidgets('a real drag $where persists the final size', (tester) async {
        await tester.pumpWidget(
          buildComposer(insideScrollView: insideScrollView),
        );

        await tester.drag(handle(), const Offset(0, -48));
        await tester.pumpAndSettle();

        expect(lines, greaterThan(6));
        expect(reported, [lines]);
        expect(preferences.uiMainPromptLines, lines);
      });
    }

    testWidgets('a drag back to the starting size persists nothing', (
      tester,
    ) async {
      await tester.pumpWidget(buildComposer());

      final gesture = await tester.startGesture(tester.getCenter(handle()));
      await gesture.moveBy(const Offset(0, -30));
      await gesture.moveBy(const Offset(0, -48));
      await tester.pump();
      expect(lines, greaterThan(6));
      await gesture.moveBy(const Offset(0, 78));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(lines, 6);
      expect(reported, isEmpty);
      expect(preferences.uiMainPromptLines, isNull);
    });

    testWidgets('a drag ended by a cancelled pointer still persists', (
      tester,
    ) async {
      await tester.pumpWidget(buildComposer());

      final gesture = await tester.startGesture(tester.getCenter(handle()));
      await gesture.moveBy(const Offset(0, -30));
      await gesture.moveBy(const Offset(0, -48));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(lines, greaterThan(6));
      expect(reported, [lines]);
      expect(preferences.uiMainPromptLines, lines);
    });
  });

  testWidgets('settings collapsed extent is shared with safe area', (
    tester,
  ) async {
    double? extent;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            viewPadding: EdgeInsets.only(bottom: 18),
          ),
          child: Builder(
            builder: (context) {
              extent = AdvancedSettingsPanel.collapsedExtent(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(extent, 58);
  });
}
