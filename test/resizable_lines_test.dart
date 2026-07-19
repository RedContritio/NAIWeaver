import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/utils/resizable_lines.dart';

void main() {
  group('linesAfterDrag', () {
    // A character prompt line: fontSize 11 * 1.4 line height.
    const lineHeight = 15.4;

    test('no movement keeps the starting size', () {
      expect(
        linesAfterDrag(startLines: 3, dragDy: 0, lineHeightPx: lineHeight),
        3,
      );
    });

    test('small jitters below half a line do not resize', () {
      expect(
        linesAfterDrag(
            startLines: 3, dragDy: lineHeight * 0.4, lineHeightPx: lineHeight),
        3,
      );
      expect(
        linesAfterDrag(
            startLines: 3, dragDy: -lineHeight * 0.4, lineHeightPx: lineHeight),
        3,
      );
    });

    test('dragging down grows line by line', () {
      expect(
        linesAfterDrag(
            startLines: 3, dragDy: lineHeight, lineHeightPx: lineHeight),
        4,
      );
      expect(
        linesAfterDrag(
            startLines: 3, dragDy: lineHeight * 5, lineHeightPx: lineHeight),
        8,
      );
    });

    test('dragging up shrinks and clamps at the minimum', () {
      expect(
        linesAfterDrag(
            startLines: 5, dragDy: -lineHeight * 2, lineHeightPx: lineHeight),
        3,
      );
      expect(
        linesAfterDrag(
            startLines: 3, dragDy: -lineHeight * 100, lineHeightPx: lineHeight),
        kCharPromptMinLines,
      );
    });

    test('clamps at the maximum', () {
      expect(
        linesAfterDrag(
            startLines: 3, dragDy: lineHeight * 100, lineHeightPx: lineHeight),
        kCharPromptMaxLines,
      );
    });

    test('is computed from the drag start, not cumulative per event', () {
      // The same total dy always lands on the same size regardless of how
      // many update events delivered it.
      final oneGo = linesAfterDrag(
          startLines: 3, dragDy: lineHeight * 3, lineHeightPx: lineHeight);
      expect(oneGo, 6);
    });

    test('honors custom bounds', () {
      expect(
        linesAfterDrag(
          startLines: 1,
          dragDy: 1000,
          lineHeightPx: lineHeight,
          minLines: 1,
          maxLines: 4,
        ),
        4,
      );
    });
  });
}
