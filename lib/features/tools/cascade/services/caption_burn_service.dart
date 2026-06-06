import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// Direction a storyboard strip is laid out in.
enum StoryboardLayout { vertical, horizontal }

/// A single beat to burn: its rendered image bytes plus an optional caption.
class CaptionFrame {
  final Uint8List imageBytes;
  final String caption;

  const CaptionFrame({required this.imageBytes, this.caption = ''});
}

/// Result of assembling a storyboard strip: the PNG bytes plus whether the
/// frames had to be downscaled to keep the strip under the memory cap (so the
/// caller can surface a "shrunk to fit" notice instead of silently degrading).
class StoryboardResult {
  final Uint8List bytes;
  final bool downscaled;

  const StoryboardResult({required this.bytes, required this.downscaled});
}

/// Burns narration captions onto cascade beat images and assembles storyboard
/// strips, mirroring [CanvasFlattenService]: the caption (scrim gradient + text)
/// is rendered to a transparent PNG with `dart:ui` on the UI thread (text layout
/// needs the engine), then composited onto the image with `package:image` inside
/// a `compute()` isolate.
///
/// All outputs are PNG bytes. Nothing here mutates the inputs — burn-in is an
/// explicit export, leaving the saved cascade and in-app previews untouched.
class CaptionBurnService {
  CaptionBurnService._();

  /// Burns [frame]'s caption onto its image and returns the composited PNG.
  /// If the caption is blank the original bytes are returned unchanged.
  static Future<Uint8List> burnFrame(CaptionFrame frame) async {
    if (frame.caption.trim().isEmpty) return frame.imageBytes;

    final dims = await _decodeDimensions(frame.imageBytes);
    if (dims == null) return frame.imageBytes;

    final captionPng = await _renderCaptionPng(
      frame.caption,
      dims.width,
      dims.height,
    );
    if (captionPng == null) return frame.imageBytes;

    return compute(_compositeCaption, _CompositePayload(
      imageBytes: frame.imageBytes,
      captionPng: captionPng,
    ));
  }

  /// Hard cap on the strip's long axis in pixels. A 12-beat 832×1216 vertical
  /// strip would otherwise be ~832×14,700 (~49 MP, ~196 MB RGBA in the isolate)
  /// and OOM-kill the encode on low-RAM devices. We downscale the common
  /// cross-axis so the long axis stays under this, and report that we did.
  static const int maxLongAxis = 8000;

  /// Burns captions onto every frame, then stacks them into a single storyboard
  /// strip image. Frames are normalized to a common cross-axis size so they line
  /// up, downscaled if needed to keep the strip under [maxLongAxis]. Returns the
  /// assembled PNG plus whether downscaling occurred.
  static Future<StoryboardResult> buildStoryboardStrip(
    List<CaptionFrame> frames, {
    StoryboardLayout layout = StoryboardLayout.vertical,
    int gap = 12,
  }) async {
    final burned = <Uint8List>[];
    for (final frame in frames) {
      burned.add(await burnFrame(frame));
    }
    if (burned.isEmpty) {
      throw ArgumentError('No frames to assemble into a storyboard.');
    }
    return compute(_assembleStrip, _StripPayload(
      frames: burned,
      vertical: layout == StoryboardLayout.vertical,
      gap: gap,
      maxLongAxis: maxLongAxis,
    ));
  }

