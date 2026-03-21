import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/img2img_session.dart';
import '../providers/img2img_notifier.dart';

/// The core painting widget: source image + mask overlay + gesture handling.
class MaskCanvas extends StatefulWidget {
  const MaskCanvas({super.key});

  @override
  State<MaskCanvas> createState() => _MaskCanvasState();
}

class _MaskCanvasState extends State<MaskCanvas> {
  /// The actual rect where the image is rendered (after BoxFit.contain).
  Rect _imageRect = Rect.zero;

  // Zoom & pan
  final TransformationController _zoomController = TransformationController();
  final FocusNode _keyboardFocusNode = FocusNode();
  bool _spaceHeld = false;

  @override
  void dispose() {
    _zoomController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<Img2ImgNotifier>();
    final session = notifier.session;
    if (session == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate the fitted image rect
        final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
        final imageAspect = session.sourceWidth / session.sourceHeight;
        final containerAspect = containerSize.width / containerSize.height;

        double renderWidth, renderHeight;
        if (imageAspect > containerAspect) {
          renderWidth = containerSize.width;
          renderHeight = containerSize.width / imageAspect;
        } else {
          renderHeight = containerSize.height;
          renderWidth = containerSize.height * imageAspect;
        }

        final offsetX = (containerSize.width - renderWidth) / 2;
        final offsetY = (containerSize.height - renderHeight) / 2;
        _imageRect = Rect.fromLTWH(offsetX, offsetY, renderWidth, renderHeight);

        final isPanMode = _spaceHeld;

        return KeyboardListener(
          focusNode: _keyboardFocusNode,
          onKeyEvent: (event) {
            if (event.logicalKey == LogicalKeyboardKey.space) {
              setState(() => _spaceHeld = event is KeyDownEvent);
            }
          },
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                _onPointerSignal(event, notifier);
              }
            },
            child: MouseRegion(
              cursor: isPanMode
                  ? SystemMouseCursors.grab
                  : SystemMouseCursors.none,
              child: InteractiveViewer(
                transformationController: _zoomController,
                panEnabled: isPanMode,
                scaleEnabled: false,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: 0.25,
                maxScale: 16.0,
                child: GestureDetector(
                  onPanStart: isPanMode
                      ? null
                      : (details) => _onPanStart(details, notifier),
                  onPanUpdate: isPanMode
                      ? null
                      : (details) => _onPanUpdate(details, notifier),
                  onPanEnd: isPanMode
                      ? null
                      : (_) => notifier.endStroke(),
                  child: SizedBox(
                    width: containerSize.width,
                    height: containerSize.height,
                    child: Stack(
                      children: [
                        // Source image
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: Image.memory(
                                session.sourceImageBytes,
                                width: session.sourceWidth.toDouble(),
                                height: session.sourceHeight.toDouble(),
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                          ),
                        ),

                        // Mask overlay
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _MaskOverlayPainter(
                              strokes: session.maskStrokes,
                              activeStroke: notifier.activeStroke,
                              imageRect: _imageRect,
                              sourceWidth: session.sourceWidth,
                              sourceHeight: session.sourceHeight,
                              maskColor: notifier.maskColor,
                              maskOpacity: notifier.maskOpacity,
                              maskShowBorder: notifier.maskShowBorder,
                              maskPattern: notifier.maskPattern,
                            ),
                          ),
                        ),

                        // Cursor preview
                        Positioned.fill(
                          child: _CursorPreview(
                            brushRadius: notifier.brushRadius,
                            isErase: notifier.isEraseMode,
                            imageRect: _imageRect,
                            sourceWidth: session.sourceWidth,
                            sourceHeight: session.sourceHeight,
                            maskColor: notifier.maskColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onPointerSignal(PointerScrollEvent event, Img2ImgNotifier notifier) {
    final keyboard = HardwareKeyboard.instance;
    final ctrlHeld = keyboard.isControlPressed || keyboard.isMetaPressed;

    if (ctrlHeld) {
      // Ctrl + scroll: adjust brush size
      final delta = event.scrollDelta.dy > 0 ? -0.005 : 0.005;
      notifier.setBrushRadius(notifier.brushRadius + delta);
    } else {
      // Plain scroll: zoom
      final zoomFactor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
      final focalPoint = event.localPosition;
      final matrix = _zoomController.value.clone();
      // ignore: deprecated_member_use
      matrix.translate(focalPoint.dx, focalPoint.dy);
      // ignore: deprecated_member_use
      matrix.scale(zoomFactor, zoomFactor);
      // ignore: deprecated_member_use
      matrix.translate(-focalPoint.dx, -focalPoint.dy);
      _zoomController.value = matrix;
    }
  }

  void _onPanStart(DragStartDetails details, Img2ImgNotifier notifier) {
    final normalized = _toNormalized(details.localPosition);
    if (normalized != null) {
      notifier.beginStroke(normalized);
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Img2ImgNotifier notifier) {
    final normalized = _toNormalized(details.localPosition);
    if (normalized != null) {
      notifier.addStrokePoint(normalized);
    }
  }

  Offset? _toNormalized(Offset localPosition) {
    if (_imageRect.width <= 0 || _imageRect.height <= 0) return null;
    // Invert zoom/pan transform
    try {
      final inverseMatrix = Matrix4.inverted(_zoomController.value);
      final transformed = MatrixUtils.transformPoint(inverseMatrix, localPosition);
      final x = (transformed.dx - _imageRect.left) / _imageRect.width;
      final y = (transformed.dy - _imageRect.top) / _imageRect.height;
      return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
    } catch (_) {
      final x = (localPosition.dx - _imageRect.left) / _imageRect.width;
      final y = (localPosition.dy - _imageRect.top) / _imageRect.height;
      return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
    }
  }
}

/// Paints the mask strokes as a semi-transparent overlay, grid-snapped to 8px.
class _MaskOverlayPainter extends CustomPainter {
  final List<MaskStroke> strokes;
  final MaskStroke? activeStroke;
  final Rect imageRect;
  final int sourceWidth;
  final int sourceHeight;
  final int maskColor;
  final double maskOpacity;
  final bool maskShowBorder;
  final MaskPattern maskPattern;

  _MaskOverlayPainter({
    required this.strokes,
    this.activeStroke,
    required this.imageRect,
    required this.sourceWidth,
    required this.sourceHeight,
    this.maskColor = 0xFFFF0066,
    this.maskOpacity = 0.19,
    this.maskShowBorder = false,
    this.maskPattern = MaskPattern.solid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageRect.isEmpty) return;

    // Collect all strokes (committed + active) by type
    final allStrokes = [...strokes, if (activeStroke != null) activeStroke!];

    // One saveLayer for all paint strokes — uniform alpha regardless of overlap
    final paintStrokes = allStrokes.where((s) => !s.isErase).toList();
    if (paintStrokes.isNotEmpty) {
      canvas.saveLayer(
        null,
        Paint()..color = Color.fromARGB((maskOpacity * 255).round(), 0, 0, 0),
      );
      final brush = Paint()
        ..color = Color(maskColor)
        ..style = PaintingStyle.fill
        ..isAntiAlias = false;
      for (final stroke in paintStrokes) {
        _drawStrokeGeometry(canvas, stroke, brush);
      }

      // Stripe / crosshatch pattern
      if (maskPattern != MaskPattern.solid) {
        _drawPattern(canvas, paintStrokes);
      }

      canvas.restore();

      // Border outline around mask edges
      if (maskShowBorder) {
        final borderBrush = Paint()
          ..color = Color(maskColor).withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..isAntiAlias = true;
        for (final stroke in paintStrokes) {
          _drawStrokeBorder(canvas, stroke, borderBrush);
        }
      }
    }

    // One saveLayer for all erase strokes — uniform alpha regardless of overlap
    final eraseStrokes = allStrokes.where((s) => s.isErase).toList();
    if (eraseStrokes.isNotEmpty) {
      canvas.saveLayer(
        null,
        Paint()..color = Color.fromARGB((maskOpacity * 0.66 * 255).round(), 0, 0, 0),
      );
      final brush = Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.fill
        ..isAntiAlias = false;
      for (final stroke in eraseStrokes) {
        _drawStrokeGeometry(canvas, stroke, brush);
      }
      canvas.restore();
    }
  }

  void _drawPattern(Canvas canvas, List<MaskStroke> paintStrokes) {
    // Draw diagonal stripes clipped to the mask region using dstIn blend
    canvas.saveLayer(null, Paint()..blendMode = BlendMode.dstIn);
    final patternPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const spacing = 6.0;
    final maxDim = math.max(imageRect.width, imageRect.height) * 2;

    // Diagonal stripes (top-left to bottom-right)
    for (double offset = -maxDim; offset < maxDim; offset += spacing) {
      canvas.drawLine(
        Offset(imageRect.left + offset, imageRect.top),
        Offset(imageRect.left + offset + maxDim, imageRect.top + maxDim),
        patternPaint,
      );
    }

    // Crosshatch: second diagonal (top-right to bottom-left)
    if (maskPattern == MaskPattern.crosshatch) {
      for (double offset = -maxDim; offset < maxDim; offset += spacing) {
        canvas.drawLine(
          Offset(imageRect.right - offset, imageRect.top),
          Offset(imageRect.right - offset - maxDim, imageRect.top + maxDim),
          patternPaint,
        );
      }
    }

    canvas.restore();
  }

  /// Draw a stroke-width outline around the grid-snapped mask boundary.
  void _drawStrokeBorder(Canvas canvas, MaskStroke stroke, Paint paint) {
    const grid = 8;
    final gridW = grid / sourceWidth * imageRect.width;
    final gridH = grid / sourceHeight * imageRect.height;
    final rawR = stroke.radius * imageRect.width;
    final r = ((rawR / gridW).ceil()).clamp(1, sourceWidth) * gridW;

    for (final point in stroke.points) {
      final rawPx = imageRect.left + point.dx * imageRect.width;
      final rawPy = imageRect.top + point.dy * imageRect.height;
      final px = imageRect.left + ((rawPx - imageRect.left) / gridW).floor() * gridW;
      final py = imageRect.top + ((rawPy - imageRect.top) / gridH).floor() * gridH;
      canvas.drawRect(Rect.fromLTWH(px - r, py - r, r * 2, r * 2), paint);
    }
  }

  /// Draw the grid-snapped rectangles for a single stroke without any
  /// saveLayer or alpha — the caller is responsible for compositing.
  void _drawStrokeGeometry(Canvas canvas, MaskStroke stroke, Paint paint) {
    // Grid step in screen coordinates (8 source pixels)
    const grid = 8;
    final gridW = grid / sourceWidth * imageRect.width;
    final gridH = grid / sourceHeight * imageRect.height;

    // Snap brush radius UP to nearest grid cell (minimum 1 grid cell)
    final rawR = stroke.radius * imageRect.width;
    final r = ((rawR / gridW).ceil()).clamp(1, sourceWidth) * gridW;

    // Draw grid-aligned square at each sampled point
    for (final point in stroke.points) {
      final rawPx = imageRect.left + point.dx * imageRect.width;
      final rawPy = imageRect.top + point.dy * imageRect.height;
      final px = imageRect.left + ((rawPx - imageRect.left) / gridW).floor() * gridW;
      final py = imageRect.top + ((rawPy - imageRect.top) / gridH).floor() * gridH;
      canvas.drawRect(Rect.fromLTWH(px - r, py - r, r * 2, r * 2), paint);
    }

    // Interpolate between consecutive points
    for (int i = 0; i < stroke.points.length - 1; i++) {
      final p1 = stroke.points[i];
      final p2 = stroke.points[i + 1];
      final rawX1 = imageRect.left + p1.dx * imageRect.width;
      final rawY1 = imageRect.top + p1.dy * imageRect.height;
      final rawX2 = imageRect.left + p2.dx * imageRect.width;
      final rawY2 = imageRect.top + p2.dy * imageRect.height;
      final x1 = imageRect.left + ((rawX1 - imageRect.left) / gridW).floor() * gridW;
      final y1 = imageRect.top + ((rawY1 - imageRect.top) / gridH).floor() * gridH;
      final x2 = imageRect.left + ((rawX2 - imageRect.left) / gridW).floor() * gridW;
      final y2 = imageRect.top + ((rawY2 - imageRect.top) / gridH).floor() * gridH;
      final dx = x2 - x1;
      final dy = y2 - y1;
      final steps = [dx.abs(), dy.abs(), 1.0].reduce((a, b) => a > b ? a : b).ceil();
      for (int s = 1; s < steps; s++) {
        final t = s / steps;
        final rawIx = x1 + dx * t;
        final rawIy = y1 + dy * t;
        final ix = imageRect.left + ((rawIx - imageRect.left) / gridW).floor() * gridW;
        final iy = imageRect.top + ((rawIy - imageRect.top) / gridH).floor() * gridH;
        canvas.drawRect(Rect.fromLTWH(ix - r, iy - r, r * 2, r * 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_MaskOverlayPainter oldDelegate) =>
      strokes != oldDelegate.strokes ||
      activeStroke != oldDelegate.activeStroke ||
      imageRect != oldDelegate.imageRect ||
      maskColor != oldDelegate.maskColor ||
      maskOpacity != oldDelegate.maskOpacity ||
      maskShowBorder != oldDelegate.maskShowBorder ||
      maskPattern != oldDelegate.maskPattern;
}

/// Shows a grid-snapped square cursor that follows the mouse position.
class _CursorPreview extends StatefulWidget {
  final double brushRadius;
  final bool isErase;
  final Rect imageRect;
  final int sourceWidth;
  final int sourceHeight;
  final int maskColor;

  const _CursorPreview({
    required this.brushRadius,
    required this.isErase,
    required this.imageRect,
    required this.sourceWidth,
    required this.sourceHeight,
    this.maskColor = 0xFFFF0066,
  });

  @override
  State<_CursorPreview> createState() => _CursorPreviewState();
}

class _CursorPreviewState extends State<_CursorPreview> {
  Offset? _mousePosition;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      hitTestBehavior: HitTestBehavior.translucent,
      onHover: (event) => setState(() => _mousePosition = event.localPosition),
      onExit: (_) => setState(() => _mousePosition = null),
      child: CustomPaint(
        painter: _CursorPainter(
          position: _mousePosition,
          rawRadius: widget.brushRadius * widget.imageRect.width,
          isErase: widget.isErase,
          imageRect: widget.imageRect,
          sourceWidth: widget.sourceWidth,
          sourceHeight: widget.sourceHeight,
          maskColor: widget.maskColor,
        ),
      ),
    );
  }
}

class _CursorPainter extends CustomPainter {
  final Offset? position;
  final double rawRadius;
  final bool isErase;
  final Rect imageRect;
  final int sourceWidth;
  final int sourceHeight;
  final int maskColor;

  _CursorPainter({
    this.position,
    required this.rawRadius,
    required this.isErase,
    required this.imageRect,
    required this.sourceWidth,
    required this.sourceHeight,
    this.maskColor = 0xFFFF0066,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (position == null || rawRadius <= 0 || imageRect.isEmpty) return;

    const grid = 8;
    final gridW = grid / sourceWidth * imageRect.width;
    final gridH = grid / sourceHeight * imageRect.height;

    // Snap brush radius UP to nearest grid cell
    final r = ((rawRadius / gridW).ceil()).clamp(1, sourceWidth) * gridW;

    // Snap cursor position to grid
    final rawPx = position!.dx;
    final rawPy = position!.dy;
    final px = imageRect.left + ((rawPx - imageRect.left) / gridW).floor() * gridW;
    final py = imageRect.top + ((rawPy - imageRect.top) / gridH).floor() * gridH;

    final paint = Paint()
      ..color = isErase ? Colors.white70 : Color(maskColor).withValues(alpha: 0.67)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRect(Rect.fromLTWH(px - r, py - r, r * 2, r * 2), paint);

    // Small crosshair at snapped center
    final crossPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(px - 4, py), Offset(px + 4, py), crossPaint);
    canvas.drawLine(Offset(px, py - 4), Offset(px, py + 4), crossPaint);
  }

  @override
  bool shouldRepaint(_CursorPainter oldDelegate) =>
      position != oldDelegate.position ||
      rawRadius != oldDelegate.rawRadius ||
      isErase != oldDelegate.isErase;
}
