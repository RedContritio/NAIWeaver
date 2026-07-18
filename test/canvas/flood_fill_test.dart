import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naiweaver/features/tools/canvas/services/flood_fill.dart';

/// Builds RGBA bytes from an ASCII grid; each character maps to an RGBA color.
Uint8List gridRgba(List<String> rows, Map<String, List<int>> palette) {
  final height = rows.length;
  final width = rows.first.length;
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final color = palette[rows[y][x]]!;
      final i = (y * width + x) * 4;
      bytes[i] = color[0];
      bytes[i + 1] = color[1];
      bytes[i + 2] = color[2];
      bytes[i + 3] = color.length > 3 ? color[3] : 255;
    }
  }
  return bytes;
}

String maskToAscii(FloodFillResult r) {
  final sb = StringBuffer();
  for (var y = 0; y < r.height; y++) {
    for (var x = 0; x < r.width; x++) {
      sb.write(r.mask[y * r.width + x] == 1 ? '#' : '.');
    }
    if (y < r.height - 1) sb.write('\n');
  }
  return sb.toString();
}

void main() {
  const palette = {
    'w': [255, 255, 255],
    'k': [0, 0, 0],
    'r': [255, 0, 0],
  };

  group('floodFillMask', () {
    test('fills only the contiguous region around the seed', () {
      final rgba = gridRgba([
        'wwkww',
        'wwkww',
        'kkkww',
        'wwwww',
      ], palette);
      final r = floodFillMask(
          rgba: rgba, width: 5, height: 4, seedX: 0, seedY: 0, tolerance: 0);
      expect(maskToAscii(r), [
        '##...',
        '##...',
        '.....',
        '.....',
      ].join('\n'));
      expect(r.pixelCount, 4);
      expect([r.minX, r.minY, r.maxX, r.maxY], [0, 0, 1, 1]);
    });

    test('regions connected around a wall are filled together', () {
      final rgba = gridRgba([
        'wwkww',
        'wwkww',
        'wwkww',
        'wwwww',
      ], palette);
      final r = floodFillMask(
          rgba: rgba, width: 5, height: 4, seedX: 0, seedY: 0, tolerance: 0);
      // Left and right sides connect along the bottom row.
      expect(r.pixelCount, 17);
      expect(maskToAscii(r), [
        '##.##',
        '##.##',
        '##.##',
        '#####',
      ].join('\n'));
    });

    test('seeding on the wall fills the wall itself', () {
      final rgba = gridRgba([
        'wwkww',
        'wwkww',
        'wwkww',
        'wwkww',
      ], palette);
      final r = floodFillMask(
          rgba: rgba, width: 5, height: 4, seedX: 2, seedY: 1, tolerance: 0);
      expect(r.pixelCount, 4);
      expect([r.minX, r.maxX], [2, 2]);
    });

    test('diagonal touches do not connect (4-connectivity)', () {
      final rgba = gridRgba([
        'wk',
        'kw',
      ], palette);
      final r = floodFillMask(
          rgba: rgba, width: 2, height: 2, seedX: 0, seedY: 0, tolerance: 0);
      expect(r.pixelCount, 1);
      expect(maskToAscii(r), '#.\n..');
    });

    test('tolerance merges similar colors', () {
      final rgba = gridRgba([
        'wgw',
      ], {
        'w': [255, 255, 255],
        'g': [235, 235, 235],
      });
      final strict = floodFillMask(
          rgba: rgba, width: 3, height: 1, seedX: 0, seedY: 0, tolerance: 0);
      expect(strict.pixelCount, 1);
      final loose = floodFillMask(
          rgba: rgba, width: 3, height: 1, seedX: 0, seedY: 0, tolerance: 32);
      expect(loose.pixelCount, 3);
    });

    test('uniform image fills everything', () {
      final rgba = gridRgba(List.filled(6, 'wwwwww'), palette);
      final r = floodFillMask(
          rgba: rgba, width: 6, height: 6, seedX: 3, seedY: 3, tolerance: 0);
      expect(r.pixelCount, 36);
      expect([r.minX, r.minY, r.maxX, r.maxY], [0, 0, 5, 5]);
    });

    test('out-of-bounds seed returns empty', () {
      final rgba = gridRgba(['ww'], palette);
      final r = floodFillMask(
          rgba: rgba, width: 2, height: 1, seedX: 5, seedY: 0);
      expect(r.isEmpty, isTrue);
    });

    test('alpha differences act as boundaries', () {
      final rgba = gridRgba([
        'wta',
      ], {
        'w': [255, 255, 255, 255],
        't': [255, 255, 255, 128],
        'a': [255, 255, 255, 255],
      });
      final r = floodFillMask(
          rgba: rgba, width: 3, height: 1, seedX: 0, seedY: 0, tolerance: 32);
      expect(r.pixelCount, 1);
    });
  });

  group('computeFillRegionPng', () {
    test('produces a fill-colored region PNG for the seeded area only', () {
      // 4x2 composite: left half white, right half black.
      final src = img.Image(width: 4, height: 2);
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 4; x++) {
          final v = x < 2 ? 255 : 0;
          src.setPixelRgba(x, y, v, v, v, 255);
        }
      }
      final regionBytes = computeFillRegionPng(FillRegionParams(
        flattenedPng: Uint8List.fromList(img.encodePng(src)),
        normalizedSeed: const Offset(0, 0),
        colorValue: 0xFFFF0000,
      ));
      expect(regionBytes, isNotNull);
      final region = img.decodePng(regionBytes!)!;
      expect(region.width, 4);
      expect(region.height, 2);
      // Seeded (white) half is filled with the color at full alpha…
      final filled = region.getPixel(1, 1);
      expect(filled.a.toInt(), 255);
      expect(filled.r.toInt(), 255);
      expect(filled.g.toInt(), 0);
      expect(filled.b.toInt(), 0);
      // …and the black half is untouched (transparent).
      expect(region.getPixel(2, 0).a.toInt(), 0);
      expect(region.getPixel(3, 1).a.toInt(), 0);
    });

    test('returns null for undecodable bytes', () {
      expect(
        computeFillRegionPng(FillRegionParams(
          flattenedPng: Uint8List.fromList([1, 2, 3]),
          normalizedSeed: const Offset(0.5, 0.5),
          colorValue: 0xFF00FF00,
        )),
        isNull,
      );
    });
  });
}
