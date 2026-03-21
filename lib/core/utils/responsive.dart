import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Returns true if the screen width is less than 600px (phone-sized).
bool isMobile(BuildContext context) =>
    MediaQuery.of(context).size.width < 600;

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
double touchTarget(BuildContext context) => isMobile(context) ? 48.0 : 32.0;

/// Returns true when the widescreen sidebar layout should be used.
///
/// [sidebarMode] is one of 'auto', 'always', 'never'.
bool isWidescreenLayout(BuildContext context, String sidebarMode) {
  if (sidebarMode == 'never') return false;
  final width = MediaQuery.of(context).size.width;
  if (sidebarMode == 'always') return width >= 1200;
  // 'auto': only on desktop platforms with sufficient width
  return isDesktopPlatform() && width >= 1200;
}
