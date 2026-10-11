import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'client_diagnostics.dart';
import 'client_diagnostics_platform.dart';

/// App-lifetime diagnostic observers. The trail stays in memory and is only
/// exported when the user explicitly submits a feedback report.
class ClientDiagnosticsRuntime with WidgetsBindingObserver {
  ClientDiagnosticsRuntime._();

  static final ClientDiagnosticsRuntime instance = ClientDiagnosticsRuntime._();

  final ClientDiagnostics _diagnostics = ClientDiagnostics.instance;
  Timer? _heartbeat;
  bool _started = false;
  String? _lastFocusSignature;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onFocusChanged);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointerEvent);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    startClientDiagnosticsPlatformSession(_diagnostics);
    _diagnostics.record('diagnostic_runtime_started', {
      'web': kIsWeb,
      'build_mode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      'target_platform': defaultTargetPlatform.name,
      'lifecycle_state': WidgetsBinding.instance.lifecycleState?.name,
    });
    _recordMetrics('flutter_metrics_initial');
    _onFocusChanged();
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      _diagnostics.record('diagnostic_heartbeat', {
        'lifecycle_state': WidgetsBinding.instance.lifecycleState?.name,
        'primary_focus_present': FocusManager.instance.primaryFocus != null,
        'retained_event_count': _diagnostics.length,
        'dropped_event_count': _diagnostics.droppedCount,
      });
    });
  }

  void _onFocusChanged() {
    final focus = FocusManager.instance.primaryFocus;
    final signature = focus == null
        ? 'none'
        : '${focus.runtimeType}:${focus.debugLabel ?? ''}:${focus.hasFocus}';
    if (signature == _lastFocusSignature) return;
    _lastFocusSignature = signature;
    _diagnostics.record('flutter_primary_focus_changed', {
      'focus_present': focus != null,
      'focus_node_type': focus?.runtimeType.toString(),
      'focus_debug_label': focus?.debugLabel,
      'has_primary_focus': focus?.hasPrimaryFocus,
      'has_focus': focus?.hasFocus,
    });
  }

  void _onPointerEvent(PointerEvent event) {
    if (event is! PointerDownEvent && event is! PointerCancelEvent) return;
    _diagnostics.record(
      event is PointerDownEvent
          ? 'flutter_pointer_down'
          : 'flutter_pointer_cancel',
      {
        'pointer': event.pointer,
        'device_kind': event.kind.name,
        'buttons': event.buttons,
        'x': event.position.dx.round(),
        'y': event.position.dy.round(),
        'view_id': event.viewId,
      },
    );
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final category = clientDiagnosticKeyCategory(event.logicalKey);
    // Text entry is captured as length/selection changes by the controllers.
    // Logging both browser and Flutter character key events would add no
    // diagnostic signal and would evict more valuable lifecycle history.
    if (category == 'character') return false;
    _diagnostics.record('flutter_key_down', {
      'key_category': category,
      'repeat': event is KeyRepeatEvent,
      'control': HardwareKeyboard.instance.isControlPressed,
      'meta': HardwareKeyboard.instance.isMetaPressed,
      'alt': HardwareKeyboard.instance.isAltPressed,
      'shift': HardwareKeyboard.instance.isShiftPressed,
    });
    return false;
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    final slow = <FrameTiming>[];
    for (final timing in timings) {
      final totalMs = timing.totalSpan.inMicroseconds / 1000;
      final buildMs = timing.buildDuration.inMicroseconds / 1000;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000;
      if (totalMs >= 34 || buildMs >= 17 || rasterMs >= 17) slow.add(timing);
    }
    if (slow.isEmpty) return;
    double maxTotalMs = 0;
    double maxBuildMs = 0;
    double maxRasterMs = 0;
    double totalMsSum = 0;
    for (final timing in slow) {
      final totalMs = timing.totalSpan.inMicroseconds / 1000;
      final buildMs = timing.buildDuration.inMicroseconds / 1000;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000;
      totalMsSum += totalMs;
      if (totalMs > maxTotalMs) maxTotalMs = totalMs;
      if (buildMs > maxBuildMs) maxBuildMs = buildMs;
      if (rasterMs > maxRasterMs) maxRasterMs = rasterMs;
    }
    _diagnostics.record('flutter_slow_frame_batch', {
      'reported_frame_count': timings.length,
      'slow_frame_count': slow.length,
      'average_slow_total_ms': _roundMetric(totalMsSum / slow.length),
      'max_total_ms': _roundMetric(maxTotalMs),
      'max_build_ms': _roundMetric(maxBuildMs),
      'max_raster_ms': _roundMetric(maxRasterMs),
      'last_frame_number': slow.last.frameNumber,
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _diagnostics.record('flutter_lifecycle_changed', {'state': state.name});
  }

  @override
  void didChangeMetrics() => _recordMetrics('flutter_metrics_changed');

  @override
  void didChangeAccessibilityFeatures() {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    _diagnostics.record('flutter_accessibility_changed', {
      'accessible_navigation': features.accessibleNavigation,
      'bold_text': features.boldText,
      'disable_animations': features.disableAnimations,
      'high_contrast': features.highContrast,
      'invert_colors': features.invertColors,
      'reduce_motion': features.reduceMotion,
    });
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    _diagnostics.record('flutter_locales_changed', {
      'locale_count': locales?.length ?? 0,
      'primary_locale': locales?.firstOrNull?.toLanguageTag(),
    });
  }

  @override
  void didChangePlatformBrightness() {
    _diagnostics.record('flutter_platform_brightness_changed', {
      'brightness':
          WidgetsBinding.instance.platformDispatcher.platformBrightness.name,
    });
  }

  @override
  void didChangeTextScaleFactor() {
    _diagnostics.record('flutter_text_scale_changed', {
      'text_scale_factor':
          WidgetsBinding.instance.platformDispatcher.textScaleFactor,
    });
  }

  @override
  void didHaveMemoryPressure() {
    _diagnostics.record('flutter_memory_pressure');
  }

  void _recordMetrics(String event) {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final view = views.first;
    _diagnostics.record(event, {
      'physical_width': view.physicalSize.width,
      'physical_height': view.physicalSize.height,
      'device_pixel_ratio': view.devicePixelRatio,
      'view_insets_bottom': view.viewInsets.bottom,
      'view_padding_bottom': view.viewPadding.bottom,
      'system_gesture_insets_bottom': view.systemGestureInsets.bottom,
    });
  }

  static double _roundMetric(double value) =>
      (value * 100).roundToDouble() / 100;
}

class DiagnosticsNavigatorObserver extends NavigatorObserver {
  DiagnosticsNavigatorObserver._();

  static final DiagnosticsNavigatorObserver instance =
      DiagnosticsNavigatorObserver._();

  void _record(String event, Route<dynamic>? route, Route<dynamic>? previous) {
    ClientDiagnostics.instance.record(event, {
      'route_type': route?.runtimeType.toString(),
      'route_name': route?.settings.name,
      'previous_route_type': previous?.runtimeType.toString(),
      'previous_route_name': previous?.settings.name,
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('navigator_push', route, previousRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('navigator_pop', route, previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('navigator_remove', route, previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record('navigator_replace', newRoute, oldRoute);
}
