import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Material 3 window size classes.
///
/// compact < 600, medium 600-839, expanded 840-1199, large 1200-1599,
/// xlarge >= 1600.
enum WindowSizeClass {
  compact,
  medium,
  expanded,
  large,
  xlarge;

  /// True for compact and medium: use touch-sized controls and bottom sheets.
  bool get isTouchSized => index <= WindowSizeClass.medium.index;

  /// True for large and xlarge: room for a persistent sidebar.
  bool get isSidebarCapable => index >= WindowSizeClass.large.index;

  /// True when this class is at least [other].
  bool atLeast(WindowSizeClass other) => index >= other.index;
}

/// Classifies a width (logical pixels), e.g. from `LayoutBuilder` constraints.
WindowSizeClass windowSizeClassForWidth(double width) {
  if (width < 600) return WindowSizeClass.compact;
  if (width < 840) return WindowSizeClass.medium;
  if (width < 1200) return WindowSizeClass.expanded;
  if (width < 1600) return WindowSizeClass.large;
  return WindowSizeClass.xlarge;
}

/// Classifies the current window via [MediaQuery].
WindowSizeClass windowSizeClassOf(BuildContext context) =>
    windowSizeClassForWidth(MediaQuery.sizeOf(context).width);

/// True when the window is below 840 (compact or medium).
bool isTouchSized(BuildContext context) =>
    windowSizeClassOf(context).isTouchSized;

/// Returns true if the screen width is less than 600px (phone-sized).
@Deprecated('Use windowSizeClassOf(context) == WindowSizeClass.compact')
bool isMobile(BuildContext context) => MediaQuery.of(context).size.width < 600;

/// Returns true on desktop platforms (Windows, Linux, macOS).
/// Always false on web.
bool isDesktopPlatform() {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

/// Returns [desktop] on wide screens, [mobile] on narrow screens.
double responsiveFont(BuildContext context, double desktop, double mobile) =>
    isMobile(context) ? mobile : desktop;

/// Returns 48 on mobile (Material touch target), 32 on desktop.
@Deprecated('Use context.touchSize / context.hitSize (VisionMetrics)')
double touchTarget(BuildContext context) => isMobile(context) ? 48.0 : 32.0;

/// Returns true when the widescreen sidebar layout should be used.
///
/// [sidebarMode] is one of 'auto', 'always', 'never'.
@Deprecated('Use windowSizeClassOf(context).isSidebarCapable')
bool isWidescreenLayout(BuildContext context, String sidebarMode) {
  if (sidebarMode == 'never') return false;
  final width = MediaQuery.of(context).size.width;
  if (sidebarMode == 'always') return width >= 1200;
  // 'auto': only on desktop platforms with sufficient width
  return isDesktopPlatform() && width >= 1200;
}
