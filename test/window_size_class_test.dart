import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/utils/responsive.dart';

void main() {
  test('windowSizeClassForWidth honours Material 3 boundaries', () {
    final cases = {
      0.0: WindowSizeClass.compact,
      599.0: WindowSizeClass.compact,
      600.0: WindowSizeClass.medium,
      839.0: WindowSizeClass.medium,
      840.0: WindowSizeClass.expanded,
      1199.0: WindowSizeClass.expanded,
      1200.0: WindowSizeClass.large,
      1599.0: WindowSizeClass.large,
      1600.0: WindowSizeClass.xlarge,
    };
    cases.forEach(
      (w, c) => expect(windowSizeClassForWidth(w), c, reason: '$w'),
    );
    expect(WindowSizeClass.medium.isTouchSized, isTrue);
    expect(WindowSizeClass.expanded.isTouchSized, isFalse);
  });
}
