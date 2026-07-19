import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naiweaver/features/tools/canvas/models/canvas_selection.dart';
import 'package:naiweaver/features/tools/canvas/models/paint_stroke.dart';
import 'package:naiweaver/features/tools/canvas/providers/canvas_notifier.dart';
import 'package:naiweaver/features/tools/canvas/services/selection_geometry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CanvasNotifier makeNotifier({int width = 1024, int height = 768}) {
    final notifier = CanvasNotifier();
    // Bytes never decode (color extraction fails silently); only the
    // dimensions matter for selection geometry.
    notifier.startSession(Uint8List.fromList([0, 1, 2]), width, height);
    return notifier;
  }

  /// Paints a simple committed stroke so the active layer has content.
  void paintSomething(CanvasNotifier n) {
    n.beginStroke(const Offset(0.1, 0.1));
    n.addStrokePoint(const Offset(0.9, 0.9));
    n.endStroke();
  }

  void selectRect(CanvasNotifier n, Offset a, Offset b) {
    n.beginSelection(a);
    n.updateSelectionRect(b);
    n.endSelectionRect();
  }

  group('deleteSelectionContents', () {
    test('adds a clipped erase-fill stroke as one undoable action', () {
      final n = makeNotifier();
      paintSomething(n);
      selectRect(n, const Offset(0.25, 0.25), const Offset(0.75, 0.75));

      final before = n.session!.activeLayer!.strokes.length;
      n.deleteSelectionContents();

      final strokes = n.session!.activeLayer!.strokes;
      expect(strokes.length, before + 1);
      final del = strokes.last;
      expect(del.isErase, isTrue);
      expect(del.strokeType, StrokeType.fill);
      expect(del.clipPolygon, isNotNull);
      expect(
        del.clipPolygon,
        selectionToPolygon(n.activeSelection!, aspect: 1024 / 768),
      );

      // Selection survives the delete.
      expect(n.hasSelection, isTrue);

      // Undo removes exactly the delete stroke; redo restores it.
      n.undo();
      expect(n.session!.activeLayer!.strokes.length, before);
      n.redo();
      expect(n.session!.activeLayer!.strokes.length, before + 1);
    });

    test('works for a moved and scaled marquee', () {
      final n = makeNotifier();
      paintSomething(n);
      selectRect(n, const Offset(0.2, 0.2), const Offset(0.4, 0.4));
      // Drag the body, then scale from a corner.
      n.beginSelectionDrag(SelectionHandle.body, const Offset(0.3, 0.3));
      n.updateSelectionDrag(const Offset(0.5, 0.5));
      n.endSelectionDrag();

      n.deleteSelectionContents();
      final del = n.session!.activeLayer!.strokes.last;
      // Polygon reflects the offset marquee, not the original rect.
      expect(del.clipPolygon!.first.dx, closeTo(0.4, 1e-9));
      expect(del.clipPolygon!.first.dy, closeTo(0.4, 1e-9));
    });

    test('works for lasso selections', () {
      final n = makeNotifier();
      paintSomething(n);
      n.beginLassoSelection(const Offset(0.2, 0.2));
      n.addLassoPoint(const Offset(0.8, 0.2));
      n.addLassoPoint(const Offset(0.5, 0.8));
      n.endLassoSelection();

      n.deleteSelectionContents();
      final del = n.session!.activeLayer!.strokes.last;
      expect(del.clipPolygon!.length, 3);
      expect(del.clipPolygon!.first, const Offset(0.2, 0.2));
    });

    test('no-ops without a selection', () {
      final n = makeNotifier();
      paintSomething(n);
      final before = n.session!.activeLayer!.strokes.length;
      n.deleteSelectionContents();
      expect(n.session!.activeLayer!.strokes.length, before);
    });

    test('no-ops on a layer with nothing to erase', () {
      final n = makeNotifier();
      selectRect(n, const Offset(0.25, 0.25), const Offset(0.75, 0.75));
      n.deleteSelectionContents();
      expect(n.session!.activeLayer!.strokes, isEmpty);
      expect(n.session!.canUndo, isFalse);
    });
  });

  group('painting clipped to the selection', () {
    test('committed strokes capture the selection polygon', () {
      final n = makeNotifier();
      selectRect(n, const Offset(0.25, 0.25), const Offset(0.75, 0.75));
      final expected =
          selectionToPolygon(n.activeSelection!, aspect: 1024 / 768);

      paintSomething(n);
      final stroke = n.session!.activeLayer!.strokes.single;
      expect(stroke.clipPolygon, expected);
    });

    test('the live preview stroke carries the same clip', () {
      final n = makeNotifier();
      selectRect(n, const Offset(0.25, 0.25), const Offset(0.75, 0.75));
      n.beginStroke(const Offset(0.5, 0.5));
      expect(n.activeStroke!.clipPolygon, isNotNull);
      n.cancelStroke();
    });

    test('strokes committed without a selection carry no clip', () {
      final n = makeNotifier();
      paintSomething(n);
      expect(n.session!.activeLayer!.strokes.single.clipPolygon, isNull);
    });

    test('the baked clip survives the selection being cleared', () {
      final n = makeNotifier();
      selectRect(n, const Offset(0.25, 0.25), const Offset(0.75, 0.75));
      paintSomething(n);
      n.cancelSelection();
      expect(n.session!.activeLayer!.strokes.single.clipPolygon, isNotNull);
    });

    test('flood fill captures the selection clip at tap time', () async {
      // Real decodable source so the fill-region isolate has pixels to chew.
      final white = img.Image(width: 8, height: 8);
      img.fill(white, color: img.ColorRgba8(255, 255, 255, 255));
      final n = CanvasNotifier();
      n.startSession(Uint8List.fromList(img.encodePng(white)), 8, 8);
      selectRect(n, const Offset(0.25, 0.25), const Offset(0.75, 0.75));

      await n.applyFill(const Offset(0.5, 0.5));

      final stroke = n.session!.activeLayer!.strokes.single;
      expect(stroke.strokeType, StrokeType.fill);
      expect(stroke.fillRegionPng, isNotNull);
      expect(stroke.clipPolygon,
          selectionToPolygon(n.activeSelection!, aspect: 1.0));
    });
  });

  group('selection lifecycle', () {
    test('clearSession drops the active selection', () {
      final n = makeNotifier();
      selectRect(n, const Offset(0.2, 0.2), const Offset(0.8, 0.8));
      expect(n.hasSelection, isTrue);
      n.clearSession();
      expect(n.hasSelection, isFalse);
    });

    test('startSession drops a selection left over from a previous session',
        () {
      final n = makeNotifier();
      selectRect(n, const Offset(0.2, 0.2), const Offset(0.8, 0.8));
      n.startSession(Uint8List.fromList([3, 4, 5]), 512, 512);
      expect(n.hasSelection, isFalse);
    });
  });
}
