import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../models/canvas_layer.dart';
import '../models/canvas_selection.dart';
import '../models/paint_stroke.dart';
import '../providers/canvas_notifier.dart';

/// Build a [TextStyle] with an optional Google Fonts family.
TextStyle _buildFontStyle({
  required Color color,
  required double fontSize,
  String? fontFamily,
  double? letterSpacing,
}) {
  final base = TextStyle(
    color: color,
    fontSize: fontSize,
    letterSpacing: letterSpacing,
  );
  if (fontFamily == null) return base;
  try {
    return GoogleFonts.getFont(fontFamily, textStyle: base);
  } catch (_) {
    return base;
  }
}

/// The painting widget: source image + paint overlay (CustomPaint) + gesture handling + cursor preview + inline text editor.
class CanvasPaintSurface extends StatefulWidget {
  const CanvasPaintSurface({super.key});

  @override
  State<CanvasPaintSurface> createState() => _CanvasPaintSurfaceState();
}

class _CanvasPaintSurfaceState extends State<CanvasPaintSurface> {
  Rect _imageRect = Rect.zero;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();

  // Zoom & pan
  final TransformationController _zoomController = TransformationController();
  final FocusNode _keyboardFocusNode = FocusNode();
  final FocusNode _textKeyboardFocusNode = FocusNode();
  bool _spaceHeld = false;
  bool _middleMouseHeld = false;

  // Image layer cache
  final Map<String, ui.Image> _imageLayerCache = {};
  final Set<String> _decodingImages = {};

  // Layer raster cache: caches rendered layer content as ui.Image to avoid
  // re-drawing all strokes every frame for unchanged layers.
  final Map<String, ui.Image> _layerRasterCache = {};
  final Map<String, String> _layerRasterKeys = {}; // layerId -> cache key

  /// Build a cache key for a layer based on its mutable properties.
  String _layerCacheKey(CanvasLayer layer) =>
      '${layer.id}:${layer.strokes.length}:${layer.visible}:${layer.opacity}:${layer.blendMode}:${layer.imageScale}:${layer.imageX}:${layer.imageY}:${layer.imageRotation}';

  /// Update the layer raster cache, invalidating stale entries and scheduling
  /// rasterization for non-active layers that have changed.
  void _updateLayerRasterCache(List<CanvasLayer> layers, String activeLayerId) {
    // Remove cache entries for layers that no longer exist
    final layerIds = layers.map((l) => l.id).toSet();
    _layerRasterCache.keys.where((id) => !layerIds.contains(id)).toList().forEach((id) {
      _layerRasterCache[id]?.dispose();
      _layerRasterCache.remove(id);
      _layerRasterKeys.remove(id);
    });

    // Invalidate entries where the cache key has changed
    for (final layer in layers) {
      if (layer.id == activeLayerId) continue; // don't cache active layer
      final key = _layerCacheKey(layer);
      if (_layerRasterKeys[layer.id] != key) {
        _layerRasterCache[layer.id]?.dispose();
        _layerRasterCache.remove(layer.id);
        _layerRasterKeys.remove(layer.id);
      }
    }

    // Schedule rasterization for uncached non-active layers in a post-frame callback
    for (final layer in layers) {
      if (layer.id == activeLayerId) continue;
      if (!layer.visible) continue;
      if (layer.strokes.isEmpty && !layer.isImageLayer) continue;
      if (_layerRasterCache.containsKey(layer.id)) continue;

      final key = _layerCacheKey(layer);
      // Rasterize this layer
      _rasterizeLayer(layer, key);
    }
  }

  /// Rasterize a single layer to a ui.Image and cache it.
  void _rasterizeLayer(CanvasLayer layer, String cacheKey) {
    if (_imageRect.isEmpty) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & Size(_imageRect.right + _imageRect.left, _imageRect.bottom + _imageRect.top));

    // Draw image layer content
    if (layer.isImageLayer) {
      final cached = _imageLayerCache[layer.id];
      if (cached != null) {
        canvas.save();
        final imgW = cached.width.toDouble();
        final imgH = cached.height.toDouble();
        final scale = layer.imageScale * _imageRect.width / imgW;
        final dx = _imageRect.left + layer.imageX * _imageRect.width;
        final dy = _imageRect.top + layer.imageY * _imageRect.height;
        canvas.translate(dx + imgW * scale / 2, dy + imgH * scale / 2);
        canvas.rotate(layer.imageRotation);
        canvas.translate(-imgW * scale / 2, -imgH * scale / 2);
        canvas.drawImageRect(
          cached,
          Rect.fromLTWH(0, 0, imgW, imgH),
          Rect.fromLTWH(0, 0, imgW * scale, imgH * scale),
          Paint(),
        );
        canvas.restore();
      }
    }

