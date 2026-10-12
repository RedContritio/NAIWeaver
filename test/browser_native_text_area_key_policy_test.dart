import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/widgets/browser_native_text_area_key_policy.dart';

/// The bindings WidgetsApp installs on the Web (`_defaultWebShortcuts`) that
/// swallowed editing keys typed into the native textarea. The VM test binding
/// uses the desktop defaults, so they are installed explicitly here; the
/// browser test in browser_native_text_area_test.dart runs against the real
/// Web defaults.
const _webScrollShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.space): ScrollIntent(
    direction: AxisDirection.down,
    type: ScrollIncrementType.page,
  ),
  SingleActivator(LogicalKeyboardKey.arrowDown): ScrollIntent(
    direction: AxisDirection.down,
  ),
  SingleActivator(LogicalKeyboardKey.arrowUp): ScrollIntent(
    direction: AxisDirection.up,
  ),
  SingleActivator(LogicalKeyboardKey.pageDown): ScrollIntent(
    direction: AxisDirection.down,
    type: ScrollIncrementType.page,
  ),
};

void main() {
  testWidgets('editing keys inside a scrollable are not taken by Flutter', (
    tester,
  ) async {
    final scroll = ScrollController();
    final focusNode = FocusNode();
    addTearDown(scroll.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: _webScrollShortcuts,
          child: ListView(
            controller: scroll,
            children: [
              const SizedBox(height: 200),
              Shortcuts(
                shortcuts: browserNativeTextAreaShortcuts,
                child: Focus(
                  focusNode: focusNode,
                  child: const SizedBox(height: 100),
                ),
              ),
              const SizedBox(height: 3000),
            ],
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.pageDown,
    ]) {
      // Unhandled means the engine leaves the browser's default action alone.
      expect(await tester.sendKeyEvent(key), isFalse, reason: '$key');
    }
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
  });
}
