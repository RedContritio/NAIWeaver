import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/utils/wheel_scroll.dart';

void main() {
  group('tamedWheelDelta', () {
    test('scales Android mouse-wheel deltas down to ~one line per notch', () {
      // One notch on a stock Android device: 64 logical px.
      final tamed = tamedWheelDelta(
        delta: const Offset(0, 64),
        platform: TargetPlatform.android,
        kind: PointerDeviceKind.mouse,
      );
      expect(tamed.dy, closeTo(64 * kAndroidWheelScrollFactor, 0.001));
      // ~One text line (fontSize 12-14 at ~1.4 line height ≈ 17-20 px).
      expect(tamed.dy, inInclusiveRange(15, 25));
    });

    test('keeps fast spins proportional and preserves sign', () {
      final oneNotch = tamedWheelDelta(
        delta: const Offset(0, -64),
        platform: TargetPlatform.android,
        kind: PointerDeviceKind.mouse,
      );
      final fourNotches = tamedWheelDelta(
        delta: const Offset(0, -256),
        platform: TargetPlatform.android,
        kind: PointerDeviceKind.mouse,
      );
      expect(oneNotch.dy, lessThan(0));
      expect(fourNotches.dy, closeTo(oneNotch.dy * 4, 0.001));
    });

    test('scales horizontal deltas too (tilt-wheel / shift-scroll)', () {
      final tamed = tamedWheelDelta(
        delta: const Offset(64, 0),
        platform: TargetPlatform.android,
        kind: PointerDeviceKind.mouse,
      );
      expect(tamed.dx, closeTo(64 * kAndroidWheelScrollFactor, 0.001));
    });

    test('leaves desktop platforms untouched', () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ]) {
        final tamed = tamedWheelDelta(
          delta: const Offset(0, 120),
          platform: platform,
          kind: PointerDeviceKind.mouse,
        );
        expect(tamed, const Offset(0, 120), reason: '$platform');
      }
    });

    test('leaves non-mouse device kinds untouched on Android', () {
      for (final kind in [
        PointerDeviceKind.trackpad,
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
      ]) {
        final tamed = tamedWheelDelta(
          delta: const Offset(0, 64),
          platform: TargetPlatform.android,
          kind: kind,
        );
        expect(tamed, const Offset(0, 64), reason: '$kind');
      }
    });

    test('zero delta stays zero', () {
      final tamed = tamedWheelDelta(
        delta: Offset.zero,
        platform: TargetPlatform.android,
        kind: PointerDeviceKind.mouse,
      );
      expect(tamed, Offset.zero);
    });
  });
}
