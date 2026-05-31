import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Restricts a scrollable child (e.g. a multi-line [TextField]) to touch/stylus
/// drag-scrolling only, removing mouse-wheel scrolling.
///
/// On a multi-line TextField, a single mouse-wheel tick scrolls by the platform
/// default step, which on Android-with-a-mouse skips multiple lines (issue #14).
/// Gating the drag devices to touch + stylus means the wheel no longer drives
/// the field's internal ScrollPosition, so users no longer skip lines; keyboard
/// navigation and caret-driven scrolling are unaffected.
class TouchScrollWrap extends StatelessWidget {
  final Widget child;

  const TouchScrollWrap({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
        },
      ),
      child: child,
    );
  }
}
