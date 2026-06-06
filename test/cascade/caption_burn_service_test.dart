import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naiweaver/features/tools/cascade/services/caption_burn_service.dart';

/// Encodes a solid-color [w]x[h] PNG for use as a fake beat preview.
Uint8List _solidPng(int w, int h, int r, int g, int b) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(r, g, b, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  // compute() needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CaptionBurnService.burnFrame', () {
    test('returns the original bytes when the caption is blank', () async {
      final png = _solidPng(64, 64, 255, 0, 0);
      final out = await CaptionBurnService.burnFrame(
        CaptionFrame(imageBytes: png, caption: '   '),
      );
      expect(out, same(png));
    });
  });

  group('CaptionBurnService.buildStoryboardStrip', () {
    test('vertical strip sums heights and matches the narrowest width', () async {
      final frames = [
        CaptionFrame(imageBytes: _solidPng(100, 50, 255, 0, 0)),
        CaptionFrame(imageBytes: _solidPng(80, 40, 0, 255, 0)),
      ];

      final result = await CaptionBurnService.buildStoryboardStrip(
        frames,
        layout: StoryboardLayout.vertical,
        gap: 10,
      );

      final strip = img.decodePng(result.bytes)!;
      // Width = narrowest frame (80). The taller frame is resized to width 80,
      // so its height scales 50 -> 40. Total height = 40 + 40 + gap(10) = 90.
      expect(strip.width, 80);
      expect(strip.height, 90);
      // Well under the long-axis cap, so no downscaling.
      expect(result.downscaled, isFalse);
    });

    test('horizontal strip sums widths and matches the shortest height', () async {
      final frames = [
        CaptionFrame(imageBytes: _solidPng(50, 100, 255, 0, 0)),
        CaptionFrame(imageBytes: _solidPng(40, 80, 0, 0, 255)),
      ];

      final result = await CaptionBurnService.buildStoryboardStrip(
        frames,
        layout: StoryboardLayout.horizontal,
        gap: 10,
      );

      final strip = img.decodePng(result.bytes)!;
      // Height = shortest frame (80). The taller frame is resized to height 80,
      // so its width scales 50 -> 40. Total width = 40 + 40 + gap(10) = 90.
      expect(strip.height, 80);
      expect(strip.width, 90);
      expect(result.downscaled, isFalse);
    });

    test('throws when no frames are provided', () async {
      expect(
        () => CaptionBurnService.buildStoryboardStrip(const []),
        throwsArgumentError,
      );
    });

    test('downscales and flags when the strip would exceed the long-axis cap', () async {
      // Many tall frames whose summed height blows past maxLongAxis (8000px),
      // forcing a proportional downscale of the common width.
      final frames = List.generate(
        12,
        (i) => CaptionFrame(imageBytes: _solidPng(832, 1216, i * 10, 0, 0)),
      );

      final result = await CaptionBurnService.buildStoryboardStrip(
        frames,
        layout: StoryboardLayout.vertical,
        gap: 12,
      );

      final strip = img.decodePng(result.bytes)!;
      expect(result.downscaled, isTrue);
      // The long axis is held under the cap so the isolate encode stays bounded.
      expect(strip.height, lessThanOrEqualTo(CaptionBurnService.maxLongAxis));
      // Width is shrunk below the original 832 to make that fit.
      expect(strip.width, lessThan(832));
    });
  });
}
