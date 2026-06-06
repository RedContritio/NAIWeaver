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

  /// Burns captions onto every frame, then stacks them into a single storyboard
  /// strip image. Frames are normalized to a common cross-axis size so they line
  /// up. Returns PNG bytes of the assembled strip.
  static Future<Uint8List> buildStoryboardStrip(
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
  _StripPayload({required this.frames, required this.vertical, required this.gap});
}

Uint8List _assembleStrip(_StripPayload payload) {
  final decoded = <img.Image>[];
  for (final bytes in payload.frames) {
    final d = img.decodeImage(bytes);
    if (d != null) decoded.add(d);
  }
  if (decoded.isEmpty) {
    throw StateError('No decodable frames in storyboard strip.');
  }

  final gap = payload.gap;

  if (payload.vertical) {
    // Normalize each frame to a common width; stack top-to-bottom.
    final targetW = decoded.map((d) => d.width).reduce((a, b) => a < b ? a : b);
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
    for (final d in resized) {
      img.compositeImage(strip, d, dstY: y);
      y += d.height + gap;
    }
    return Uint8List.fromList(img.encodePng(strip));
  } else {
    // Normalize each frame to a common height; lay out left-to-right.
    final targetH = decoded.map((d) => d.height).reduce((a, b) => a < b ? a : b);
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
    for (final d in resized) {
      img.compositeImage(strip, d, dstX: x);
      x += d.width + gap;
    }
    return Uint8List.fromList(img.encodePng(strip));
  }
}