    // We can't easily draw strokes here since the painter methods are private.
    // Instead, we use a lighter approach: only cache layers that have an image
    // and no strokes, which is the common case for imported image layers.
    // For stroke-heavy layers, the painter will draw them directly.
    if (layer.strokes.isNotEmpty) {
      // Can't rasterize stroke-only layers without duplicating painter logic.
      // The shouldRepaint optimization handles this case instead.
      return;
    }

    final picture = recorder.endRecording();
    final width = (_imageRect.right + _imageRect.left).ceil();
    final height = (_imageRect.bottom + _imageRect.top).ceil();
    if (width <= 0 || height <= 0) return;

    picture.toImage(width, height).then((image) {
      if (mounted) {
        setState(() {
          _layerRasterCache[layer.id] = image;
          _layerRasterKeys[layer.id] = cacheKey;
        });
      }
      picture.dispose();
    });
  }

  void _ensureImageCached(CanvasLayer layer) {
    if (!layer.isImageLayer || layer.imageBytes == null) return;
    if (_imageLayerCache.containsKey(layer.id)) return;
    if (_decodingImages.contains(layer.id)) return;
    _decodingImages.add(layer.id);

    ui.decodeImageFromList(layer.imageBytes!, (result) {
      if (mounted) {
        setState(() {
          _imageLayerCache[layer.id] = result;
          _decodingImages.remove(layer.id);
        });
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    _zoomController.dispose();
    _keyboardFocusNode.dispose();
    _textKeyboardFocusNode.dispose();
    for (final img in _imageLayerCache.values) {
      img.dispose();
    }
    for (final img in _layerRasterCache.values) {
      img.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<CanvasNotifier>();
    final session = notifier.session;
    if (session == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
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

        // Ensure image layers are cached
        for (final layer in session.layers) {
          _ensureImageCached(layer);
        }

        // Build/invalidate layer raster cache
        _updateLayerRasterCache(session.layers, session.activeLayerId);

        // Build pending text stroke for live preview
        PaintStroke? pendingTextStroke;
        if (notifier.hasPendingText && notifier.pendingTextContent.isNotEmpty) {
          pendingTextStroke = PaintStroke(
            points: [notifier.pendingTextPosition!],
            radius: 0,
            colorValue: notifier.brushColor,
            opacity: notifier.brushOpacity,
            strokeType: StrokeType.text,
            text: notifier.pendingTextContent,
            fontSize: notifier.pendingTextFontSize,
            fontFamily: notifier.pendingTextFontFamily,
            letterSpacing: notifier.pendingTextLetterSpacing,
          );
        }

        // Whether pan mode is active (Space held or middle-mouse)
        final isPanMode = _spaceHeld || _middleMouseHeld;

        return KeyboardListener(
          focusNode: _keyboardFocusNode,
          onKeyEvent: (event) {
            if (event.logicalKey == LogicalKeyboardKey.space) {
              setState(() => _spaceHeld = event is KeyDownEvent);
            }
          },
          child: Stack(
            children: [
              Listener(
                onPointerDown: (event) {
                  if (event.buttons & kMiddleMouseButton != 0) {
                    setState(() => _middleMouseHeld = true);
                  }
                },
                onPointerUp: (event) {
                  if (_middleMouseHeld) setState(() => _middleMouseHeld = false);
                },
                onPointerCancel: (event) {
                  if (_middleMouseHeld) setState(() => _middleMouseHeld = false);
                },
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
                    scaleEnabled: false, // we handle zoom via scroll wheel
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: 0.25,
                    maxScale: 16.0,
                    child: GestureDetector(
                      onTapUp: isPanMode
                          ? null
                          : (details) => _onTapUp(details, notifier),
                      onPanStart: isPanMode
                          ? null
                          : (details) => _onPanStart(details, notifier),
                      onPanUpdate: isPanMode
                          ? null
                          : (details) => _onPanUpdate(details, notifier),
                      onPanEnd: isPanMode
                          ? null
                          : (_) => _onPanEnd(notifier),
                      onScaleStart: !isPanMode ? null : (_) {},
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

                            // Paint overlay — per-layer compositing + pending text preview
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _CanvasPaintOverlayPainter(
                                  layers: session.layers,
                                  activeLayerId: session.activeLayerId,
                                  activeStroke: notifier.activeStroke,
                                  pendingTextStroke: pendingTextStroke,
                                  imageRect: _imageRect,
                                  imageCache: _imageLayerCache,
                                  layerRasterCache: _layerRasterCache,
                                ),
                              ),
                            ),

                            // Selection overlay (marching ants + handles)
                            if (notifier.hasSelection)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _SelectionOverlayPainter(
                                    selection: notifier.activeSelection!,
                                    imageRect: _imageRect,
                                  ),
                                ),
                              ),

                            // Blinking text cursor
                            if (notifier.hasPendingText)
                              _BlinkingTextCursor(
                                normalizedPosition: notifier.pendingTextPosition!,
                                currentText: notifier.pendingTextContent,
                                fontSizeNormalized: notifier.pendingTextFontSize,
                                fontFamily: notifier.pendingTextFontFamily,
                                letterSpacing: notifier.pendingTextLetterSpacing,
                                imageRect: _imageRect,
                                color: notifier.brushColorAsColor,
                              ),

                            // Cursor preview
                            Positioned.fill(
                              child: _CanvasCursorPreview(
                                brushRadius: notifier.brushRadius,
                                tool: notifier.tool,
                                brushColor: notifier.brushColorAsColor,
                                imageRect: _imageRect,
                                zoomController: _zoomController,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Inline text editor — outside the canvas GestureDetector so
              // button taps are not stolen by the pan recognizer.
              if (notifier.hasPendingText)
                _buildInlineTextEditor(notifier),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInlineTextEditor(CanvasNotifier notifier) {
    final t = context.t;
    final l = context.l;
    final pos = notifier.pendingTextPosition!;

    // Convert normalized position to screen position
    final screenX = _imageRect.left + pos.dx * _imageRect.width;
    final screenY = _imageRect.top + pos.dy * _imageRect.height;

    // Clamp so the editor doesn't overflow outside the image rect
    final editorWidth = 220.0.clamp(0.0, _imageRect.width - 16);
    const editorHeight = 40.0;
    final clampedX = screenX.clamp(_imageRect.left, _imageRect.right - editorWidth);
    final keyboardTop = MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom;
    final maxY = (keyboardTop - editorHeight - 8).clamp(_imageRect.top, _imageRect.bottom - editorHeight);
    final clampedY = (screenY - editorHeight - 8).clamp(_imageRect.top, maxY);

    return Positioned(
      left: clampedX,
      top: clampedY,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        color: t.surfaceHigh,
        child: Container(
          width: editorWidth,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: t.accentEdit, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: KeyboardListener(
                  focusNode: _textKeyboardFocusNode,
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                      notifier.cancelPendingText();
                      _textController.clear();
                    }
                  },
                  child: TextField(
                    controller: _textController,
                    focusNode: _textFocusNode,
                    autofocus: true,
                    style: TextStyle(color: t.textPrimary, fontSize: t.fontSize(9)),
                    decoration: InputDecoration(
                      hintText: l.canvasTextHint,
                      hintStyle: TextStyle(color: t.textMinimal, fontSize: t.fontSize(9)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      border: InputBorder.none,
                    ),
                    onChanged: notifier.updatePendingText,
                    onSubmitted: (_) {
                      notifier.commitPendingText();
                      _textController.clear();
                    },
                  ),
                ),
              ),
              // Confirm button
              GestureDetector(
                onTap: () {
                  notifier.commitPendingText();
                  _textController.clear();
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.check, size: 16, color: t.accentEdit),
                ),
              ),
              // Cancel button
              GestureDetector(
                onTap: () {
                  notifier.cancelPendingText();
                  _textController.clear();
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: t.textDisabled),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onPointerSignal(PointerScrollEvent event, CanvasNotifier notifier) {
    final keyboard = HardwareKeyboard.instance;
    final ctrlHeld = keyboard.isControlPressed || keyboard.isMetaPressed;
    final altHeld = keyboard.isAltPressed;

    if (ctrlHeld) {
      // Ctrl + scroll: adjust brush size
      final delta = event.scrollDelta.dy > 0 ? -0.003 : 0.003;
      notifier.setBrushRadius(notifier.brushRadius + delta);
    } else if (altHeld) {
      // Alt + scroll: adjust opacity
      final delta = event.scrollDelta.dy > 0 ? -0.05 : 0.05;
      notifier.setBrushOpacity(notifier.brushOpacity + delta);
    } else {
      // Plain scroll: zoom in/out centered on cursor
      final zoomFactor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
      final focalPoint = event.localPosition;
      final matrix = _zoomController.value.clone();
      // Translate to focal point, scale, translate back
      // ignore: deprecated_member_use
      matrix.translate(focalPoint.dx, focalPoint.dy);
      // ignore: deprecated_member_use
      matrix.scale(zoomFactor, zoomFactor);
      // ignore: deprecated_member_use
      matrix.translate(-focalPoint.dx, -focalPoint.dy);
      _zoomController.value = matrix;
    }
  }

  void _onTapUp(TapUpDetails details, CanvasNotifier notifier) {
    if (!_imageRect.contains(details.localPosition)) return;
    final normalized = _toNormalized(details.localPosition);
    if (normalized == null) return;

    if (notifier.tool == CanvasTool.eyedropper) {
      _samplePixel(normalized, notifier);
    } else if (notifier.tool == CanvasTool.fill) {
      notifier.applyFill(normalized);
    } else if (notifier.tool == CanvasTool.cloneStamp) {
      // Alt+tap or first tap sets clone source
      final altHeld = HardwareKeyboard.instance.isAltPressed;
      if (altHeld || notifier.cloneSourcePoint == null) {
        notifier.setCloneSource(normalized);
      }
    } else if (notifier.tool == CanvasTool.text) {
      if (notifier.hasPendingText) {
        notifier.commitPendingText();
        _textController.clear();
      }
      notifier.beginTextEditing(normalized);
      _textController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _textFocusNode.requestFocus();
      });
    }
  }

  void _onPanStart(DragStartDetails details, CanvasNotifier notifier) {
    if (!_imageRect.contains(details.localPosition)) return;
    final normalized = _toNormalized(details.localPosition);
    if (normalized == null) return;

    if (notifier.tool == CanvasTool.eyedropper) {
      _samplePixel(normalized, notifier);
    } else if (notifier.tool == CanvasTool.fill) {
      notifier.applyFill(normalized);
    } else if (notifier.tool == CanvasTool.text) {
      // If there's already a pending text, commit it first
      if (notifier.hasPendingText) {
        notifier.commitPendingText();
        _textController.clear();
      }
      notifier.beginTextEditing(normalized);
      _textController.clear();
      // Re-focus the text field after a frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _textFocusNode.requestFocus();
      });
    } else if (notifier.tool == CanvasTool.select) {
      if (notifier.hasSelection) {
        // Hit test handles on existing selection
        final handleRadius = 0.02;
        final handle = notifier.activeSelection!.hitTestHandle(normalized, handleRadius);
        if (handle != null) {
          notifier.beginSelectionDrag(handle, normalized);
        } else {
          // Start new selection
          notifier.beginSelection(normalized);
        }
      } else {
        notifier.beginSelection(normalized);
      }
    } else if (notifier.tool == CanvasTool.lasso) {
      if (notifier.hasSelection) {
        final handleRadius = 0.02;
        final handle = notifier.activeSelection!.hitTestHandle(normalized, handleRadius);
        if (handle != null) {
          notifier.beginSelectionDrag(handle, normalized);
        } else {
          notifier.beginLassoSelection(normalized);
        }
      } else {
        notifier.beginLassoSelection(normalized);
      }
    } else {
      notifier.beginStroke(normalized);
    }
  }

  void _onPanUpdate(DragUpdateDetails details, CanvasNotifier notifier) {
    final normalized = _toNormalized(details.localPosition);
    if (normalized == null) return;

    if (notifier.tool == CanvasTool.select) {
      if (notifier.activeSelection != null && notifier.activeSelection!.normalizedRect.width > 0.005) {
        notifier.updateSelectionDrag(normalized);
      } else {
        notifier.updateSelectionRect(normalized);
      }
    } else if (notifier.tool == CanvasTool.lasso) {
      if (notifier.activeSelection?.clipPath != null &&
          notifier.activeSelection!.normalizedRect.width > 0.005 &&
          notifier.activeSelection!.clipPath!.length > 2) {
        notifier.updateSelectionDrag(normalized);
      } else {
        notifier.addLassoPoint(normalized);
      }
    } else {
      notifier.addStrokePoint(normalized);
    }
  }

  void _onPanEnd(CanvasNotifier notifier) {
    if (notifier.tool == CanvasTool.select) {
      if (notifier.hasSelection) {
        notifier.endSelectionDrag();
        notifier.endSelectionRect();
      }
    } else if (notifier.tool == CanvasTool.lasso) {
      if (notifier.hasSelection) {
        notifier.endSelectionDrag();
        notifier.endLassoSelection();
      }
    } else {
      notifier.endStroke();
    }
  }

  Offset? _toNormalized(Offset localPosition) {
    if (_imageRect.width <= 0 || _imageRect.height <= 0) return null;
    // localPosition from GestureDetector inside InteractiveViewer is already
    // in the child's untransformed coordinate space (Flutter hit testing applies
    // the inverse transform automatically), so no manual inversion is needed.
    final x = (localPosition.dx - _imageRect.left) / _imageRect.width;
    final y = (localPosition.dy - _imageRect.top) / _imageRect.height;
    return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
  }

  void _samplePixel(Offset normalized, CanvasNotifier notifier) {
    final session = notifier.session;
    if (session == null) return;

    try {
      final decoded = img.decodeImage(session.sourceImageBytes);
      if (decoded == null) return;

      final px = (normalized.dx * (decoded.width - 1)).round().clamp(0, decoded.width - 1);
      final py = (normalized.dy * (decoded.height - 1)).round().clamp(0, decoded.height - 1);
      final pixel = decoded.getPixel(px, py);

      final r = pixel.r.toInt().clamp(0, 255);
      final g = pixel.g.toInt().clamp(0, 255);
      final b = pixel.b.toInt().clamp(0, 255);
      final colorValue = (0xFF << 24) | (r << 16) | (g << 8) | b;

      notifier.pickColorFromCanvas(colorValue);
    } catch (_) {
      // Silently fail if decoding fails
    }
  }
}

/// Paints smooth anti-aliased strokes per-layer with blend mode + opacity compositing.
/// Also renders image layers with transform.
class _CanvasPaintOverlayPainter extends CustomPainter {
  final List<CanvasLayer> layers;
  final String activeLayerId;
  final PaintStroke? activeStroke;
  final PaintStroke? pendingTextStroke;
  final Rect imageRect;
  final Map<String, ui.Image> imageCache;
  final Map<String, ui.Image> layerRasterCache;

  _CanvasPaintOverlayPainter({
    required this.layers,
    required this.activeLayerId,
    this.activeStroke,
    this.pendingTextStroke,
    required this.imageRect,
    this.imageCache = const {},
    this.layerRasterCache = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageRect.isEmpty) return;

    // Clip all paint to image bounds
    canvas.save();
    canvas.clipRect(imageRect);

    // Iterate layers bottom-to-top
    for (final layer in layers) {
      if (!layer.visible) continue;

      // Check raster cache for non-active layers
      final cachedRaster = layerRasterCache[layer.id];
      if (cachedRaster != null && layer.id != activeLayerId) {
        // Draw cached layer as a pre-rendered image with blend mode + opacity
        canvas.saveLayer(
          null,
          Paint()
            ..blendMode = layer.blendMode.toFlutterBlendMode()
            ..color = Color.fromARGB(
                (layer.opacity * 255).round(), 255, 255, 255),
        );
        canvas.drawImage(cachedRaster, Offset.zero, Paint());
        canvas.restore();
        continue;
      }

      final layerStrokes = [
        ...layer.strokes,
        if (layer.id == activeLayerId && activeStroke != null) activeStroke!,
      ];
      if (layerStrokes.isEmpty) continue;

      // Save layer with blend mode and opacity
      canvas.saveLayer(
        null,
        Paint()
          ..blendMode = layer.blendMode.toFlutterBlendMode()
          ..color = Color.fromARGB(
              (layer.opacity * 255).round(), 255, 255, 255),
      );

      // Draw image layer content first (if present)
      if (layer.isImageLayer) {
        final cached = imageCache[layer.id];
        if (cached != null) {
          canvas.save();
          final imgW = cached.width.toDouble();
          final imgH = cached.height.toDouble();
          // Compute destination rect based on normalized transform
          final scale = layer.imageScale * imageRect.width / imgW;
          final dx = imageRect.left + layer.imageX * imageRect.width;
          final dy = imageRect.top + layer.imageY * imageRect.height;
          canvas.translate(dx + imgW * scale / 2, dy + imgH * scale / 2);
          canvas.rotate(layer.imageRotation);
          canvas.translate(-imgW * scale / 2, -imgH * scale / 2);
          canvas.drawImageRect(
            cached,
            Rect.fromLTWH(0, 0, imgW, imgH),
            Rect.fromLTWH(0, 0, imgW * scale, imgH * scale),
            Paint(),
          );
          canvas.restore();
        }
      }

      for (final stroke in layerStrokes) {
        _drawStroke(canvas, stroke);
      }

      canvas.restore();
    }

    // Draw pending text preview on top of all layers
    if (pendingTextStroke != null) {
      _drawStroke(canvas, pendingTextStroke!);
    }

    canvas.restore();
  }

  void _drawStroke(Canvas canvas, PaintStroke stroke) {
    if (stroke.isErase) {
      final erasePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.radius * 2 * imageRect.width
        ..isAntiAlias = true
        ..blendMode = ui.BlendMode.dstOut
        ..color = const Color(0xFFFFFFFF);

      final path = stroke.smooth ? _buildSmoothPath(stroke) : _buildPath(stroke);
      canvas.drawPath(path, erasePaint);
    } else {
      final strokeColor =
          Color(stroke.colorValue).withValues(alpha: stroke.opacity);
      final paintBrush = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.radius * 2 * imageRect.width
        ..isAntiAlias = true
        ..color = strokeColor;

      switch (stroke.strokeType) {
        case StrokeType.fill:
          final fillPaint = Paint()
            ..color = strokeColor
            ..style = PaintingStyle.fill;
          canvas.drawRect(imageRect, fillPaint);

        case StrokeType.line:
          if (stroke.points.length >= 2) {
            final p1 = _toScreen(stroke.points.first);
            final p2 = _toScreen(stroke.points.last);
            canvas.drawLine(p1, p2, paintBrush);
          } else if (stroke.points.length == 1) {
            final p = _toScreen(stroke.points.first);
            canvas.drawLine(p, Offset(p.dx + 0.1, p.dy + 0.1), paintBrush);
          }

        case StrokeType.rectangle:
          if (stroke.points.length >= 2) {
            final p1 = _toScreen(stroke.points.first);
            final p2 = _toScreen(stroke.points.last);
            canvas.drawRect(Rect.fromPoints(p1, p2), paintBrush);
          }

        case StrokeType.circle:
          if (stroke.points.length >= 2) {
            final p1 = _toScreen(stroke.points.first);
            final p2 = _toScreen(stroke.points.last);
            canvas.drawOval(Rect.fromPoints(p1, p2), paintBrush);
          }

        case StrokeType.text:
          if (stroke.text != null && stroke.points.isNotEmpty) {
            final pos = _toScreen(stroke.points.first);
            final textFontSize =
                (stroke.fontSize ?? 0.05) * imageRect.height;
            final textLetterSpacing =
                (stroke.letterSpacing ?? 0.0) * imageRect.height;
            final style = _buildFontStyle(
              color: strokeColor,
              fontSize: textFontSize,
              fontFamily: stroke.fontFamily,
              letterSpacing: textLetterSpacing,
            );
            final textPainter = TextPainter(
              text: TextSpan(text: stroke.text, style: style),
              textDirection: TextDirection.ltr,
            )..layout();
            textPainter.paint(canvas, pos);
          }

        case StrokeType.blur:
          // Render blur path as a semi-transparent highlight to show the blurred region
          final blurPath = stroke.smooth ? _buildSmoothPath(stroke) : _buildPath(stroke);
          final blurPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = stroke.radius * 2 * imageRect.width
            ..isAntiAlias = true
            ..color = const Color(0x30FFFFFF)
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: stroke.blurSigma ?? 5.0,
              sigmaY: stroke.blurSigma ?? 5.0,
            );
          canvas.drawPath(blurPath, blurPaint);

        case StrokeType.cloneStamp:
          // Render clone stamp path as a semi-transparent indicator
          final clonePath = stroke.smooth ? _buildSmoothPath(stroke) : _buildPath(stroke);
          final clonePaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = stroke.radius * 2 * imageRect.width
            ..isAntiAlias = true
            ..color = const Color(0x4000BCD4);
          canvas.drawPath(clonePath, clonePaint);

        case StrokeType.freehand:
          final path = stroke.smooth ? _buildSmoothPath(stroke) : _buildPath(stroke);
          canvas.drawPath(path, paintBrush);
      }
    }
  }

  Path _buildPath(PaintStroke stroke) {
    final path = Path();
    if (stroke.points.isEmpty) return path;

    final first = _toScreen(stroke.points.first);
    path.moveTo(first.dx, first.dy);

    if (stroke.points.length == 1) {
      // Single dot: draw a tiny line so stroke cap renders
      path.lineTo(first.dx + 0.1, first.dy + 0.1);
    } else {
      for (int i = 1; i < stroke.points.length; i++) {
        final p = _toScreen(stroke.points[i]);
        path.lineTo(p.dx, p.dy);
      }
    }

    return path;
  }

  Path _buildSmoothPath(PaintStroke stroke) {
    final path = Path();
    if (stroke.points.isEmpty) return path;

    final pts = stroke.points.map(_toScreen).toList();
    path.moveTo(pts.first.dx, pts.first.dy);

    if (pts.length == 1) {
      path.lineTo(pts.first.dx + 0.1, pts.first.dy + 0.1);
    } else if (pts.length == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
    } else {
      // Quadratic bezier through midpoints for C1 continuity
      for (int i = 0; i < pts.length - 1; i++) {
        final current = pts[i];
        final next = pts[i + 1];
        final midX = (current.dx + next.dx) / 2;
        final midY = (current.dy + next.dy) / 2;

        if (i == 0) {
          path.quadraticBezierTo(current.dx, current.dy, midX, midY);
        } else {
          path.quadraticBezierTo(current.dx, current.dy, midX, midY);
        }
      }
      path.lineTo(pts.last.dx, pts.last.dy);
    }

    return path;
  }

  Offset _toScreen(Offset normalized) {
    return Offset(
      imageRect.left + normalized.dx * imageRect.width,
      imageRect.top + normalized.dy * imageRect.height,
    );
  }

  @override
  bool shouldRepaint(_CanvasPaintOverlayPainter oldDelegate) =>
      layers != oldDelegate.layers ||
      activeLayerId != oldDelegate.activeLayerId ||
      activeStroke != oldDelegate.activeStroke ||
      pendingTextStroke != oldDelegate.pendingTextStroke ||
      imageRect != oldDelegate.imageRect ||
      imageCache != oldDelegate.imageCache;
}

/// Shows a circular brush outline following the mouse position.
class _CanvasCursorPreview extends StatefulWidget {
  final double brushRadius;
  final CanvasTool tool;
  final Color brushColor;
  final Rect imageRect;
  final TransformationController? zoomController;

  const _CanvasCursorPreview({
    required this.brushRadius,
    required this.tool,
    required this.brushColor,
    required this.imageRect,
    this.zoomController,
  });

  @override
  State<_CanvasCursorPreview> createState() => _CanvasCursorPreviewState();
}

class _CanvasCursorPreviewState extends State<_CanvasCursorPreview> {
  Offset? _mousePosition;

  @override
  void initState() {
    super.initState();
    widget.zoomController?.addListener(_onZoomChanged);
  }

  @override
  void didUpdateWidget(_CanvasCursorPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoomController != widget.zoomController) {
      oldWidget.zoomController?.removeListener(_onZoomChanged);
      widget.zoomController?.addListener(_onZoomChanged);
    }
  }

  @override
  void dispose() {
    widget.zoomController?.removeListener(_onZoomChanged);
    super.dispose();
  }

  void _onZoomChanged() {
    // Clear stale cursor position when zoom/pan changes so it re-syncs
    // on the next mouse move event
    if (_mousePosition != null) {
      setState(() => _mousePosition = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      hitTestBehavior: HitTestBehavior.translucent,
      onHover: (event) => setState(() => _mousePosition = event.localPosition),
      onExit: (_) => setState(() => _mousePosition = null),
      child: CustomPaint(
        painter: _CanvasCursorPainter(
          position: _mousePosition,
          radius: widget.brushRadius * widget.imageRect.width,
          tool: widget.tool,
          brushColor: widget.brushColor,
        ),
      ),
    );
  }
}

class _CanvasCursorPainter extends CustomPainter {
  final Offset? position;
  final double radius;
  final CanvasTool tool;
  final Color brushColor;

  _CanvasCursorPainter({
    this.position,
    required this.radius,
    required this.tool,
    required this.brushColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (position == null) return;

    if (tool == CanvasTool.eyedropper || tool == CanvasTool.fill || tool == CanvasTool.text ||
        tool == CanvasTool.select || tool == CanvasTool.lasso) {
      // Eyedropper / Fill / Text: crosshair only (no circle outline)
      final crossPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5;
      const len = 8.0;
      canvas.drawLine(
        Offset(position!.dx - len, position!.dy),
        Offset(position!.dx + len, position!.dy),
        crossPaint,
      );
      canvas.drawLine(
        Offset(position!.dx, position!.dy - len),
        Offset(position!.dx, position!.dy + len),
        crossPaint,
      );
      // Dark outline for visibility
      final outlinePaint = Paint()
        ..color = Colors.black54
        ..strokeWidth = 0.5;
      canvas.drawLine(
        Offset(position!.dx - len, position!.dy),
        Offset(position!.dx + len, position!.dy),
        outlinePaint,
      );
      canvas.drawLine(
        Offset(position!.dx, position!.dy - len),
        Offset(position!.dx, position!.dy + len),
        outlinePaint,
      );
      return;
    }

    if (radius <= 0) return;

    final outlinePaint = Paint()
      ..color = tool == CanvasTool.erase
          ? Colors.white70
          : brushColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(position!, radius, outlinePaint);

    // Small crosshair at center
    final crossPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(position!.dx - 4, position!.dy),
      Offset(position!.dx + 4, position!.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(position!.dx, position!.dy - 4),
      Offset(position!.dx, position!.dy + 4),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(_CanvasCursorPainter oldDelegate) =>
      position != oldDelegate.position ||
      radius != oldDelegate.radius ||
      tool != oldDelegate.tool ||
      brushColor != oldDelegate.brushColor;
}

/// A blinking vertical cursor line shown on the canvas at the text insertion point.
class _BlinkingTextCursor extends StatefulWidget {
  final Offset normalizedPosition;
  final String currentText;
  final double fontSizeNormalized;
  final String? fontFamily;
  final double letterSpacing;
  final Rect imageRect;
  final Color color;

  const _BlinkingTextCursor({
    required this.normalizedPosition,
    required this.currentText,
    required this.fontSizeNormalized,
    required this.fontFamily,
    required this.letterSpacing,
    required this.imageRect,
    required this.color,
  });

  @override
  State<_BlinkingTextCursor> createState() => _BlinkingTextCursorState();
}

class _BlinkingTextCursorState extends State<_BlinkingTextCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = widget.fontSizeNormalized * widget.imageRect.height;
    final letterSpacing = widget.letterSpacing * widget.imageRect.height;

    // Measure current text width to position cursor at end
    double textWidth = 0;
    if (widget.currentText.isNotEmpty) {
      final style = _buildFontStyle(
        color: widget.color,
        fontSize: fontSize,
        fontFamily: widget.fontFamily,
        letterSpacing: letterSpacing,
      );
      final textPainter = TextPainter(
        text: TextSpan(text: widget.currentText, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      textWidth = textPainter.width;
    }

    final screenX = widget.imageRect.left +
        widget.normalizedPosition.dx * widget.imageRect.width +
        textWidth;
    final screenY = widget.imageRect.top +
        widget.normalizedPosition.dy * widget.imageRect.height;

    final cursorHeight = fontSize.clamp(8.0, 200.0);

    return Positioned(
      left: screenX,
      top: screenY,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, _) => Opacity(
            opacity: _controller.value > 0.5 ? 1.0 : 0.0,
            child: Container(
              width: 2,
              height: cursorHeight,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the selection overlay: dashed rectangle (or lasso path),
/// corner handles, and rotation handle.
class _SelectionOverlayPainter extends CustomPainter {
  final CanvasSelection selection;
  final Rect imageRect;

  _SelectionOverlayPainter({required this.selection, required this.imageRect});

  Offset _toScreen(Offset normalized) => Offset(
    imageRect.left + normalized.dx * imageRect.width,
    imageRect.top + normalized.dy * imageRect.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (imageRect.isEmpty) return;

    final r = selection.transformedRect;
    final screenRect = Rect.fromLTRB(
      _toScreen(r.topLeft).dx, _toScreen(r.topLeft).dy,
      _toScreen(r.bottomRight).dx, _toScreen(r.bottomRight).dy,
    );

    // Dashed border (marching ants effect)
    final dashPaintWhite = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final dashPaintBlack = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw lasso path if available
    if (selection.clipPath != null && selection.clipPath!.length > 2) {
      final path = Path();
      final first = _toScreen(selection.clipPath!.first);
      path.moveTo(first.dx, first.dy);
      for (int i = 1; i < selection.clipPath!.length; i++) {
        final p = _toScreen(selection.clipPath![i]);
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, dashPaintBlack);
      canvas.drawPath(path, dashPaintWhite);
    } else {
      // Draw rectangle
      canvas.drawRect(screenRect, dashPaintBlack);
      canvas.drawRect(screenRect, dashPaintWhite);
    }

    // Semi-transparent fill
    final fillPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRect(screenRect, fillPaint);

    // Corner handles
    const handleSize = 6.0;
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final handleBorder = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final corner in [
      screenRect.topLeft,
      screenRect.topRight,
      screenRect.bottomLeft,
      screenRect.bottomRight,
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: handleSize * 2, height: handleSize * 2),
        handlePaint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: handleSize * 2, height: handleSize * 2),
        handleBorder,
      );
    }

    // Rotation handle (circle above top center)
    final rotCenter = Offset(screenRect.center.dx, screenRect.top - 20);
    canvas.drawCircle(rotCenter, 5, handlePaint);
    canvas.drawCircle(rotCenter, 5, handleBorder);
    // Line connecting to top center
    canvas.drawLine(
      Offset(screenRect.center.dx, screenRect.top),
      rotCenter,
      Paint()..color = Colors.black..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_SelectionOverlayPainter oldDelegate) =>
      selection != oldDelegate.selection ||
      imageRect != oldDelegate.imageRect;
}
