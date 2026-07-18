import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/utils/canvas_zoom_math.dart';

void main() {
  const viewport = Size(800, 600);

  Offset sceneUnder(ZoomState s, Offset viewportPoint) =>
      s.toScene(viewportPoint);

  group('zoomAtPoint', () {
    test('zoom in anchors the scene point under the cursor', () {
      const focal = Offset(200, 150);
      const before = ZoomState.identity;
      final sceneBefore = sceneUnder(before, focal);

      final after = zoomAtPoint(before, focal, 2.0, viewport);

      expect(after.scale, 2.0);
      final sceneAfter = sceneUnder(after, focal);
      expect(sceneAfter.dx, closeTo(sceneBefore.dx, 1e-9));
      expect(sceneAfter.dy, closeTo(sceneBefore.dy, 1e-9));
    });

    test('anchor holds when already zoomed and panned (bug #17/#18 regression)',
        () {
      // The old implementation post-multiplied the current matrix with a
      // viewport-space focal point, which only anchored correctly at
      // identity. This state reproduces the drift.
      const before = ZoomState(scale: 3.0, tx: -400, ty: -300);
      const focal = Offset(500, 400);
      final sceneBefore = sceneUnder(before, focal);

      final after = zoomAtPoint(before, focal, 1.5, viewport);

      expect(after.scale, closeTo(4.5, 1e-9));
      final sceneAfter = sceneUnder(after, focal);
      expect(sceneAfter.dx, closeTo(sceneBefore.dx, 1e-9));
      expect(sceneAfter.dy, closeTo(sceneBefore.dy, 1e-9));
    });

    test('scale clamps to the maximum', () {
      const before = ZoomState(scale: 12.0, tx: -100, ty: -100);
      final after = zoomAtPoint(before, const Offset(400, 300), 4.0, viewport);
      expect(after.scale, kCanvasMaxScale);
    });

    test('scale clamps to fit and recenters, regardless of cursor position',
        () {
      // Zooming out repeatedly from a deep zoom in a corner must land on the
      // centered fit view — this is the "getting lost off-canvas" bug (#18).
      var state = const ZoomState(scale: 8.0, tx: -5000, ty: -4000);
      const focal = Offset(790, 10); // corner, worst case for drift
      for (var i = 0; i < 60; i++) {
        state = zoomAtPoint(state, focal, 1 / 1.1, viewport);
      }
      expect(state.scale, kCanvasMinScale);
      expect(state.tx, closeTo(0, 1e-9));
      expect(state.ty, closeTo(0, 1e-9));
    });

    test('translation stays clamped so content always covers the viewport',
        () {
      // Zoom in at the top-left corner: content may not detach from any edge.
      var state = ZoomState.identity;
      for (var i = 0; i < 20; i++) {
        state = zoomAtPoint(state, const Offset(0, 0), 1.1, viewport);
      }
      expect(state.tx, lessThanOrEqualTo(0));
      expect(state.ty, lessThanOrEqualTo(0));
      expect(state.tx, greaterThanOrEqualTo(viewport.width * (1 - state.scale)));
      expect(state.ty,
          greaterThanOrEqualTo(viewport.height * (1 - state.scale)));
    });

    test('zoom in then out with inverse factors returns to the start', () {
      const start = ZoomState(scale: 2.0, tx: -200, ty: -150);
      const focal = Offset(321, 234);
      final zoomed = zoomAtPoint(start, focal, 1.1, viewport);
      final back = zoomAtPoint(zoomed, focal, 1 / 1.1, viewport);
      expect(back.scale, closeTo(start.scale, 1e-9));
      expect(back.tx, closeTo(start.tx, 1e-6));
      expect(back.ty, closeTo(start.ty, 1e-6));
    });

    test('empty viewport is a no-op', () {
      const before = ZoomState(scale: 2.0, tx: -10, ty: -20);
      final after = zoomAtPoint(before, Offset.zero, 2.0, Size.zero);
      expect(after, same(before));
    });
  });

  group('clampToViewport', () {
    test('centers content at fit scale', () {
      const state = ZoomState(scale: 1.0, tx: -300, ty: 200);
      final clamped = clampToViewport(state, viewport);
      expect(clamped.tx, 0);
      expect(clamped.ty, 0);
    });

    test('clamps a runaway pan back into bounds when zoomed', () {
      const state = ZoomState(scale: 2.0, tx: 500, ty: -99999);
      final clamped = clampToViewport(state, viewport);
      expect(clamped.tx, 0); // can't reveal space left of the content
      expect(clamped.ty, viewport.height * (1 - 2.0));
    });
  });

  group('ZoomState matrix conversion', () {
    test('round-trips through Matrix4', () {
      const state = ZoomState(scale: 3.5, tx: -123.5, ty: 67.25);
      final restored = ZoomState.fromMatrix(state.toMatrix());
      expect(restored.scale, state.scale);
      expect(restored.tx, state.tx);
      expect(restored.ty, state.ty);
    });

    test('toMatrix is the inverse of toScene', () {
      const state = ZoomState(scale: 2.0, tx: -100, ty: -50);
      const scene = Offset(200, 125);
      final m = state.toMatrix();
      final viewportPoint = Offset(
        m.storage[0] * scene.dx + m.storage[12],
        m.storage[5] * scene.dy + m.storage[13],
      );
      final roundTripped = state.toScene(viewportPoint);
      expect(roundTripped.dx, closeTo(scene.dx, 1e-9));
      expect(roundTripped.dy, closeTo(scene.dy, 1e-9));
    });
  });
}
