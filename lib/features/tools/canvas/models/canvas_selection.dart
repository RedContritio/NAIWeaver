import 'dart:typed_data';
import 'dart:ui';

/// Represents an active rectangular or freeform selection on the canvas.
/// Coordinates are normalized (0-1) relative to the source image dimensions.
class CanvasSelection {
  /// The original bounding rect of the selection (normalized 0-1).
  final Rect normalizedRect;

  /// Optional freeform clip path for lasso selections (normalized 0-1).
  final List<Offset>? clipPath;

  /// Rasterized pixel data of the selected region (PNG bytes).
  final Uint8List? pixelData;

  /// Current position offset from original rect (normalized).
  final double offsetX;
  final double offsetY;

  /// Current scale factor (1.0 = original size).
  final double scale;

  /// Current rotation in radians.
  final double rotation;

  const CanvasSelection({
    required this.normalizedRect,
    this.clipPath,
    this.pixelData,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  CanvasSelection copyWith({
    Rect? normalizedRect,
    List<Offset>? clipPath,
    Uint8List? pixelData,
    double? offsetX,
    double? offsetY,
    double? scale,
    double? rotation,
  }) {
    return CanvasSelection(
      normalizedRect: normalizedRect ?? this.normalizedRect,
      clipPath: clipPath ?? this.clipPath,
      pixelData: pixelData ?? this.pixelData,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  /// The current transformed rect (original rect + offset + scale).
  Rect get transformedRect {
    final w = normalizedRect.width * scale;
    final h = normalizedRect.height * scale;
    final cx = normalizedRect.center.dx + offsetX;
    final cy = normalizedRect.center.dy + offsetY;
    return Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
  }

  /// Whether a normalized point is inside the selection handle area.
  SelectionHandle? hitTestHandle(Offset normalizedPoint, double handleRadius) {
    final r = transformedRect;
    final hr = handleRadius;

    // Corner handles
    if ((normalizedPoint - r.topLeft).distance < hr) return SelectionHandle.topLeft;
    if ((normalizedPoint - r.topRight).distance < hr) return SelectionHandle.topRight;
    if ((normalizedPoint - r.bottomLeft).distance < hr) return SelectionHandle.bottomLeft;
    if ((normalizedPoint - r.bottomRight).distance < hr) return SelectionHandle.bottomRight;

    // Rotation handle (above top center)
    final rotHandle = Offset(r.center.dx, r.top - hr * 3);
    if ((normalizedPoint - rotHandle).distance < hr) return SelectionHandle.rotate;

    // Body drag
    if (r.contains(normalizedPoint)) return SelectionHandle.body;

    return null;
  }
}

/// Which handle of the selection the user is dragging.
enum SelectionHandle { topLeft, topRight, bottomLeft, bottomRight, body, rotate }
