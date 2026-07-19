import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import '../models/canvas_selection.dart';

/// Pure geometry for consuming a [CanvasSelection]: applies the marquee's
/// live transform (offset / scale / rotation) to its outline, and rasterizes
/// the resulting polygon into a per-pixel mask.
///
/// Both the selection overlay painter and the stroke renderers derive the
/// region from [selectionToPolygon], so the marquee the user sees is exactly
/// the region that delete/clip operations act on.

/// The selection outline — lasso path, or the rect's four corners — with
/// offset, scale, and rotation applied, in normalized 0-1 coordinates.
///
/// Rotation is performed in aspect-corrected space ([aspect] = source
/// width / height) so a rotated marquee is a true rotation in pixels;
/// normalized space is anisotropic on non-square images and rotating there
/// would shear the region.
List<Offset> selectionToPolygon(
  CanvasSelection selection, {
  required double aspect,
}) {
  final rect = selection.normalizedRect;
  final base = selection.clipPath ??
      [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];

  // Scale around the original center, then offset — this maps the rect's
  // corners exactly onto transformedRect.
  final center = rect.center;
  final offset = Offset(selection.offsetX, selection.offsetY);
  final placed = base
      .map((p) => center + (p - center) * selection.scale + offset)
      .toList();
  if (selection.rotation == 0.0) return placed;

  final pivot = center + offset;
  final cosR = math.cos(selection.rotation);
  final sinR = math.sin(selection.rotation);
  return placed.map((p) {
    final u = (p.dx - pivot.dx) * aspect;
    final v = p.dy - pivot.dy;
    return Offset(
      pivot.dx + (u * cosR - v * sinR) / aspect,
      pivot.dy + (u * sinR + v * cosR),
    );
  }).toList();
}

/// Rasterizes a normalized polygon into a width×height mask (1 = inside),
/// using scanline even-odd filling over pixel centers — concave and
/// self-intersecting lasso paths behave like they do in every paint program.
/// Fewer than 3 points yields an empty mask.
Uint8List rasterizePolygonMask(List<Offset> polygon, int width, int height) {
  if (width <= 0 || height <= 0) return Uint8List(0);
  final mask = Uint8List(width * height);
  if (polygon.length < 3) return mask;

  final n = polygon.length;
  final xs = List<double>.generate(n, (i) => polygon[i].dx * width);
  final ys = List<double>.generate(n, (i) => polygon[i].dy * height);

  final hits = <double>[];
  for (var y = 0; y < height; y++) {
    final cy = y + 0.5;
    hits.clear();
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final y1 = ys[i], y2 = ys[j];
      // Half-open interval so a vertex shared by two edges counts once.
      if ((y1 <= cy && y2 > cy) || (y2 <= cy && y1 > cy)) {
        final t = (cy - y1) / (y2 - y1);
        hits.add(xs[i] + t * (xs[j] - xs[i]));
      }
    }
    if (hits.length < 2) continue;
    hits.sort();
    for (var k = 0; k + 1 < hits.length; k += 2) {
      // Pixel x is inside when its center x+0.5 lies within [lo, hi).
      final x1 = math.max((hits[k] - 0.5).ceil(), 0);
      final x2 = math.min((hits[k + 1] - 0.5).ceil() - 1, width - 1);
      for (var x = x1; x <= x2; x++) {
        mask[y * width + x] = 1;
      }
    }
  }
  return mask;
}
