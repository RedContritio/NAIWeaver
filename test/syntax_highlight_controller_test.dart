import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/widgets/syntax_highlight_controller.dart';

void main() {
  /// Builds the span tree for [text] and returns the flattened plain text of
  /// each leaf span in order.
  List<TextSpan> spansFor(WidgetTester tester, String text) {
    final controller = SyntaxHighlightController(text: text);
    final context = tester.element(find.byType(SizedBox));
    final root = controller.buildTextSpan(
      context: context,
      style: const TextStyle(color: Colors.white),
      withComposing: false,
    );
    final leaves = <TextSpan>[];
    root.visitChildren((span) {
      if (span is TextSpan && span.text != null) leaves.add(span);
      return true;
    });
    return leaves;
  }

  String joined(List<TextSpan> spans) => spans.map((s) => s.text).join();

  Future<void> pump(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: SizedBox()));

  testWidgets('round-trips plain text unchanged', (tester) async {
    await pump(tester);
    const text = '1girl, long hair, artist:test';
    expect(joined(spansFor(tester, text)), text);
  });

  testWidgets('highlights the full N::tag:: unit including closing delimiter',
      (tester) async {
    await pump(tester);
    const text = '2::black hair::, smile';
    final spans = spansFor(tester, text);
    expect(joined(spans), text);
    expect(spans[0].text, '2::');
    expect(spans[0].style?.color, isNot(Colors.white));
    expect(spans[1].text, 'black hair');
    expect(spans[1].style?.color, isNot(Colors.white));
    expect(spans[2].text, '::');
    expect(spans[2].style?.color, isNot(Colors.white));
    // Trailing text is plain.
    expect(spans[3].style?.color, Colors.white);
  });

  testWidgets('supports negative and fractional weights', (tester) async {
    await pump(tester);
    for (final text in ['-1::glasses::', '1.5::smile::', '-0.5::blur::']) {
      final spans = spansFor(tester, text);
      expect(joined(spans), text);
      expect(spans.first.style?.color, isNot(Colors.white),
          reason: 'weight prefix of "$text" should be highlighted');
    }
  });

  testWidgets('leaves an unterminated weight prefix as prefix-only highlight',
      (tester) async {
    await pump(tester);
    const text = '2::black ha';
    final spans = spansFor(tester, text);
    expect(joined(spans), text);
    expect(spans[0].text, '2::');
    expect(spans[1].style?.color, Colors.white);
  });

  // Regression: a weight prefix inside brackets used to make buildTextSpan
  // spin forever (the bracket run-collector broke at the match but nothing
  // consumed it), freezing the app as soon as e.g. `{2::` was typed.
  testWidgets('terminates on weight prefixes inside brackets', (tester) async {
    await pump(tester);
    for (final text in [
      '{2::tag::}',
      '[1.5::tag::]',
      '{{nested, 2::deep::}}',
      '{2::unterminated',
    ]) {
      expect(joined(spansFor(tester, text)), text,
          reason: '"$text" should render all characters exactly once');
    }
  });

  testWidgets('still colors brace and bracket emphasis', (tester) async {
    await pump(tester);
    const text = '{{1girl}}, [background]';
    final spans = spansFor(tester, text);
    expect(joined(spans), text);
    expect(spans.first.style?.color, isNot(Colors.white));
  });

  testWidgets('disabled controller returns unstyled text', (tester) async {
    await pump(tester);
    final controller =
        SyntaxHighlightController(text: '2::tag::', enabled: false);
    final context = tester.element(find.byType(SizedBox));
    final root = controller.buildTextSpan(
      context: context,
      style: const TextStyle(color: Colors.white),
      withComposing: false,
    );
    expect(root.toPlainText(), '2::tag::');
  });
}
