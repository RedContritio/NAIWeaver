import 'dart:ui';

import 'package:flutter/widgets.dart' show Matrix4, immutable;

/// Pure zoom/pan math shared by the canvas editor and the inpaint mask editor.
///
/// Both surfaces render into a child that is exactly viewport-sized (the image
/// letterboxed inside it) and only ever transform it with a uniform scale
/// followed by a translation. The whole transform therefore fits in three
/// doubles, which keeps this logic free of widget dependencies and
/// unit-testable.

/// Fit-to-view floor: at scale 1 the whole image is already visible, so
/// zooming out further only adds empty space around it.
const double kCanvasMinScale = 1.0;
const double kCanvasMaxScale = 16.0;

/// A uniform scale followed by a translation, in viewport coordinates.
@immutable
class ZoomState {
  final double scale;
  final double tx;
  final double ty;

  const ZoomState({required this.scale, required this.tx, required this.ty});

  static const ZoomState identity = ZoomState(scale: 1, tx: 0, ty: 0);

  /// Reads scale + translation from a scale-and-translate-only matrix.
  factory ZoomState.fromMatrix(Matrix4 m) =>
      ZoomState(scale: m.storage[0], tx: m.storage[12], ty: m.storage[13]);

  Matrix4 toMatrix() => Matrix4.identity()
    ..setEntry(0, 0, scale)
    ..setEntry(1, 1, scale)
    ..setEntry(0, 3, tx)
    ..setEntry(1, 3, ty);

  /// Maps a viewport point into untransformed (scene) coordinates.
  Offset toScene(Offset viewportPoint) =>
      Offset((viewportPoint.dx - tx) / scale, (viewportPoint.dy - ty) / scale);
}

/// Scales around [focalViewport] — the scene point under it stays put — then
/// clamps the scale to [minScale]..[maxScale] and the translation via
/// [clampToViewport]. Because the translation clamp recenters at fit scale,
/// zooming out always converges on the centered fit view instead of drifting
/// off-canvas.
ZoomState zoomAtPoint(
  ZoomState current,
  Offset focalViewport,
  double factor,
  Size viewportSize, {
  double minScale = kCanvasMinScale,
  double maxScale = kCanvasMaxScale,
}) {
  if (viewportSize.isEmpty || factor <= 0 || current.scale <= 0) return current;
  final newScale = (current.scale * factor).clamp(minScale, maxScale);
  final k = newScale / current.scale;
  // Keeping viewport point f over the same scene point p requires
  // t' = k*t + f*(1-k), from f = s*p + t and f = s'*p + t'.
  return clampToViewport(
    ZoomState(
      scale: newScale,
      tx: k * current.tx + focalViewport.dx * (1 - k),
      ty: k * current.ty + focalViewport.dy * (1 - k),
    ),
    viewportSize,
  );
}

/// Clamps the translation so viewport-sized content always covers the
/// viewport when zoomed in, and sits centered at or below fit scale.
ZoomState clampToViewport(ZoomState state, Size viewportSize) {
  double clampAxis(double t, double extent) {
    final overhang = extent * (1 - state.scale);
    if (state.scale <= 1) return overhang / 2;
    return t.clamp(overhang, 0.0);
  }

  return ZoomState(
    scale: state.scale,
    tx: clampAxis(state.tx, viewportSize.width),
    ty: clampAxis(state.ty, viewportSize.height),
  );
}

/// Applies one mouse-wheel tick to a [TransformationController] matrix.
/// Zoom-in and zoom-out use exactly inverse factors so ticks cancel out.
Matrix4 wheelZoomMatrix({
  required Matrix4 current,
  required Offset focalViewport,
  required bool zoomIn,
  required Size viewportSize,
}) {
  return zoomAtPoint(
    ZoomState.fromMatrix(current),
    focalViewport,
    zoomIn ? 1.1 : 1 / 1.1,
    viewportSize,
  ).toMatrix();
}
