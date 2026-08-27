import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/widgets/browser_native_text_area.dart';

void main() {
  testWidgets(
    'focused browser textarea survives sliver recycling',
    (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 420,
            child: ListView(
              children: [
                const SizedBox(height: 360),
                Column(
                  children: [
                    const Text('NEGATIVE PROMPT'),
                    BrowserNativeTextArea(
                      controller: controller,
                      focusNode: focusNode,
                      height: 100,
                      backgroundColor: const Color(0xFF121212),
                      style: const TextStyle(fontSize: 16),
                      fallback: TextField(
                        controller: controller,
                        focusNode: focusNode,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pumpAndSettle();
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(focusNode.hasFocus, isTrue);
      expect(
        find.byType(BrowserNativeTextArea, skipOffstage: false),
        findsOneWidget,
      );
    },
    skip: !supportsBrowserNativeTextArea,
  );
}
