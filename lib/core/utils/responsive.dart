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

/// Returns true on desktop platforms (Windows, Linux, macOS).
/// Always false on web.
bool isDesktopPlatform() {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
