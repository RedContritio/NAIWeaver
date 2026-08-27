import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'client_diagnostics.dart';

Future<Map<String, dynamic>> collectClientPlatformInfo() async => {
  'platform': web.window.navigator.platform,
  'web': true,
  'user_agent': web.window.navigator.userAgent,
  'language': web.window.navigator.language,
  'window_width': web.window.innerWidth,
  'window_height': web.window.innerHeight,
  'device_pixel_ratio': web.window.devicePixelRatio,
  'screen_width': web.window.screen.width,
  'screen_height': web.window.screen.height,
  'screen_available_width': web.window.screen.availWidth,
  'screen_available_height': web.window.screen.availHeight,
  'color_depth': web.window.screen.colorDepth,
  'screen_orientation_type': _screenOrientationType(),
  'screen_orientation_angle': _screenOrientationAngle(),
  'visual_viewport_width': web.window.visualViewport?.width,
  'visual_viewport_height': web.window.visualViewport?.height,
  'visual_viewport_offset_left': web.window.visualViewport?.offsetLeft,
  'visual_viewport_offset_top': web.window.visualViewport?.offsetTop,
  'visual_viewport_scale': web.window.visualViewport?.scale,
  'document_client_width': web.document.documentElement?.clientWidth,
  'document_client_height': web.document.documentElement?.clientHeight,
  'document_scroll_width': web.document.documentElement?.scrollWidth,
  'document_scroll_height': web.document.documentElement?.scrollHeight,
  'page_scroll_x': web.window.scrollX,
  'page_scroll_y': web.window.scrollY,
  'max_touch_points': web.window.navigator.maxTouchPoints,
  'hardware_concurrency': web.window.navigator.hardwareConcurrency,
  'online': web.window.navigator.onLine,
  'cookie_enabled': web.window.navigator.cookieEnabled,
  'document_visibility': web.document.visibilityState,
  'document_has_focus': web.document.hasFocus(),
  'timezone_name': DateTime.now().timeZoneName,
  'timezone_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
};

bool _platformSessionStarted = false;
int _lastViewportEventMs = 0;

void startClientDiagnosticsPlatformSession(ClientDiagnostics diagnostics) {
  if (_platformSessionStarted) return;
  _platformSessionStarted = true;

  void listen(
    web.EventTarget target,
    String eventName,
    void Function(web.Event) handler,
  ) {
    target.addEventListener(eventName, handler.toJS);
  }

  void recordViewport(String event) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (event.contains('scroll') && now - _lastViewportEventMs < 100) return;
    _lastViewportEventMs = now;
    final viewport = web.window.visualViewport;
    final root = web.document.documentElement;
    diagnostics.record(event, {
      'window_inner_width': web.window.innerWidth,
      'window_inner_height': web.window.innerHeight,
      'visual_viewport_width': viewport?.width,
      'visual_viewport_height': viewport?.height,
      'visual_viewport_offset_left': viewport?.offsetLeft,
      'visual_viewport_offset_top': viewport?.offsetTop,
      'visual_viewport_scale': viewport?.scale,
      'document_client_width': root?.clientWidth,
      'document_client_height': root?.clientHeight,
      'document_scroll_width': root?.scrollWidth,
      'document_scroll_height': root?.scrollHeight,
      'page_scroll_x': web.window.scrollX,
      'page_scroll_y': web.window.scrollY,
      'screen_orientation_type': _screenOrientationType(),
      'screen_orientation_angle': _screenOrientationAngle(),
      'document_visibility': web.document.visibilityState,
      'document_has_focus': web.document.hasFocus(),
    });
  }

  listen(web.window, 'focus', (_) {
    recordViewport('browser_window_focus');
  });
  listen(web.window, 'blur', (_) {
    recordViewport('browser_window_blur');
  });
  listen(web.window, 'resize', (_) {
    recordViewport('browser_window_resize');
  });
  listen(web.window, 'online', (_) {
    diagnostics.record('browser_network_changed', {'online': true});
  });
  listen(web.window, 'offline', (_) {
    diagnostics.record('browser_network_changed', {'online': false});
  });
  listen(web.window, 'pageshow', (_) {
    recordViewport('browser_page_show');
  });
  listen(web.window, 'pagehide', (_) {
    recordViewport('browser_page_hide');
  });
  listen(web.document, 'visibilitychange', (_) {
    recordViewport('browser_visibility_changed');
  });
  listen(web.document, 'pointerdown', (rawEvent) {
    final event = rawEvent as web.PointerEvent;
    diagnostics.record('browser_pointer_down', {
      'pointer_type': event.pointerType,
      'buttons': event.buttons,
      'client_x': event.clientX,
      'client_y': event.clientY,
      'is_primary': event.isPrimary,
    });
  });
  listen(web.document, 'keydown', (rawEvent) {
    final event = rawEvent as web.KeyboardEvent;
    final category = _safeKeyCategory(event.key);
    if (category == 'character') return;
    diagnostics.record('browser_key_down', {
      'key_category': category,
      'repeat': event.repeat,
      'control': event.ctrlKey,
      'meta': event.metaKey,
      'alt': event.altKey,
      'shift': event.shiftKey,
      'composing': event.isComposing,
    });
  });

  final visualViewport = web.window.visualViewport;
  if (visualViewport != null) {
    listen(visualViewport, 'resize', (_) {
      recordViewport('browser_visual_viewport_resize');
    });
    listen(visualViewport, 'scroll', (_) {
      recordViewport('browser_visual_viewport_scroll');
    });
  }

  recordViewport('browser_platform_session_started');
}

