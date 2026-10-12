@TestOn('browser')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/core/widgets/browser_native_text_area.dart';
import 'package:naiweaver/features/generation/widgets/prompt_shortcuts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import 'browser_platform_view_test_support.dart';

/// The engine hands a keydown to Flutter (window capture listener) and the
/// browser then delivers the same event to the textarea. A widget test has no
/// engine listener and an unattached element, so one physical key press is
/// reproduced by sending both halves.
Future<void> _press(
  WidgetTester tester,
  web.HTMLTextAreaElement textarea, {
  required LogicalKeyboardKey key,
  required String domKey,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  textarea.dispatchEvent(
    web.KeyboardEvent(
      'keydown',
      web.KeyboardEventInit(
        key: domKey,
        ctrlKey: true,
        cancelable: true,
        bubbles: true,
      ),
    ),
  );
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testPlatformViewWidgets(
    'one keydown in the native prompt editor runs its shortcut once',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({});
        final preferences = PreferencesService(
          await SharedPreferences.getInstance(),
          const FlutterSecureStorage(),
        );
        final controller = TextEditingController(text: 'cat');
        final focusNode = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focusNode.dispose);
        var weightSteps = 0;
        var generated = 0;

        await tester.pumpWidget(
          ChangeNotifierProvider(
            create: (_) => ThemeNotifier(preferences),
            child: MaterialApp(
              home: Scaffold(
                body: GenerationShortcuts(
                  onGenerate: () => generated++,
                  onCycleStyle: (_) {},
                  child: PromptKeyScope(
                    controller: controller,
                    actions: {
                      AdjustTagWeightIntent:
                          PromptAction<AdjustTagWeightIntent>(
                            onInvoke: (_) => weightSteps++,
                          ),
                    },
                    builder: (context, onKeyDown) => BrowserNativeTextArea(
                      controller: controller,
                      focusNode: focusNode,
                      height: 100,
                      onKeyDown: onKeyDown,
                      fallback: const SizedBox(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final textarea = await platformViewElement<web.HTMLTextAreaElement>(
          tester,
        );
        focusNode.requestFocus();
        await tester.pump();

        await _press(
          tester,
          textarea,
          key: LogicalKeyboardKey.arrowUp,
          domKey: 'ArrowUp',
        );
        expect(weightSteps, 1);

        await _press(
          tester,
          textarea,
          key: LogicalKeyboardKey.enter,
          domKey: 'Enter',
        );
        expect(generated, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
