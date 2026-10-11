// Shared setup for widget tests of DOM-backed widgets. Import only from
// tests annotated `@TestOn('browser')`.
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// [testWidgets] for trees containing platform views.
///
/// The Web test runner makes the engine drop every platform message,
/// including `flutter/platform_views`, so an `HtmlElementView` would never
/// get its element. Message handling is switched on for the test body only:
/// the engine answers through zero-length timers, and replies to the messages
/// the binding sends while tearing the test down would otherwise be left
/// pending. The tree is unmounted, its `dispose` reply flushed, and the
/// flutter_tester environment restored before the test ends.
void testPlatformViewWidgets(
  String description,
  WidgetTesterCallback callback,
) {
  testWidgets(description, (tester) async {
    ui_web.TestEnvironment.setUp(
      const ui_web.TestEnvironment(
        forceTestFonts: true,
        disableFontFallbacks: true,
        keepSemanticsDisabledOnUpdate: true,
        defaultToTestUrlStrategy: true,
      ),
    );
    try {
      await callback(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    } finally {
      ui_web.TestEnvironment.setUp(
        const ui_web.TestEnvironment.flutterTester(),
      );
    }
  });
}

/// Waits for the [index]th platform view to be created (an async platform
/// message) and returns its DOM element. Widget tests never composite, so the
/// element is not attached to the document.
Future<T> platformViewElement<T extends Object>(
  WidgetTester tester, {
  int index = 0,
}) async {
  final surfaces = find.byType(PlatformViewSurface);
  for (var attempt = 0; attempt < 20; attempt++) {
    if (surfaces.evaluate().length > index) break;
    await settleBrowser(tester);
  }
  final surface = tester.widget<PlatformViewSurface>(surfaces.at(index));
  return ui_web.platformViewRegistry.getViewById(surface.controller.viewId)
      as T;
}

/// Lets real browser work (promise reactions, observers, timers) run, then
/// flushes what it scheduled in the fake-async zone. Engine replies to
/// platform messages arrive through zero-length timers, hence the
/// `Duration.zero` pump rather than a plain `pump()`.
Future<void> settleBrowser(
  WidgetTester tester, {
  Duration wait = const Duration(milliseconds: 10),
}) async {
  await tester.runAsync(() => Future<void>.delayed(wait));
  await tester.pump(Duration.zero);
}
