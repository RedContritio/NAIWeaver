import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// How much of the platform-reported mouse-wheel delta Android keeps.
///
/// Android's embedder converts one wheel notch into
/// ViewConfiguration.getScaledVerticalScrollFactor() logical pixels — ~64,
/// and more on some OEM skins — which jumps 3-4 text lines per notch in the
/// prompt boxes (issue #14). 0.3 lands one notch at roughly one text line
/// while keeping fast spins proportional. Desktop deltas already feel right
/// and are left untouched.
const double kAndroidWheelScrollFactor = 0.3;

/// Returns the wheel-scroll [delta] to actually apply, scaling down
/// Android mouse-wheel deltas (issue #14). Pure so it's unit-testable;
/// trackpads and touch-derived scroll deltas pass through untouched on
/// every platform.
Offset tamedWheelDelta({
  required Offset delta,
  required TargetPlatform platform,
  required PointerDeviceKind kind,
}) {
  if (platform != TargetPlatform.android || kind != PointerDeviceKind.mouse) {
    return delta;
  }
  return delta * kAndroidWheelScrollFactor;
}

/// Drop-in replacement for [WidgetsFlutterBinding] that rescales mouse-wheel
/// deltas before dispatch, so text fields and lists all scroll by the same
/// tamed amount (issue #14). Rescaling here — rather than per-widget — is the
/// only way to reach the scrollables embedded inside TextField/EditableText.
class NaiWidgetsBinding extends WidgetsFlutterBinding {
  static WidgetsBinding ensureInitialized() {
    if (!_initialized) {
      NaiWidgetsBinding();
      _initialized = true;
    }
    return WidgetsBinding.instance;
  }

  static bool _initialized = false;

  @override
  void dispatchEvent(PointerEvent event, HitTestResult? hitTestResult) {
    super.dispatchEvent(_tameWheelEvent(event), hitTestResult);
  }

  PointerEvent _tameWheelEvent(PointerEvent event) {
    if (event is! PointerScrollEvent) return event;
    final tamed = tamedWheelDelta(
      delta: event.scrollDelta,
      platform: defaultTargetPlatform,
      kind: event.kind,
    );
    if (tamed == event.scrollDelta) return event;
    return PointerScrollEvent(
      viewId: event.viewId,
      timeStamp: event.timeStamp,
      kind: event.kind,
      device: event.device,
      position: event.position,
      scrollDelta: tamed,
      embedderId: event.embedderId,
      onRespond: event.respond,
    );
  }
}
