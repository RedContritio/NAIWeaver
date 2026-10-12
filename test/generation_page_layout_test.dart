import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/features/generation/widgets/generation_page_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

}
