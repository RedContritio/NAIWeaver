import 'package:flutter/widgets.dart';

/// Non-color design tokens: spacing, radius, opacity, touch and icon sizes.
///
/// These are theme-independent constants. Use `context.m` for the
/// size-class aware values ([VisionMetrics.touchTargetFor]) and the static
/// members directly for everything else.
abstract final class VisionMetrics {
  // — Spacing —
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space24 = 24;

  // — Radius (4 is the default) —
  static const double radius2 = 2;
  static const double radius4 = 4;
  static const double radius8 = 8;
  static const double radius12 = 12;

  // — Opacity steps —
  static const double opacityHover = 0.08;
  static const double opacityPressed = 0.15;
  static const double opacityDisabled = 0.4;
  static const double opacityScrim = 0.5;
  static const double opacityOverlay = 0.8;

  // — Touch sizes —
  /// Visual size of a control on touch-sized windows (compact / medium).
  static const double touchTargetTouch = 48;

  /// Visual size of a control on expanded and larger windows.
  static const double touchTargetPointer = 32;

  /// Smallest hit area any interactive control may have.
  static const double minHitTarget = 40;

  // — Icon sizes —
  static const double iconSmall = 14;
  static const double iconMedium = 18;
  static const double iconLarge = 24;

  // — Border —
  static const double borderWidth = 1;

  /// Visual control size for a window of [width] logical pixels.
  static double touchTargetForWidth(double width) =>
      width < 840 ? touchTargetTouch : touchTargetPointer;

  /// Visual control size for the current window.
  static double touchTargetFor(BuildContext context) =>
      touchTargetForWidth(MediaQuery.sizeOf(context).width);

  /// Hit area for the current window: the visual size, but never below
  /// [minHitTarget].
  static double hitTargetFor(BuildContext context) {
    final v = touchTargetFor(context);
    return v < minHitTarget ? minHitTarget : v;
  }

  static BorderRadius get borderRadius4 => BorderRadius.circular(radius4);
}
