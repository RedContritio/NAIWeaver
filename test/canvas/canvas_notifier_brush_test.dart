import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/tools/canvas/providers/canvas_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CanvasNotifier makeNotifier({int width = 1024, int height = 768}) {
    final notifier = CanvasNotifier();
    // Bytes never decode (color extraction fails silently); dimensions are
    // what brush sizing math uses.
    notifier.startSession(Uint8List.fromList([0, 1, 2]), width, height);
    return notifier;
  }

  group('brush sizing in pixels (#16)', () {
    test('diameter maps to normalized radius against source width', () {
      final n = makeNotifier(width: 1000);
      n.setBrushDiameterPx(100);
      expect(n.brushRadius, closeTo(0.05, 1e-9));
      expect(n.brushDiameterPx, closeTo(100, 1e-9));
    });

    test('floor is a 1px diameter, far below the old 0.2% floor', () {
      final n = makeNotifier(width: 1024);
      n.setBrushDiameterPx(1);
      expect(n.brushDiameterPx, closeTo(1, 1e-9));
      expect(n.brushRadius, closeTo(0.5 / 1024, 1e-12));
      // The old floor (0.002 of width) was a ~4px diameter on a 1024w image.
      expect(n.brushRadius, lessThan(0.002));
    });

    test('requests below one pixel clamp to the 1px floor', () {
      final n = makeNotifier(width: 1024);
      n.setBrushDiameterPx(0.2);
      expect(n.brushDiameterPx, closeTo(1, 1e-9));
    });

    test('ceiling stays at 15% of image width', () {
      final n = makeNotifier(width: 1000);
      n.setBrushDiameterPx(99999);
      expect(n.brushRadius, closeTo(0.15, 1e-9));
      expect(n.brushDiameterPx, closeTo(300, 1e-9));
    });

    test('brushStepPx is 10% of current size with a 1px minimum', () {
      final n = makeNotifier(width: 1000);
      n.setBrushDiameterPx(200);
      expect(n.brushStepPx, closeTo(20, 1e-9));
      n.setBrushDiameterPx(4);
      expect(n.brushStepPx, 1.0);
    });
  });
}
