import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/widgets/browser_native_key_event.dart';
import 'package:naiweaver/features/generation/widgets/prompt_composer.dart';
import 'package:naiweaver/features/generation/widgets/prompt_shortcuts.dart';

import 'test_harness.dart';

/// A composer wired like the page wires it: completions in, accepted tag out.
class _ComposerHarness extends StatefulWidget {
  const _ComposerHarness({
    required this.controller,
    required this.onGenerate,
    this.suggestions = const [],
  });

  final TextEditingController controller;
  final VoidCallback onGenerate;
  final List<DanbooruTag> suggestions;

  @override
  State<_ComposerHarness> createState() => _ComposerHarnessState();
}

class _ComposerHarnessState extends State<_ComposerHarness> {
  final key = GlobalKey<PromptComposerState>();
  final accepted = <String>[];

  @override
  Widget build(BuildContext context) {
    return GenerationShortcuts(
      onGenerate: widget.onGenerate,
      onCycleStyle: (_) {},
      child: PromptComposer(
        key: key,
        controller: widget.controller,
        suggestions: widget.suggestions,
        slot: PromptLayoutSlot.footer,
        defaultLines: 4,
        action: const SizedBox.shrink(),
        onTextChanged: (_) {},
        onSuggestionAccepted: (tag) => accepted.add(tag.tag),
        onSuggestionsDismissed: () {},
      ),
    );
  }
}

/// The negative prompt's editor: a plain field behind the shared scope.
class _NegativeHarness extends StatelessWidget {
  const _NegativeHarness({
    required this.controller,
    required this.onGenerate,
    this.onKeyDown,
  });

  final TextEditingController controller;
  final VoidCallback onGenerate;
  final void Function(BrowserNativeKeyHandler handler)? onKeyDown;

  @override
  Widget build(BuildContext context) {
    return GenerationShortcuts(
      onGenerate: onGenerate,
      onCycleStyle: (_) {},
      child: PromptKeyScope(
        controller: controller,
        builder: (context, handler) {
          onKeyDown?.call(handler);
          return TextField(
            key: const ValueKey('negative'),
            controller: controller,
            maxLines: 3,
          );
        },
      ),
    );
  }
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  final tags = [
    DanbooruTag(tag: 'blue_sky', count: 10),
    DanbooruTag(tag: 'blue_eyes', count: 9),
  ];

  group('generate shortcut', () {
    for (final entry in {
      'main prompt': true,
      'negative prompt': false,
    }.entries) {
      final mainPrompt = entry.value;

      Future<void> pump(
        WidgetTester tester,
        TextEditingController controller,
        VoidCallback onGenerate,
      ) async {
        await pumpHarness(
          tester,
          mainPrompt
              ? _ComposerHarness(controller: controller, onGenerate: onGenerate)
              : _NegativeHarness(
                  controller: controller,
                  onGenerate: onGenerate,
                ),
          size: const Size(900, 700),
        );
        await tester.tap(
          find.byKey(
            mainPrompt ? PromptComposer.fieldKey : const ValueKey('negative'),
          ),
        );
        await tester.pump();
      }

      testWidgets('${entry.key}: Cmd+Enter on Apple platforms', (tester) async {
        await _onPlatform(TargetPlatform.macOS, () async {
          final controller = TextEditingController(text: 'a');
          addTearDown(controller.dispose);
          var generated = 0;
          await pump(tester, controller, () => generated++);

          await _chord(
            tester,
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.enter,
          );
          expect(generated, 1, reason: 'Ctrl+Enter also generates on a Mac');

          await _chord(
            tester,
            LogicalKeyboardKey.metaLeft,
            LogicalKeyboardKey.enter,
          );
          expect(generated, 2);
        });
      });

      testWidgets('${entry.key}: Ctrl+Enter elsewhere', (tester) async {
        await _onPlatform(TargetPlatform.windows, () async {
          final controller = TextEditingController(text: 'a');
          addTearDown(controller.dispose);
          var generated = 0;
          await pump(tester, controller, () => generated++);

          await _chord(
            tester,
            LogicalKeyboardKey.metaLeft,
            LogicalKeyboardKey.enter,
          );
          expect(generated, 0);

          await _chord(
            tester,
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.enter,
          );
          expect(generated, 1);
        });
      });
    }
  });

  testWidgets('weight shortcut uses the platform command key', (tester) async {
    await _onPlatform(TargetPlatform.macOS, () async {
      final controller = TextEditingController(text: 'blue_sky')
        ..selection = const TextSelection.collapsed(offset: 3);
      addTearDown(controller.dispose);
      await pumpHarness(
        tester,
        _NegativeHarness(controller: controller, onGenerate: () {}),
        size: const Size(900, 700),
      );
      await tester.tap(find.byKey(const ValueKey('negative')));
      await tester.pump();
      controller.selection = const TextSelection.collapsed(offset: 3);

      await _chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.arrowUp,
      );
      expect(controller.text, 'blue_sky');

      await _chord(
        tester,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.arrowUp,
      );
      expect(controller.text, '1.1::blue_sky::');
    });
  });

  group('browser textarea keydown', () {
    testWidgets('runs the same mapping as the Flutter keys', (tester) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        final controller = TextEditingController(text: 'a');
        addTearDown(controller.dispose);
        late BrowserNativeKeyHandler onKeyDown;
        var generated = 0;
        await pumpHarness(
          tester,
          _NegativeHarness(
            controller: controller,
            onGenerate: () => generated++,
            onKeyDown: (handler) => onKeyDown = handler,
          ),
          size: const Size(900, 700),
        );

        expect(
          onKeyDown(const BrowserNativeKeyEvent(key: 'Enter', control: true)),
          isTrue,
        );
        expect(
          onKeyDown(const BrowserNativeKeyEvent(key: 'Enter', meta: true)),
          isTrue,
        );
        expect(generated, 2);
      });
    });
  });

  group('completions', () {
    Future<_ComposerHarnessState> pump(
      WidgetTester tester,
      TextEditingController controller,
    ) async {
      await pumpHarness(
        tester,
        _ComposerHarness(
          controller: controller,
          onGenerate: () {},
          suggestions: tags,
        ),
        size: const Size(900, 700),
      );
      await tester.tap(find.byKey(PromptComposer.fieldKey));
      await tester.pump();
      return tester.state<_ComposerHarnessState>(find.byType(_ComposerHarness));
    }

    testWidgets('Enter does not accept while the input method composes', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'blue');
      addTearDown(controller.dispose);
      final host = await pump(tester, controller);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      controller.value = const TextEditingValue(
        text: 'blue',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 0, end: 4),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(host.accepted, isEmpty);

      controller.value = const TextEditingValue(
        text: 'blue',
        selection: TextSelection.collapsed(offset: 4),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(host.accepted, ['blue_sky']);
    });

    testWidgets('accepting a completion returns the focus to the editor', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'blue');
      addTearDown(controller.dispose);
      final host = await pump(tester, controller);
      final composer = host.key.currentState!;

      // A tap on a chip lands outside the field: the field has lost focus.
      composer.unfocus();
      await tester.pump();
      expect(composer.focusNode.hasFocus, isFalse);

      await tester.tap(find.textContaining('blue_eyes'));
      await tester.pump();

      expect(host.accepted, ['blue_eyes']);
      expect(composer.focusNode.hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