  static Future<({int width, int height})?> _decodeDimensions(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      return (width: w, height: h);
    } catch (e) {
      debugPrint('CaptionBurnService._decodeDimensions: $e');
      return null;
    }
  }

  /// Renders the scrim gradient + caption text into a transparent PNG sized to
  /// the target image. Runs on the UI thread (text layout requires the engine).
  static Future<Uint8List?> _renderCaptionPng(String text, int width, int height) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final w = width.toDouble();
      final h = height.toDouble();

      // Scale typography to the image so captions read the same regardless of
      // resolution. Roughly 3.2% of height, clamped to a sane range.
      final fontSize = (height * 0.032).clamp(18.0, 64.0);
      final hPad = w * 0.035;
      final vPad = h * 0.025;

      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        maxLines: 3,
        ellipsis: '…',
      ))
        ..pushStyle(ui.TextStyle(
          color: const Color(0xFFFFFFFF),
          height: 1.3,
          shadows: const [
            Shadow(color: Color(0xFF000000), blurRadius: 6, offset: Offset(0, 2)),
            Shadow(color: Color(0xCC000000), blurRadius: 12),
          ],
        ))
        ..addText(text.trim());
      final paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: w - hPad * 2));

      // Scrim band: tall enough to cover the text plus padding, gradient from
      // transparent (top) to black@~65% (bottom).
      final bandHeight = paragraph.height + vPad * 2;
      final bandTop = h - bandHeight;
      final scrimRect = Rect.fromLTWH(0, bandTop, w, bandHeight);
      final scrimPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xA6000000)],
        ).createShader(scrimRect);
      canvas.drawRect(scrimRect, scrimPaint);

      canvas.drawParagraph(paragraph, Offset(hPad, h - vPad - paragraph.height));

      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('CaptionBurnService._renderCaptionPng: $e');
      return null;
    }
  }
}

class _CompositePayload {
  final Uint8List imageBytes;
  final Uint8List captionPng;
  _CompositePayload({required this.imageBytes, required this.captionPng});
}

Uint8List _compositeCaption(_CompositePayload payload) {
  final base = img.decodeImage(payload.imageBytes);
  if (base == null) return payload.imageBytes;
  final caption = img.decodePng(payload.captionPng);
  if (caption == null) return payload.imageBytes;

  final result = img.Image.from(base);
  // Caption PNG is rendered at the base image's pixel size, so it aligns 1:1.
  img.compositeImage(result, caption);
  return Uint8List.fromList(img.encodePng(result));
}

class _StripPayload {
  final List<Uint8List> frames;
  final bool vertical;
  final int gap;
  final int maxLongAxis;
  _StripPayload({
    required this.frames,
    required this.vertical,
    required this.gap,
    required this.maxLongAxis,
  });
}

/// Draws a beat-number badge ("1", "2", …) into the top-left corner of [frame]
/// so the assembled strip reads like a numbered comic page. Mutates [frame].
void _drawBeatLabel(img.Image frame, int beatNumber) {
  final label = '$beatNumber';
  // Scale the font to the frame so labels read at any resolution.
  final font = frame.width >= 1000
      ? img.arial48
      : frame.width >= 480
          ? img.arial24
          : img.arial14;
  const pad = 6;
  // Sum the actual advance of each glyph for an accurate plate width.
  final textW = label.codeUnits.fold<int>(
      0, (w, c) => w + (font.characters[c]?.xAdvance ?? font.base));
  final boxW = textW + pad * 2;
  final boxH = font.lineHeight + pad;
  // Semi-opaque black plate behind the number for legibility over any image.
  img.fillRect(frame,
      x1: 0, y1: 0, x2: boxW, y2: boxH, color: img.ColorRgba8(0, 0, 0, 170));
  img.drawString(frame, label,
      font: font, x: pad, y: pad ~/ 2, color: img.ColorRgba8(255, 255, 255, 255));
}

