import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/tools/canvas/models/canvas_action.dart';
import 'package:naiweaver/features/tools/canvas/models/canvas_layer.dart';
import 'package:naiweaver/features/tools/canvas/models/paint_stroke.dart';

void main() {
  List<CanvasLayer> makeLayers() => [
        CanvasLayer(id: 'a', name: 'A', strokes: [
          const PaintStroke(
            points: [Offset(0.2, 0.3), Offset(0.4, 0.5)],
            radius: 0.01,
            colorValue: 0xFF112233,
          ),
        ]),
        CanvasLayer(id: 'b', name: 'B', strokes: [
          const PaintStroke(
            points: [Offset(0.9, 0.9)],
            radius: 0.02,
            colorValue: 0xFF445566,
          ),
        ]),
      ];

  group('TranslateLayerAction', () {
    test('apply shifts every stroke point; revert restores them exactly', () {
      final layers = makeLayers();
      const action = TranslateLayerAction(layerId: 'a', dx: 0.1, dy: -0.05);

      action.apply(layers, activeLayerId: 'a');
      expect(layers[0].strokes.single.points, const [
        Offset(0.2 + 0.1, 0.3 - 0.05),
        Offset(0.4 + 0.1, 0.5 - 0.05),
      ]);

      action.revert(layers);
      final restored = layers[0].strokes.single.points;
      expect(restored[0].dx, closeTo(0.2, 1e-12));
      expect(restored[0].dy, closeTo(0.3, 1e-12));
      expect(restored[1].dx, closeTo(0.4, 1e-12));
      expect(restored[1].dy, closeTo(0.5, 1e-12));
    });

    test('does not touch other layers', () {
      final layers = makeLayers();
      const action = TranslateLayerAction(layerId: 'a', dx: 0.1, dy: 0.1);
      action.apply(layers, activeLayerId: 'a');
      expect(layers[1].strokes.single.points, const [Offset(0.9, 0.9)]);
    });

    test('moveImage also shifts the image position', () {
      final layers = [
        CanvasLayer(
          id: 'img',
          name: 'Image',
          imageBytes: Uint8List.fromList([1, 2, 3]),
          imageX: 0.25,
          imageY: 0.5,
        ),
      ];
      const action = TranslateLayerAction(
          layerId: 'img', dx: 0.1, dy: 0.2, moveImage: true);

      action.apply(layers, activeLayerId: 'img');
      expect(layers[0].imageX, closeTo(0.35, 1e-12));
      expect(layers[0].imageY, closeTo(0.7, 1e-12));

      action.revert(layers);
      expect(layers[0].imageX, closeTo(0.25, 1e-12));
      expect(layers[0].imageY, closeTo(0.5, 1e-12));
    });

    test('round-trips through JSON', () {
      const action = TranslateLayerAction(
          layerId: 'a', dx: 0.125, dy: -0.25, moveImage: true);
      final restored =
          CanvasAction.fromJson(action.toJson()) as TranslateLayerAction;
      expect(restored.layerId, 'a');
      expect(restored.dx, 0.125);
      expect(restored.dy, -0.25);
      expect(restored.moveImage, isTrue);
    });
  });

  test('PaintStroke JSON round-trips the fill region and seed', () {
    final stroke = PaintStroke(
      points: const [Offset(0.5, 0.25)],
      radius: 0,
      colorValue: 0xFFABCDEF,
      strokeType: StrokeType.fill,
      fillRegionPng: Uint8List.fromList([1, 2, 3, 4]),
      fillSeed: const Offset(0.5, 0.25),
    );
    final restored = PaintStroke.fromJson(
        jsonDecode(jsonEncode(stroke.toJson())) as Map<String, dynamic>);
    expect(restored.fillRegionPng, [1, 2, 3, 4]);
    expect(restored.fillSeed, const Offset(0.5, 0.25));
    expect(restored.strokeType, StrokeType.fill);
  });

  test('PaintStroke.translated keeps the relative clone-source offset', () {
    const stroke = PaintStroke(
      points: [Offset(0.5, 0.5)],
      radius: 0.01,
      colorValue: 0xFF000000,
      strokeType: StrokeType.cloneStamp,
      cloneSourceOffset: Offset(0.1, 0.1),
    );
    final moved = stroke.translated(const Offset(0.2, 0.3));
    expect(moved.points.single, const Offset(0.7, 0.8));
    expect(moved.cloneSourceOffset, const Offset(0.1, 0.1));
  });
}
