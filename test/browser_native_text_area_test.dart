@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/core/widgets/browser_native_text_area.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import 'browser_platform_view_test_support.dart';

Future<void> pumpThemed(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = PreferencesService(
    await SharedPreferences.getInstance(),
    const FlutterSecureStorage(),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(preferences),
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
}

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  BrowserNativeTextArea editor({ValueChanged<String>? onChanged}) =>
      BrowserNativeTextArea(
        controller: controller,
        focusNode: focusNode,
        height: 100,
        onChanged: onChanged,
        fallback: const SizedBox(),
      );

  testPlatformViewWidgets(
    'focused browser textarea survives sliver recycling',
    (tester) async {
      await pumpThemed(
        tester,
        SizedBox(
          height: 420,
          child: ListView(
            children: [
              const SizedBox(height: 360),
              Column(children: [const Text('NEGATIVE PROMPT'), editor()]),
              const SizedBox(height: 1200),
            ],
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
  );

  testPlatformViewWidgets(
    'editing keys inside a scrollable are left to the textarea',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpThemed(
        tester,
        ListView(
          controller: scroll,
          children: [
            const SizedBox(height: 200),
            editor(),
            const SizedBox(height: 3000),
          ],
        ),
      );
      focusNode.requestFocus();
      await tester.pump();

      for (final key in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.home,
      ]) {
        final handled = await tester.sendKeyEvent(key);
        expect(handled, isFalse, reason: '$key must reach the textarea');
      }
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(focusNode.hasFocus, isTrue);
    },
  );

  testPlatformViewWidgets('controller edits keep the controller selection', (
    tester,
  ) async {
    await pumpThemed(tester, editor());
    final textarea = await platformViewElement<web.HTMLTextAreaElement>(tester);

    controller.value = const TextEditingValue(
      text: 'cat, dog',
      selection: TextSelection.collapsed(offset: 3),
    );
    expect(textarea.value, 'cat, dog');
    expect((textarea.selectionStart, textarea.selectionEnd), (3, 3));

    // A tag-weight adjustment rewrites the text around the selection.
    controller.value = const TextEditingValue(
      text: '1.1::cat::, dog',
      selection: TextSelection(baseOffset: 5, extentOffset: 8),
    );
    expect(textarea.value, '1.1::cat::, dog');
    expect((textarea.selectionStart, textarea.selectionEnd), (5, 8));
  });

  testPlatformViewWidgets('a disposed editor ignores its old DOM element', (
    tester,
  ) async {
    final changes = <String>[];
    controller.text = 'kept';
    await pumpThemed(tester, editor(onChanged: changes.add));
    final textarea = await platformViewElement<web.HTMLTextAreaElement>(tester);

    await pumpThemed(tester, const SizedBox());
    textarea.value = 'typed after dispose';
    textarea.dispatchEvent(web.InputEvent('input'));
    textarea.dispatchEvent(web.KeyboardEvent('keyup'));
    textarea.dispatchEvent(web.Event('focus'));

    expect(changes, isEmpty);
    expect(controller.text, 'kept');
    expect(focusNode.hasFocus, isFalse);
  });
}
