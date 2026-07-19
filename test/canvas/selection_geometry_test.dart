import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/tools/canvas/models/canvas_selection.dart';
import 'package:naiweaver/features/tools/canvas/services/selection_geometry.dart';

void main() {
  group('selectionToPolygon', () {
    test('untransformed rect yields its four corners', () {
      const sel = CanvasSelection(
        normalizedRect: Rect.fromLTRB(0.2, 0.3, 0.6, 0.7),
      );
      final poly = selectionToPolygon(sel, aspect: 1.0);
      expect(poly, const [
        Offset(0.2, 0.3),
        Offset(0.6, 0.3),
        Offset(0.6, 0.7),
        Offset(0.2, 0.7),
      ]);
    });

    test('offset shifts every corner', () {
      const sel = CanvasSelection(
        normalizedRect: Rect.fromLTRB(0.2, 0.3, 0.6, 0.7),
        offsetX: 0.1,
        offsetY: -0.2,
      );
      final poly = selectionToPolygon(sel, aspect: 1.0);
      expect(poly.first.dx, closeTo(0.3, 1e-12));
      expect(poly.first.dy, closeTo(0.1, 1e-12));
      expect(poly[2].dx, closeTo(0.7, 1e-12));
      expect(poly[2].dy, closeTo(0.5, 1e-12));
    });

    test('scale grows around the rect center', () {
      const sel = CanvasSelection(
        normalizedRect: Rect.fromLTRB(0.4, 0.4, 0.6, 0.6),
        scale: 2.0,
      );
      final poly = selectionToPolygon(sel, aspect: 1.0);
      // Center (0.5, 0.5) stays put; half-extent doubles from 0.1 to 0.2.
      expect(poly.first.dx, closeTo(0.3, 1e-12));
      expect(poly.first.dy, closeTo(0.3, 1e-12));
      expect(poly[2].dx, closeTo(0.7, 1e-12));
      expect(poly[2].dy, closeTo(0.7, 1e-12));
    });

    test('polygon corners land exactly on transformedRect (no rotation)', () {
      const sel = CanvasSelection(
        normalizedRect: Rect.fromLTRB(0.1, 0.2, 0.5, 0.4),
        offsetX: 0.05,
        offsetY: 0.1,
        scale: 1.5,
      );
      final poly = selectionToPolygon(sel, aspect: 1.0);
      final r = sel.transformedRect;
      expect(poly[0].dx, closeTo(r.left, 1e-12));
      expect(poly[0].dy, closeTo(r.top, 1e-12));
      expect(poly[2].dx, closeTo(r.right, 1e-12));
      expect(poly[2].dy, closeTo(r.bottom, 1e-12));
    });

    test('90-degree rotation on a square image cycles the corners', () {
      const sel = CanvasSelection(
        normalizedRect: Rect.fromLTRB(0.25, 0.25, 0.75, 0.75),
        rotation: 1.5707963267948966, // pi / 2
      );
      final poly = selectionToPolygon(sel, aspect: 1.0);
      // Top-left rotates onto the top-right corner position.
      expect(poly[0].dx, closeTo(0.75, 1e-9));
      expect(poly[0].dy, closeTo(0.25, 1e-9));
      expect(poly[1].dx, closeTo(0.75, 1e-9));
      expect(poly[1].dy, closeTo(0.75, 1e-9));
    });

    test('rotation is a true rotation in pixel space on non-square images',
        () {
      // 2:1 image; a 0.2x0.2 normalized rect is 0.4x0.2 in aspect units.
      // After 90 degrees the pixel-space extents swap: normalized width
      // becomes 0.1 and height becomes 0.4.
      const sel = CanvasSelection(
        normalizedRect: Rect.fromLTRB(0.4, 0.4, 0.6, 0.6),
        rotation: 1.5707963267948966,
      );
      final poly = selectionToPolygon(sel, aspect: 2.0);
      final minX = poly.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
      final maxX = poly.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
      final minY = poly.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
      final maxY = poly.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
      expect(maxX - minX, closeTo(0.1, 1e-9));
      expect(maxY - minY, closeTo(0.4, 1e-9));
    });

    test('lasso clipPath is used verbatim and transformed', () {
      const path = [Offset(0.1, 0.1), Offset(0.3, 0.1), Offset(0.2, 0.3)];
      const sel = CanvasSelection(
        normalizedRect: Rect.fromLTRB(0.1, 0.1, 0.3, 0.3),
        clipPath: path,
        offsetX: 0.5,
      );
      final poly = selectionToPolygon(sel, aspect: 1.0);
      expect(poly.length, 3);
      expect(poly[0].dx, closeTo(0.6, 1e-12));
      expect(poly[0].dy, closeTo(0.1, 1e-12));
      expect(poly[2].dx, closeTo(0.7, 1e-12));
      expect(poly[2].dy, closeTo(0.3, 1e-12));
    });
  });

  group('rasterizePolygonMask', () {
    int countSet(List<int> mask) => mask.where((v) => v != 0).length;

    test('full-canvas square sets every pixel', () {
      const poly = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
      final mask = rasterizePolygonMask(poly, 8, 8);
      expect(countSet(mask), 64);
    });

    test('left-half rect fills exactly the left columns', () {
      const poly = [
        Offset(0, 0),
        Offset(0.5, 0),
        Offset(0.5, 1),
        Offset(0, 1),
      ];
      final mask = rasterizePolygonMask(poly, 8, 8);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          expect(mask[y * 8 + x], x < 4 ? 1 : 0,
              reason: 'pixel ($x,$y)');
        }
      }
    });

    test('concave polygon leaves the notch empty (even-odd)', () {
      // A "U": full square with a notch cut from the top middle down to 0.5.
      const poly = [
        Offset(0, 0),
        Offset(0.4, 0),
        Offset(0.4, 0.5),
        Offset(0.6, 0.5),
        Offset(0.6, 0),
        Offset(1, 0),
        Offset(1, 1),
        Offset(0, 1),
      ];
      final mask = rasterizePolygonMask(poly, 10, 10);
      expect(mask[2 * 10 + 5], 0); // inside the notch
      expect(mask[2 * 10 + 1], 1); // left arm
      expect(mask[2 * 10 + 8], 1); // right arm
      expect(mask[8 * 10 + 5], 1); // base below the notch
    });

    test('fewer than 3 points yields an empty mask', () {
      const poly = [Offset(0.1, 0.1), Offset(0.9, 0.9)];
      final mask = rasterizePolygonMask(poly, 8, 8);
      expect(countSet(mask), 0);
    });

    test('polygon partly outside the canvas clamps safely', () {
      const poly = [
        Offset(-0.5, -0.5),
        Offset(0.25, -0.5),
        Offset(0.25, 0.25),
        Offset(-0.5, 0.25),
      ];
      final mask = rasterizePolygonMask(poly, 8, 8);
      // Only the on-canvas quadrant of the polygon is set: x,y in [0,2).
      expect(countSet(mask), 4);
      expect(mask[0], 1);
      expect(mask[1 * 8 + 1], 1);
      expect(mask[2 * 8 + 2], 0);
    });

    test('polygon entirely outside the canvas sets nothing', () {
      const poly = [
        Offset(-0.9, 0.2),
        Offset(-0.1, 0.2),
        Offset(-0.1, 0.8),
        Offset(-0.9, 0.8),
      ];
      final mask = rasterizePolygonMask(poly, 8, 8);
      expect(countSet(mask), 0);
    });

    test('zero-size canvas returns an empty buffer', () {
      const poly = [Offset(0, 0), Offset(1, 0), Offset(1, 1)];
      expect(rasterizePolygonMask(poly, 0, 8), isEmpty);
      expect(rasterizePolygonMask(poly, 8, 0), isEmpty);
    });
  });
}