void captureClientDiagnosticsPlatformSnapshot(ClientDiagnostics diagnostics) {
  final viewport = web.window.visualViewport;
  final root = web.document.documentElement;
  diagnostics.record('browser_submission_snapshot', {
    'window_inner_width': web.window.innerWidth,
    'window_inner_height': web.window.innerHeight,
    'visual_viewport_width': viewport?.width,
    'visual_viewport_height': viewport?.height,
    'visual_viewport_offset_left': viewport?.offsetLeft,
    'visual_viewport_offset_top': viewport?.offsetTop,
    'visual_viewport_scale': viewport?.scale,
    'document_client_width': root?.clientWidth,
    'document_client_height': root?.clientHeight,
    'document_scroll_width': root?.scrollWidth,
    'document_scroll_height': root?.scrollHeight,
    'page_scroll_x': web.window.scrollX,
    'page_scroll_y': web.window.scrollY,
    'screen_width': web.window.screen.width,
    'screen_height': web.window.screen.height,
    'screen_available_width': web.window.screen.availWidth,
    'screen_available_height': web.window.screen.availHeight,
    'screen_orientation_type': _screenOrientationType(),
    'screen_orientation_angle': _screenOrientationAngle(),
    'document_visibility': web.document.visibilityState,
    'document_has_focus': web.document.hasFocus(),
    'online': web.window.navigator.onLine,
  });

  final entries = web.window.performance.getEntriesByType('resource').toDart;
  final start = entries.length > 60 ? entries.length - 60 : 0;
  for (var index = start; index < entries.length; index++) {
    final entry = entries[index] as web.PerformanceResourceTiming;
    diagnostics.record('browser_resource_timing', {
      'resource_path': _safeResourcePath(entry.name),
      'initiator_type': entry.initiatorType,
      'duration_ms': _round(entry.duration),
      'response_wait_ms': _round(entry.responseStart - entry.requestStart),
      'download_ms': _round(entry.responseEnd - entry.responseStart),
      'transfer_size': entry.transferSize,
      'protocol': entry.nextHopProtocol,
    });
  }
}

String _safeKeyCategory(String key) {
  if (key.length == 1) return 'character';
  return switch (key) {
    'Enter' => 'enter',
    'Escape' => 'escape',
    'Tab' => 'tab',
    'Backspace' || 'Delete' => 'editing',
    'ArrowUp' ||
    'ArrowDown' ||
    'ArrowLeft' ||
    'ArrowRight' ||
    'Home' ||
    'End' ||
    'PageUp' ||
    'PageDown' => 'navigation',
    _ => 'command',
  };
}

String _safeResourcePath(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) return '[unparseable]';
  final segments = uri.pathSegments.map((segment) {
    if (segment.length > 32 || RegExp(r'^\d+$').hasMatch(segment)) {
      return ':id';
    }
    return segment;
  });
  final path = '/${segments.join('/')}';
  return uri.host.isEmpty ? path : '${uri.host}$path';
}

double _round(double value) => (value * 100).roundToDouble() / 100;

String? _screenOrientationType() {
  try {
    return web.window.screen.orientation.type;
  } catch (_) {
    return null;
  }
}

int? _screenOrientationAngle() {
  try {
    return web.window.screen.orientation.angle;
  } catch (_) {
    return null;
  }
}