StoryboardResult _assembleStrip(_StripPayload payload) {
  var decoded = <img.Image>[];
  for (final bytes in payload.frames) {
    final d = img.decodeImage(bytes);
    if (d != null) decoded.add(d);
  }
  if (decoded.isEmpty) {
    throw StateError('No decodable frames in storyboard strip.');
  }

  // Number each frame before any resize so the badge scales with the frame.
  for (var i = 0; i < decoded.length; i++) {
    _drawBeatLabel(decoded[i], i + 1);
  }

  final gap = payload.gap;
  // A thin contrasting line drawn into the gap so frames read as separated
  // panels rather than a single seamless image.
  final separator = img.ColorRgba8(90, 90, 90, 255);

  if (payload.vertical) {
    // Normalize each frame to a common width; stack top-to-bottom.
    var targetW = decoded.map((d) => d.width).reduce((a, b) => a < b ? a : b);

    // Estimate the strip's long axis at this width and shrink targetW so it
    // stays under the cap (the encode buffer scales with total pixels).
    int estimateHeight(int w) {
      var total = gap * (decoded.length - 1);
      for (final d in decoded) {
        total += d.width == w ? d.height : (d.height * w / d.width).round();
      }
      return total;
    }

    var downscaled = false;
    if (estimateHeight(targetW) > payload.maxLongAxis) {
      // Binary-search-free: scale targetW by the ratio, then nudge down until
      // under cap. One proportional step is enough in practice.
      final ratio = payload.maxLongAxis / estimateHeight(targetW);
      targetW = (targetW * ratio).floor().clamp(1, targetW);
      while (targetW > 1 && estimateHeight(targetW) > payload.maxLongAxis) {
        targetW = (targetW * 0.95).floor();
      }
      downscaled = true;
    }

    final resized = decoded
        .map((d) => d.width == targetW
            ? d
            : img.copyResize(d, width: targetW, interpolation: img.Interpolation.linear))
        .toList();
    final totalH = resized.fold<int>(0, (sum, d) => sum + d.height) +
        gap * (resized.length - 1);
    final strip = img.Image(width: targetW, height: totalH, numChannels: 4);
    img.fill(strip, color: img.ColorRgba8(0, 0, 0, 255));
    int y = 0;
    for (var i = 0; i < resized.length; i++) {
      img.compositeImage(strip, resized[i], dstY: y);
      y += resized[i].height;
      if (i < resized.length - 1) {
        // Separator line centered in the gap band.
        final lineY = y + gap ~/ 2;
        img.drawLine(strip, x1: 0, y1: lineY, x2: targetW - 1, y2: lineY, color: separator);
        y += gap;
      }
    }
    return StoryboardResult(
      bytes: Uint8List.fromList(img.encodePng(strip)),
      downscaled: downscaled,
    );
  } else {
    // Normalize each frame to a common height; lay out left-to-right.
    var targetH = decoded.map((d) => d.height).reduce((a, b) => a < b ? a : b);

    int estimateWidth(int h) {
      var total = gap * (decoded.length - 1);
      for (final d in decoded) {
        total += d.height == h ? d.width : (d.width * h / d.height).round();
      }
      return total;
    }

    var downscaled = false;
    if (estimateWidth(targetH) > payload.maxLongAxis) {
      final ratio = payload.maxLongAxis / estimateWidth(targetH);
      targetH = (targetH * ratio).floor().clamp(1, targetH);
      while (targetH > 1 && estimateWidth(targetH) > payload.maxLongAxis) {
        targetH = (targetH * 0.95).floor();
      }
      downscaled = true;
    }

    final resized = decoded
        .map((d) => d.height == targetH
            ? d
            : img.copyResize(d, height: targetH, interpolation: img.Interpolation.linear))
        .toList();
    final totalW = resized.fold<int>(0, (sum, d) => sum + d.width) +
        gap * (resized.length - 1);
    final strip = img.Image(width: totalW, height: targetH, numChannels: 4);
    img.fill(strip, color: img.ColorRgba8(0, 0, 0, 255));
    int x = 0;
    for (var i = 0; i < resized.length; i++) {
      img.compositeImage(strip, resized[i], dstX: x);
      x += resized[i].width;
      if (i < resized.length - 1) {
        final lineX = x + gap ~/ 2;
        img.drawLine(strip, x1: lineX, y1: 0, x2: lineX, y2: targetH - 1, color: separator);
        x += gap;
      }
    }
    return StoryboardResult(
      bytes: Uint8List.fromList(img.encodePng(strip)),
      downscaled: downscaled,
    );
  }
}
