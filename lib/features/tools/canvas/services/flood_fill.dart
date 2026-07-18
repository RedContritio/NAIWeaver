import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

/// Result of a flood fill: a per-pixel mask (1 = inside the region) plus the
/// bounding box of the region.
class FloodFillResult {
  final Uint8List mask;
  final int width;
  final int height;
  final int minX, minY, maxX, maxY;
  final int pixelCount;

  const FloodFillResult({
    required this.mask,
    required this.width,
    required this.height,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.pixelCount,
  });

  bool get isEmpty => pixelCount == 0;

  static FloodFillResult empty(int width, int height) => FloodFillResult(
        mask: Uint8List(width * height),
        width: width,
        height: height,
        minX: 0,
        minY: 0,
        maxX: -1,
        maxY: -1,
        pixelCount: 0,
      );
}

/// Scanline flood fill over raw RGBA bytes (4 bytes per pixel, row-major).
///
/// A pixel joins the region when every channel (alpha included) differs from
/// the seed pixel's channel by at most [tolerance]. Connectivity is
/// 4-directional, so regions do not leak across diagonal-only touches.
FloodFillResult floodFillMask({
  required Uint8List rgba,
  required int width,
  required int height,
  required int seedX,
  required int seedY,
  int tolerance = 32,
}) {
  if (width <= 0 ||
      height <= 0 ||
      rgba.length < width * height * 4 ||
      seedX < 0 ||
      seedY < 0 ||
      seedX >= width ||
      seedY >= height) {
    return FloodFillResult.empty(width <= 0 ? 0 : width, height <= 0 ? 0 : height);
  }

  final seedIdx = (seedY * width + seedX) * 4;
  final sr = rgba[seedIdx];
  final sg = rgba[seedIdx + 1];
  final sb = rgba[seedIdx + 2];
  final sa = rgba[seedIdx + 3];

  bool matches(int x, int y) {
    final i = (y * width + x) * 4;
    return (rgba[i] - sr).abs() <= tolerance &&
        (rgba[i + 1] - sg).abs() <= tolerance &&
        (rgba[i + 2] - sb).abs() <= tolerance &&
        (rgba[i + 3] - sa).abs() <= tolerance;
  }

  final mask = Uint8List(width * height);
  var minX = seedX, maxX = seedX, minY = seedY, maxY = seedY;
  var pixelCount = 0;

  // Scanline fill: each stack entry is a span seed (x, y); the span is
  // expanded left/right, then matching runs on the rows above and below are
  // pushed once per run.
  final stack = <int>[seedX, seedY];
  while (stack.isNotEmpty) {
    final y = stack.removeLast();
    final x = stack.removeLast();
    if (mask[y * width + x] != 0 || !matches(x, y)) continue;

    var x1 = x;
    while (x1 > 0 && mask[y * width + x1 - 1] == 0 && matches(x1 - 1, y)) {
      x1--;
    }
    var x2 = x;
    while (x2 < width - 1 &&
        mask[y * width + x2 + 1] == 0 &&
        matches(x2 + 1, y)) {
      x2++;
    }

    for (var i = x1; i <= x2; i++) {
      mask[y * width + i] = 1;
    }
    pixelCount += x2 - x1 + 1;
    if (x1 < minX) minX = x1;
    if (x2 > maxX) maxX = x2;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;

    for (final ny in [y - 1, y + 1]) {
      if (ny < 0 || ny >= height) continue;
      var inRun = false;
      for (var i = x1; i <= x2; i++) {
        final open = mask[ny * width + i] == 0 && matches(i, ny);
        if (open && !inRun) {
          stack..add(i)..add(ny);
          inRun = true;
        } else if (!open) {
          inRun = false;
        }
      }
    }
  }

  return FloodFillResult(
    mask: mask,
    width: width,
    height: height,
    minX: minX,
    minY: minY,
    maxX: maxX,
    maxY: maxY,
    pixelCount: pixelCount,
  );
}

/// Parameters for [computeFillRegionPng], transferable to an isolate.
class FillRegionParams {
  final Uint8List flattenedPng;
  final Offset normalizedSeed;
  final int colorValue; // ARGB fill color; opacity is applied at render time
  final int tolerance;

  FillRegionParams({
    required this.flattenedPng,
    required this.normalizedSeed,
    required this.colorValue,
    this.tolerance = 32,
  });
}

/// Isolate entry point: decodes the flattened composite, flood-fills from the
/// seed, and returns the region as a PNG at source resolution — fill color at
/// full alpha inside the region, transparent elsewhere. Returns null when the
/// image cannot be decoded or the fill matched nothing.
Uint8List? computeFillRegionPng(FillRegionParams p) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(p.flattenedPng);
  } catch (_) {
    // The format probe can throw on malformed bytes instead of returning null.
    return null;
  }
  if (decoded == null) return null;
  final width = decoded.width;
  final height = decoded.height;

  final rgbaImage = decoded.numChannels == 4
      ? decoded
      : decoded.convert(numChannels: 4);
  final rgba = rgbaImage.getBytes(order: img.ChannelOrder.rgba);

  final seedX =
      (p.normalizedSeed.dx * (width - 1)).round().clamp(0, width - 1);
  final seedY =
      (p.normalizedSeed.dy * (height - 1)).round().clamp(0, height - 1);

  final result = floodFillMask(
    rgba: Uint8List.fromList(rgba),
    width: width,
    height: height,
    seedX: seedX,
    seedY: seedY,
    tolerance: p.tolerance,
  );
  if (result.isEmpty) return null;

  final r = (p.colorValue >> 16) & 0xFF;
  final g = (p.colorValue >> 8) & 0xFF;
  final b = p.colorValue & 0xFF;

  final region = img.Image(width: width, height: height, numChannels: 4);
  for (var y = result.minY; y <= result.maxY; y++) {
    for (var x = result.minX; x <= result.maxX; x++) {
      if (result.mask[y * width + x] != 0) {
        region.setPixelRgba(x, y, r, g, b, 255);
      }
    }
  }
  return Uint8List.fromList(img.encodePng(region));
}
