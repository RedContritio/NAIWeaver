import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/widgets/browser_native_text_area_key_policy.dart';

void main() {
  test('ordinary editing keys keep browser default but stop propagation', () {
    final policy = browserNativeTextAreaKeyPolicy(false);
    expect(policy.preventDefault, isFalse);
    expect(policy.stopPropagation, isTrue);
  });

  test('handled shortcuts suppress browser default and propagation', () {
    final policy = browserNativeTextAreaKeyPolicy(true);
    expect(policy.preventDefault, isTrue);
    expect(policy.stopPropagation, isTrue);
  });
}
