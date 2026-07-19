import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naiweaver/features/tools/canvas/models/canvas_layer.dart';
import 'package:naiweaver/features/tools/canvas/models/paint_stroke.dart';
import 'package:naiweaver/features/tools/canvas/services/canvas_flatten_service.dart';

/// End-to-end coverage of the CPU flatten path honoring baked clip polygons —
/// the same guarantee the live painter gives via canvas.clipPath.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const leftHalf = [
    Offset(0, 0),
    Offset(0.5, 0),
    Offset(0.5, 1),
    Offset(0, 1),
  ];

  Uint8List whitePng(int w, int h) {
    final image = img.Image(width: w, height: h);
    img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
    return Uint8List.fromList(img.encodePng(image));
  }

  Future<img.Image> flatten(List<PaintStroke> strokes) async {
    final out = await CanvasFlattenService.flatten(
      sourceBytes: whitePng(8, 8),
      sourceWidth: 8,
      sourceHeight: 8,
      visibleLayers: [CanvasLayer(id: 'l', name: 'L', strokes: strokes)],
    );
    return img.decodeImage(out)!;
  }

  bool isRed(img.Pixel p) => p.r.toInt() > 200 && p.g.toInt() < 50;
  bool isWhite(img.Pixel p) => p.r.toInt() > 200 && p.g.toInt() > 200;

  test('clipped whole-canvas fill only paints inside the polygon', () async {
    const fill = PaintStroke(
      points: [Offset(0.25, 0.5)],
      radius: 0,
      colorValue: 0xFFFF0000,
      strokeType: StrokeType.fill,
      clipPolygon: leftHalf,
    );
    final result = await flatten(const [fill]);
    expect(isRed(result.getPixel(1, 4)), isTrue);
    expect(isRed(result.getPixel(3, 0)), isTrue);
    expect(isWhite(result.getPixel(4, 4)), isTrue);
    expect(isWhite(result.getPixel(7, 7)), isTrue);
  });

  test('clipped freehand stroke does not escape the polygon', () async {
    // A fat horizontal stroke across the whole image, clipped to the left half.
    const stroke = PaintStroke(
      points: [Offset(0.0, 0.5), Offset(1.0, 0.5)],
      radius: 0.2,
      colorValue: 0xFFFF0000,
      clipPolygon: leftHalf,
    );
    final result = await flatten(const [stroke]);
    expect(isRed(result.getPixel(2, 4)), isTrue);
    expect(isWhite(result.getPixel(6, 4)), isTrue);
  });

  test('erase-fill with clip deletes only inside the polygon', () async {
    const paintAll = PaintStroke(
      points: [Offset(0.5, 0.5)],
      radius: 0,
      colorValue: 0xFFFF0000,
      strokeType: StrokeType.fill,
    );
    const deleteLeft = PaintStroke(
      points: [Offset(0.25, 0.5)],
      radius: 0,
      colorValue: 0xFF000000,
      isErase: true,
      strokeType: StrokeType.fill,
      clipPolygon: leftHalf,
    );
    final result = await flatten(const [paintAll, deleteLeft]);
    // Left half erased back to the white source; right half still red.
    expect(isWhite(result.getPixel(1, 4)), isTrue);
    expect(isWhite(result.getPixel(3, 7)), isTrue);
    expect(isRed(result.getPixel(4, 0)), isTrue);
    expect(isRed(result.getPixel(7, 4)), isTrue);
  });

  test('unclipped strokes still cover the whole canvas', () async {
    const fill = PaintStroke(
      points: [Offset(0.5, 0.5)],
      radius: 0,
      colorValue: 0xFFFF0000,
      strokeType: StrokeType.fill,
    );
    final result = await flatten(const [fill]);
    expect(isRed(result.getPixel(0, 0)), isTrue);
    expect(isRed(result.getPixel(7, 7)), isTrue);
  });
}
