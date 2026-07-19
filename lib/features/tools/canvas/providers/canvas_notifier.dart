import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/canvas_action.dart';
import '../models/canvas_layer.dart';
import '../models/canvas_selection.dart';
import '../models/canvas_session.dart';
import '../models/paint_stroke.dart';
import '../services/canvas_flatten_service.dart';
import '../services/flood_fill.dart';
import '../services/selection_geometry.dart';
import '../widgets/canvas_color_picker.dart';

/// Parameters for source image resize in isolate.
class _ResizeParams {
  final Uint8List sourceBytes;
  final int newWidth;
  final int newHeight;
  final int anchorOffsetX;
  final int anchorOffsetY;
  _ResizeParams({
    required this.sourceBytes,
    required this.newWidth,
    required this.newHeight,
    required this.anchorOffsetX,
    required this.anchorOffsetY,
  });
}

/// Resize source image in an isolate: create a new image at the target
/// dimensions and composite the original at the anchor offset.
Uint8List _resizeSourceImage(_ResizeParams p) {
  final decoded = img.decodeImage(p.sourceBytes);
  if (decoded == null) return p.sourceBytes;

  final newImage = img.Image(width: p.newWidth, height: p.newHeight);
  // Fill with black (transparent would work too but black is safer for generation)
  img.fill(newImage, color: img.ColorRgba8(0, 0, 0, 255));

  // Composite the original image at the anchor offset
  img.compositeImage(newImage, decoded, dstX: p.anchorOffsetX, dstY: p.anchorOffsetY);

  return Uint8List.fromList(img.encodePng(newImage));
}

/// Parameters for sampling a pixel from PNG bytes in an isolate.
class _SampleParams {
  final Uint8List pngBytes;
  final double nx;
  final double ny;
  _SampleParams({required this.pngBytes, required this.nx, required this.ny});
}

/// Decode PNG bytes and return the ARGB color at the normalized position.
int? _samplePixelFromPng(_SampleParams p) {
  final decoded = img.decodeImage(p.pngBytes);
  if (decoded == null) return null;
  final px = (p.nx * (decoded.width - 1)).round().clamp(0, decoded.width - 1);
  final py = (p.ny * (decoded.height - 1)).round().clamp(0, decoded.height - 1);
  final pixel = decoded.getPixel(px, py);
  final r = pixel.r.toInt().clamp(0, 255);
  final g = pixel.g.toInt().clamp(0, 255);
  final b = pixel.b.toInt().clamp(0, 255);
  return (0xFF << 24) | (r << 16) | (g << 8) | b;
}

/// Tool mode for the canvas editor.
enum CanvasTool { paint, erase, line, rectangle, circle, fill, text, eyedropper, transform, select, lasso, blur, cloneStamp }

/// Manages a canvas editing session: layer CRUD, stroke lifecycle,
/// action-based undo/redo, brush settings.
class CanvasNotifier extends ChangeNotifier {
  CanvasSession? _session;
  CanvasSession? get session => _session;
  bool get hasSession => _session != null;

  // --- Source image dominant colors ---
  List<Color> _sourceImageColors = [];
  List<Color> get sourceImageColors => _sourceImageColors;

  // --- Brush settings ---
  CanvasTool _tool = CanvasTool.paint;
  double _brushRadius = 0.02;
  double _brushOpacity = 1.0;
  int _brushColor = 0xFF000000; // default black

  CanvasTool get tool => _tool;
  double get brushRadius => _brushRadius;
  double get brushOpacity => _brushOpacity;
  int get brushColor => _brushColor;
  Color get brushColorAsColor => Color(_brushColor);

  // --- Smooth strokes ---
  bool _smoothStrokes = true;
  bool get smoothStrokes => _smoothStrokes;

  // --- Persistent text-tool settings ---
  double _pendingTextFontSize = 0.05;
  String? _pendingTextFontFamily;
  double _pendingTextLetterSpacing = 0.0;

  double get pendingTextFontSize => _pendingTextFontSize;
  String? get pendingTextFontFamily => _pendingTextFontFamily;
  double get pendingTextLetterSpacing => _pendingTextLetterSpacing;

  void setPendingTextFontSize(double size) {
    _pendingTextFontSize = size.clamp(0.01, 0.20);
    notifyListeners();
  }

  void setPendingTextFontFamily(String? family) {
    _pendingTextFontFamily = family;
    notifyListeners();
  }

  void setPendingTextLetterSpacing(double spacing) {
    _pendingTextLetterSpacing = spacing.clamp(-0.01, 0.05);
    notifyListeners();
  }

  // --- Pending text editing state ---
  Offset? _pendingTextPosition; // normalized tap position
  String _pendingTextContent = '';

  Offset? get pendingTextPosition => _pendingTextPosition;
  String get pendingTextContent => _pendingTextContent;
  bool get hasPendingText => _pendingTextPosition != null;

  void beginTextEditing(Offset normalizedPos) {
    _pendingTextPosition = normalizedPos;
    _pendingTextContent = '';
    notifyListeners();
  }

  void updatePendingText(String text) {
    _pendingTextContent = text;
    notifyListeners();
  }

  void commitPendingText() {
    if (_pendingTextPosition == null || _pendingTextContent.trim().isEmpty) {
      cancelPendingText();
      return;
    }
    addTextStroke(
      position: _pendingTextPosition!,
      text: _pendingTextContent.trim(),
      fontSize: _pendingTextFontSize,
      fontFamily: _pendingTextFontFamily,
      letterSpacing: _pendingTextLetterSpacing,
    );
    _pendingTextPosition = null;
    _pendingTextContent = '';
    notifyListeners();
  }

  void cancelPendingText() {
    _pendingTextPosition = null;
    _pendingTextContent = '';
    notifyListeners();
  }

  // --- Eyedropper state ---
  CanvasTool? _previousToolBeforeEyedropper;
  bool _isSamplingColor = false;

  /// Samples the color under [normalized] from the *composited* canvas —
  /// source image plus visible layers — so the eyedropper sees painted
  /// strokes, not just the original pixels (#23). Text strokes are rendered
  /// as UI overlays at flatten time and are not part of the CPU composite,
  /// so they are not sampled.
  Future<void> pickColorAtPoint(Offset normalized) async {
    if (_session == null || _isSamplingColor) return;
    _isSamplingColor = true;
    try {
      final visibleLayers =
          _session!.layers.where((l) => l.visible).toList();
      final Uint8List flattened;
      if (visibleLayers.any((l) => l.strokes.isNotEmpty || l.isImageLayer)) {
        flattened = await CanvasFlattenService.flatten(
          sourceBytes: _session!.sourceImageBytes,
          sourceWidth: _session!.sourceWidth,
          sourceHeight: _session!.sourceHeight,
          visibleLayers: visibleLayers,
        );
      } else {
        flattened = _session!.sourceImageBytes;
      }
      final color = await compute(
        _samplePixelFromPng,
        _SampleParams(
            pngBytes: flattened, nx: normalized.dx, ny: normalized.dy),
      );
      if (color != null) pickColorFromCanvas(color);
    } catch (e) {
      debugPrint('Eyedropper sampling failed: $e');
    } finally {
      _isSamplingColor = false;
    }
  }

  // --- Blur tool ---
  double _blurSigma = 5.0;
  double get blurSigma => _blurSigma;
  void setBlurSigma(double sigma) {
    _blurSigma = sigma.clamp(1.0, 30.0);
    notifyListeners();
  }

  // --- Clone stamp ---
  Offset? _cloneSourcePoint;
  Offset? get cloneSourcePoint => _cloneSourcePoint;
  void setCloneSource(Offset normalizedPoint) {
    _cloneSourcePoint = normalizedPoint;
    notifyListeners();
  }

  // --- Active stroke (in-progress) ---
  List<Offset>? _currentStrokePoints;

  int _nextLayerNumber = 2;

  /// Start a new canvas session from source image bytes.
  void startSession(Uint8List sourceBytes, int width, int height) {
    const defaultLayerId = 'layer_1';
    final defaultLayer = CanvasLayer(
      id: defaultLayerId,
      name: 'Layer 1',
    );
    _nextLayerNumber = 2;
    _activeSelection = null;
    _session = CanvasSession(
      sourceImageBytes: sourceBytes,
      sourceWidth: width,
      sourceHeight: height,
      layers: [defaultLayer],
      activeLayerId: defaultLayerId,
      sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    _extractSourceColors(sourceBytes);
    notifyListeners();
  }

  /// Restore a session (e.g. from persistence), preserving history.
  void restoreSession(CanvasSession session) {
    _session = session;
    // Determine next layer number from existing names
    _nextLayerNumber = 1;
    for (final layer in session.layers) {
      final match = RegExp(r'^Layer (\d+)').firstMatch(layer.name);
      if (match != null) {
        final num = int.parse(match.group(1)!);
        if (num >= _nextLayerNumber) _nextLayerNumber = num + 1;
      }
    }
    _extractSourceColors(session.sourceImageBytes);
    notifyListeners();
  }

  void clearSession() {
    _session = null;
    _currentStrokePoints = null;
    _pendingTextPosition = null;
    _pendingTextContent = '';
    _sourceImageColors = [];
    _activeSelection = null;
    _dragHandle = null;
    _dragStartPoint = null;
    notifyListeners();
  }

  /// Extract dominant colors from the source image in a background isolate.
  void _extractSourceColors(Uint8List sourceBytes) {
    _sourceImageColors = [];
    extractDominantColors(sourceBytes, count: 8).then((colors) {
      _sourceImageColors = colors;
      notifyListeners();
    }).catchError((e) {
      debugPrint('Color extraction failed: $e');
    });
  }

  // --- Tool selection ---

  void setTool(CanvasTool tool) {
    if (tool == CanvasTool.eyedropper) {
      _previousToolBeforeEyedropper = _tool;
    }
    _tool = tool;
    notifyListeners();
  }

  void toggleSmoothStrokes() {
    _smoothStrokes = !_smoothStrokes;
    notifyListeners();
  }

  void pickColorFromCanvas(int colorValue) {
    _brushColor = colorValue;
    // Switch back to previous tool
    _tool = _previousToolBeforeEyedropper ?? CanvasTool.paint;
    _previousToolBeforeEyedropper = null;
    notifyListeners();
  }

  static const double _maxBrushRadiusFraction = 0.15;

  /// Radius floor: half a source pixel, i.e. a 1px-diameter brush (#16 —
  /// the old floor was 0.2% of image width, far too coarse for fine detail).
  /// Falls back to the old floor when no session is open.
  double get minBrushRadius =>
      _session != null ? 0.5 / _session!.sourceWidth : 0.002;
  double get maxBrushRadius => _maxBrushRadiusFraction;

  void setBrushRadius(double radius) {
    _brushRadius = radius.clamp(minBrushRadius, _maxBrushRadiusFraction);
    notifyListeners();
  }

  /// Brush size as a diameter in source-image pixels — the unit shown in the
  /// UI, matching native NAI. Stored normalized so strokes stay resolution-
  /// independent.
  double get brushDiameterPx =>
      _session == null ? 0 : _brushRadius * 2 * _session!.sourceWidth;

  void setBrushDiameterPx(double px) {
    if (_session == null) return;
    setBrushRadius(px / (2 * _session!.sourceWidth));
  }

  /// A comfortable step for +/- controls: 10% of the current size, at least
  /// one pixel.
  double get brushStepPx =>
      brushDiameterPx * 0.1 < 1 ? 1.0 : brushDiameterPx * 0.1;

  void setBrushOpacity(double opacity) {
    _brushOpacity = opacity.clamp(0.05, 1.0);
    notifyListeners();
  }

  void setBrushColor(int colorValue) {
    _brushColor = colorValue;
    notifyListeners();
  }

  // --- Stroke management ---

  void beginStroke(Offset normalizedPoint) {
    _currentStrokePoints = [normalizedPoint];
    notifyListeners();
  }

  void addStrokePoint(Offset normalizedPoint) {
    if (_currentStrokePoints == null) return;
    // Shape tools keep exactly 2 points (start + current)
    if (_tool == CanvasTool.line ||
        _tool == CanvasTool.rectangle ||
        _tool == CanvasTool.circle) {
      if (_currentStrokePoints!.length == 1) {
        _currentStrokePoints!.add(normalizedPoint);
      } else {
        _currentStrokePoints![1] = normalizedPoint;
      }
    } else {
      _currentStrokePoints!.add(normalizedPoint);
    }
    notifyListeners();
  }

  StrokeType _toolToStrokeType() {
    return switch (_tool) {
      CanvasTool.line => StrokeType.line,
      CanvasTool.rectangle => StrokeType.rectangle,
      CanvasTool.circle => StrokeType.circle,
      CanvasTool.fill => StrokeType.fill,
      CanvasTool.blur => StrokeType.blur,
      CanvasTool.cloneStamp => StrokeType.cloneStamp,
      _ => StrokeType.freehand,
    };
  }

  void endStroke() {
    if (_session == null ||
        _currentStrokePoints == null ||
        _currentStrokePoints!.isEmpty) {
      _currentStrokePoints = null;
      return;
    }

    final activeLayer = _session!.activeLayer;
    if (activeLayer == null) {
      _currentStrokePoints = null;
      return;
    }

    final strokeType = _toolToStrokeType();
    final stroke = PaintStroke(
      points: List<Offset>.from(_currentStrokePoints!),
      radius: _brushRadius,
      colorValue: _brushColor,
      opacity: _brushOpacity,
      isErase: _tool == CanvasTool.erase,
      strokeType: strokeType,
      smooth: strokeType == StrokeType.freehand && _smoothStrokes,
      blurSigma: _tool == CanvasTool.blur ? _blurSigma : null,
      cloneSourceOffset: _tool == CanvasTool.cloneStamp && _cloneSourcePoint != null
          ? Offset(
              _currentStrokePoints!.first.dx - _cloneSourcePoint!.dx,
              _currentStrokePoints!.first.dy - _cloneSourcePoint!.dy,
            )
          : null,
    );

    _currentStrokePoints = null;
    _pushAction(AddStrokeAction(
      layerId: activeLayer.id,
      stroke: stroke,
    ));
  }

  // --- Fill tool ---
  bool _isApplyingFill = false;
  bool get isApplyingFill => _isApplyingFill;

  /// Flood-fills the contiguous color region under [normalizedPoint] on the
  /// composited canvas (source + visible layers) and commits it as a fill
  /// stroke on the active layer (#23 — previously this always filled the
  /// whole image). Fill strokes restored from old sessions carry no region
  /// bitmap and keep the legacy whole-canvas behavior when rendered.
  Future<void> applyFill(Offset normalizedPoint) async {
    if (_session == null || _isApplyingFill) return;
    final activeLayer = _session!.activeLayer;
    if (activeLayer == null) return;
    _isApplyingFill = true;
    notifyListeners();
    try {
      final visibleLayers = _session!.layers.where((l) => l.visible).toList();
      final Uint8List flattened;
      if (visibleLayers.any((l) => l.strokes.isNotEmpty || l.isImageLayer)) {
        flattened = await CanvasFlattenService.flatten(
          sourceBytes: _session!.sourceImageBytes,
          sourceWidth: _session!.sourceWidth,
          sourceHeight: _session!.sourceHeight,
          visibleLayers: visibleLayers,
        );
      } else {
        flattened = _session!.sourceImageBytes;
      }
      final regionPng = await compute(
        computeFillRegionPng,
        FillRegionParams(
          flattenedPng: flattened,
          normalizedSeed: normalizedPoint,
          colorValue: _brushColor,
        ),
      );
      if (regionPng == null) return;
      // The session may have changed while the fill was computing.
      if (_session == null ||
          !_session!.layers.any((l) => l.id == activeLayer.id)) {
        return;
      }
      final stroke = PaintStroke(
        points: [normalizedPoint],
        radius: 0,
        colorValue: _brushColor,
        opacity: _brushOpacity,
        strokeType: StrokeType.fill,
        fillRegionPng: regionPng,
        fillSeed: normalizedPoint,
      );
      _pushAction(AddStrokeAction(layerId: activeLayer.id, stroke: stroke));
    } catch (e) {
      debugPrint('Flood fill failed: $e');
    } finally {
      _isApplyingFill = false;
      notifyListeners();
    }
  }

  /// Add a text stroke at the given position.
  void addTextStroke({
    required Offset position,
    required String text,
    required double fontSize,
    String? fontFamily,
    double? letterSpacing,
  }) {
    if (_session == null) return;
    final activeLayer = _session!.activeLayer;
    if (activeLayer == null) return;
    final stroke = PaintStroke(
      points: [position],
      radius: 0,
      colorValue: _brushColor,
      opacity: _brushOpacity,
      strokeType: StrokeType.text,
      text: text,
      fontSize: fontSize,
      fontFamily: fontFamily,
      letterSpacing: letterSpacing,
    );
    _pushAction(AddStrokeAction(layerId: activeLayer.id, stroke: stroke));
  }

  /// Discards the in-progress stroke without committing it to the active layer.
  /// Used when a second finger lands and the gesture becomes a pinch-zoom, so
  /// the partial one-finger stroke doesn't get left on the canvas.
  void cancelStroke() {
    if (_currentStrokePoints == null) return;
    _currentStrokePoints = null;
    notifyListeners();
  }

  /// Returns current in-progress stroke for live preview rendering.
  PaintStroke? get activeStroke {
    if (_currentStrokePoints == null || _currentStrokePoints!.isEmpty) {
      return null;
    }
    final strokeType = _toolToStrokeType();
    return PaintStroke(
      points: _currentStrokePoints!,
      radius: _brushRadius,
      colorValue: _brushColor,
      opacity: _brushOpacity,
      isErase: _tool == CanvasTool.erase,
      strokeType: strokeType,
      smooth: strokeType == StrokeType.freehand && _smoothStrokes,
      blurSigma: _tool == CanvasTool.blur ? _blurSigma : null,
      cloneSourceOffset: _tool == CanvasTool.cloneStamp && _cloneSourcePoint != null
          ? Offset(
              _currentStrokePoints!.first.dx - _cloneSourcePoint!.dx,
              _currentStrokePoints!.first.dy - _cloneSourcePoint!.dy,
            )
          : null,
    );
  }

  // --- Layer management ---

  void setActiveLayer(String layerId) {
    if (_session == null) return;
    if (_session!.layers.any((l) => l.id == layerId)) {
      _session = _session!.copyWith(activeLayerId: layerId);
      notifyListeners();
    }
  }

  void addLayer() {
    if (_session == null) return;
    final id = 'layer_${DateTime.now().microsecondsSinceEpoch}';
    final name = 'Layer $_nextLayerNumber';
    _nextLayerNumber++;

    final layer = CanvasLayer(id: id, name: name);
    _pushAction(AddLayerAction(layer: layer));
    // After adding, set the new layer as active
    _session = _session!.copyWith(activeLayerId: id);
    notifyListeners();
  }

  void removeLayer(String layerId) {
    if (_session == null) return;
    final idx = _session!.layers.indexWhere((l) => l.id == layerId);
    if (idx < 0) return;
    // Don't allow deleting the last layer
    if (_session!.layers.length <= 1) return;

    final removedLayer = _session!.layers[idx];
    _pushAction(RemoveLayerAction(removedLayer: removedLayer, index: idx));

    // If we removed the active layer, switch to nearest
    if (_session!.activeLayerId == layerId) {
      // layers already updated by _pushAction
      final newActive = _session!.layers.isNotEmpty
          ? _session!.layers[idx.clamp(0, _session!.layers.length - 1)].id
          : '';
      _session = _session!.copyWith(activeLayerId: newActive);
      notifyListeners();
    }
  }

  void duplicateLayer(String layerId) {
    if (_session == null) return;
    final srcIdx = _session!.layers.indexWhere((l) => l.id == layerId);
    if (srcIdx < 0) return;

    final src = _session!.layers[srcIdx];
    final newId = 'layer_${DateTime.now().microsecondsSinceEpoch}';
    final copy = src.copyWith(
      id: newId,
      name: '${src.name} copy',
      strokes: List<PaintStroke>.from(src.strokes),
    );
    final insertIdx = srcIdx + 1;
    _pushAction(
        DuplicateLayerAction(duplicatedLayer: copy, insertIndex: insertIdx));
    _session = _session!.copyWith(activeLayerId: newId);
    notifyListeners();
  }

  void renameLayer(String layerId, String newName) {
    if (_session == null) return;
    final layer = _session!.layers.firstWhere((l) => l.id == layerId,
        orElse: () => const CanvasLayer(id: '', name: ''));
    if (layer.id.isEmpty || layer.name == newName) return;

    _pushAction(RenameLayerAction(
      layerId: layerId,
      oldName: layer.name,
      newName: newName,
    ));
  }

  void setLayerVisibility(String layerId, bool visible) {
    if (_session == null) return;
    final layer = _session!.layers.firstWhere((l) => l.id == layerId,
        orElse: () => const CanvasLayer(id: '', name: ''));
    if (layer.id.isEmpty || layer.visible == visible) return;

    _pushAction(SetLayerVisibilityAction(
      layerId: layerId,
      oldVisible: layer.visible,
      newVisible: visible,
    ));
  }

  void setLayerOpacity(String layerId, double opacity) {
    if (_session == null) return;
    final layer = _session!.layers.firstWhere((l) => l.id == layerId,
        orElse: () => const CanvasLayer(id: '', name: ''));
    if (layer.id.isEmpty || layer.opacity == opacity) return;

    _pushAction(SetLayerOpacityAction(
      layerId: layerId,
      oldOpacity: layer.opacity,
      newOpacity: opacity,
    ));
  }

  void setLayerBlendMode(String layerId, CanvasBlendMode mode) {
    if (_session == null) return;
    final layer = _session!.layers.firstWhere((l) => l.id == layerId,
        orElse: () => const CanvasLayer(id: '', name: ''));
    if (layer.id.isEmpty || layer.blendMode == mode) return;

    _pushAction(SetLayerBlendModeAction(
      layerId: layerId,
      oldMode: layer.blendMode,
      newMode: mode,
    ));
  }

  void reorderLayer(int oldIndex, int newIndex) {
    if (_session == null) return;
    if (oldIndex == newIndex) return;
    _pushAction(
        ReorderLayerAction(oldIndex: oldIndex, newIndex: newIndex));
  }

  void clearLayer(String layerId) {
    if (_session == null) return;
    final layer = _session!.layers.firstWhere((l) => l.id == layerId,
        orElse: () => const CanvasLayer(id: '', name: ''));
    if (layer.id.isEmpty || layer.strokes.isEmpty) return;

    _pushAction(ClearLayerAction(
      layerId: layerId,
      removedStrokes: List<PaintStroke>.from(layer.strokes),
    ));
  }

  // --- Image layer management ---

  /// Add an image as a new layer.
  void addImageLayer(Uint8List bytes, {String? name}) {
    if (_session == null) return;
    final id = 'layer_${DateTime.now().microsecondsSinceEpoch}';
    final layerName = name ?? 'Image $_nextLayerNumber';
    _nextLayerNumber++;

    final layer = CanvasLayer(
      id: id,
      name: layerName,
      imageBytes: bytes,
      imageX: 0.0,
      imageY: 0.0,
      imageScale: 1.0,
      imageRotation: 0.0,
    );

    _pushAction(AddImageLayerAction(layer: layer));
    _session = _session!.copyWith(activeLayerId: id);
    notifyListeners();
  }

  // Transform tool state
  double? _transformStartX;
  double? _transformStartY;
  double? _transformStartScale;
  double? _transformStartRotation;

  void beginTransform() {
    if (_session == null) return;
    final layer = _session!.activeLayer;
    if (layer == null || !layer.isImageLayer) return;

    _transformStartX = layer.imageX;
    _transformStartY = layer.imageY;
    _transformStartScale = layer.imageScale;
    _transformStartRotation = layer.imageRotation;
  }

  void updateTransform({
    double? dx,
    double? dy,
    double? scale,
    double? rotation,
  }) {
    if (_session == null) return;
    final layer = _session!.activeLayer;
    if (layer == null || !layer.isImageLayer) return;

    final layers = List<CanvasLayer>.from(_session!.layers);
    final idx = layers.indexWhere((l) => l.id == layer.id);
    if (idx < 0) return;

    layers[idx] = layers[idx].copyWith(
      imageX: dx ?? layer.imageX,
      imageY: dy ?? layer.imageY,
      imageScale: scale ?? layer.imageScale,
      imageRotation: rotation ?? layer.imageRotation,
    );
    _session = _session!.copyWith(layers: layers);
    notifyListeners();
  }

  void endTransform() {
    if (_session == null || _transformStartX == null) return;
    final layer = _session!.activeLayer;
    if (layer == null || !layer.isImageLayer) return;

    _pushAction(TransformImageLayerAction(
      layerId: layer.id,
      oldX: _transformStartX!,
      oldY: _transformStartY!,
      oldScale: _transformStartScale!,
      oldRotation: _transformStartRotation!,
      newX: layer.imageX,
      newY: layer.imageY,
      newScale: layer.imageScale,
      newRotation: layer.imageRotation,
    ));

    _transformStartX = null;
    _transformStartY = null;
    _transformStartScale = null;
    _transformStartRotation = null;
  }

  // --- Layer move (Move tool) ---
  Offset _layerMoveOffset = Offset.zero;
  String? _movingLayerId;

  /// Live, uncommitted offset of the layer being moved (normalized units).
  /// The paint surface renders the layer shifted by this while the drag is in
  /// progress; the offset is baked into the strokes on [endLayerMove].
  Offset get layerMoveOffset => _layerMoveOffset;
  String? get movingLayerId => _movingLayerId;

  void beginLayerMove() {
    if (_session?.activeLayer == null) return;
    _movingLayerId = _session!.activeLayer!.id;
    _layerMoveOffset = Offset.zero;
  }

  void updateLayerMove(Offset delta) {
    if (_movingLayerId == null) return;
    _layerMoveOffset += delta;
    notifyListeners();
  }

  /// Commits the accumulated move as an undoable action.
  void endLayerMove() {
    final layerId = _movingLayerId;
    final offset = _layerMoveOffset;
    _movingLayerId = null;
    _layerMoveOffset = Offset.zero;
    if (_session == null || layerId == null) return;
    final layer = _session!.layers.firstWhere((l) => l.id == layerId,
        orElse: () => const CanvasLayer(id: '', name: ''));
    final hasContent = layer.strokes.isNotEmpty || layer.isImageLayer;
    if (layer.id.isEmpty || offset == Offset.zero || !hasContent) {
      notifyListeners();
      return;
    }
    _pushAction(TranslateLayerAction(
      layerId: layerId,
      dx: offset.dx,
      dy: offset.dy,
      moveImage: layer.isImageLayer,
    ));
  }

  /// Discards an in-progress move without committing (e.g. pinch started).
  void cancelLayerMove() {
    if (_movingLayerId == null) return;
    _movingLayerId = null;
    _layerMoveOffset = Offset.zero;
    notifyListeners();
  }

  // --- Selection tool state ---
  CanvasSelection? _activeSelection;
  SelectionHandle? _dragHandle;
  Offset? _dragStartPoint;

  CanvasSelection? get activeSelection => _activeSelection;
  bool get hasSelection => _activeSelection != null;

  /// Start drawing a selection rectangle.
  void beginSelection(Offset normalizedStart) {
    _activeSelection = CanvasSelection(
      normalizedRect: Rect.fromPoints(normalizedStart, normalizedStart),
    );
    _dragStartPoint = normalizedStart;
    notifyListeners();
  }

  /// Update the selection rectangle while drawing.
  void updateSelectionRect(Offset normalizedCurrent) {
    if (_dragStartPoint == null) return;
    _activeSelection = CanvasSelection(
      normalizedRect: Rect.fromPoints(_dragStartPoint!, normalizedCurrent),
    );
    notifyListeners();
  }

  /// Finalize the selection rectangle.
  void endSelectionRect() {
    if (_activeSelection == null) return;
    final r = _activeSelection!.normalizedRect;
    // Discard if too small
    if (r.width < 0.005 || r.height < 0.005) {
      _activeSelection = null;
    }
    _dragStartPoint = null;
    notifyListeners();
  }

  /// Begin lasso selection with freehand path.
  void beginLassoSelection(Offset normalizedStart) {
    _activeSelection = CanvasSelection(
      normalizedRect: Rect.fromPoints(normalizedStart, normalizedStart),
      clipPath: [normalizedStart],
    );
    notifyListeners();
  }

  /// Add a point to the lasso path.
  void addLassoPoint(Offset normalizedPoint) {
    if (_activeSelection?.clipPath == null) return;
    final pts = [..._activeSelection!.clipPath!, normalizedPoint];
    // Compute bounding rect
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    _activeSelection = CanvasSelection(
      normalizedRect: Rect.fromLTRB(minX, minY, maxX, maxY),
      clipPath: pts,
    );
    notifyListeners();
  }

  /// Finalize the lasso selection.
  void endLassoSelection() {
    if (_activeSelection?.clipPath == null) return;
    final r = _activeSelection!.normalizedRect;
    if (r.width < 0.005 || r.height < 0.005) {
      _activeSelection = null;
    }
    notifyListeners();
  }

  /// Begin dragging a selection handle.
  void beginSelectionDrag(SelectionHandle handle, Offset normalizedPoint) {
    _dragHandle = handle;
    _dragStartPoint = normalizedPoint;
  }

  /// Update dragging a selection handle.
  void updateSelectionDrag(Offset normalizedPoint) {
    if (_activeSelection == null || _dragHandle == null || _dragStartPoint == null) return;

    final delta = normalizedPoint - _dragStartPoint!;

    if (_dragHandle == SelectionHandle.body) {
      _activeSelection = _activeSelection!.copyWith(
        offsetX: _activeSelection!.offsetX + delta.dx,
        offsetY: _activeSelection!.offsetY + delta.dy,
      );
    } else if (_dragHandle == SelectionHandle.rotate) {
      final center = _activeSelection!.transformedRect.center;
      final angle = (normalizedPoint - center).direction -
          (_dragStartPoint! - center).direction;
      _activeSelection = _activeSelection!.copyWith(
        rotation: _activeSelection!.rotation + angle,
      );
    } else {
      // Scale from corner handles
      final rect = _activeSelection!.transformedRect;
      final center = rect.center;
      final oldDist = (_dragStartPoint! - center).distance;
      final newDist = (normalizedPoint - center).distance;
      if (oldDist > 0.001) {
        final scaleFactor = newDist / oldDist;
        _activeSelection = _activeSelection!.copyWith(
          scale: (_activeSelection!.scale * scaleFactor).clamp(0.1, 10.0),
        );
      }
    }

    _dragStartPoint = normalizedPoint;
    notifyListeners();
  }

  /// End dragging a selection handle.
  void endSelectionDrag() {
    _dragHandle = null;
    _dragStartPoint = null;
  }

  /// Cancel and clear the active selection.
  void cancelSelection() {
    _activeSelection = null;
    _dragHandle = null;
    _dragStartPoint = null;
    notifyListeners();
  }

  /// The active selection as a transformed polygon, or null when there is no
  /// usable selection. Rotation is applied in aspect-corrected space — see
  /// selection_geometry.dart.
  List<Offset>? _selectionClipPolygon() {
    if (_session == null || _activeSelection == null) return null;
    final polygon = selectionToPolygon(
      _activeSelection!,
      aspect: _session!.sourceWidth / _session!.sourceHeight,
    );
    return polygon.length >= 3 ? polygon : null;
  }

  /// Erases the selection's area on the active layer as a single undoable
  /// action: an erase-typed fill stroke clipped to the selection polygon.
  /// The selection stays active afterwards (Photoshop semantics). No-ops on
  /// layers with nothing to erase so undo history stays clean.
  void deleteSelectionContents() {
    if (_session == null) return;
    final activeLayer = _session!.activeLayer;
    if (activeLayer == null) return;
    if (activeLayer.strokes.isEmpty && !activeLayer.isImageLayer) return;
    final polygon = _selectionClipPolygon();
    if (polygon == null) return;

    final stroke = PaintStroke(
      points: [_activeSelection!.transformedRect.center],
      radius: 0,
      colorValue: 0xFF000000,
      isErase: true,
      strokeType: StrokeType.fill,
      clipPolygon: polygon,
    );
    _pushAction(AddStrokeAction(layerId: activeLayer.id, stroke: stroke));
  }

  // --- Undo / Redo ---

  void undo() {
    if (_session == null || !_session!.canUndo) return;
    final action = _session!.history[_session!.historyIndex - 1];
    _revertAction(action);
    // Handle dimension changes for resize actions
    if (action is ResizeCanvasAction) {
      // Recompute source image at old dimensions (reverse the resize)
      _session = _session!.copyWith(
        sourceWidth: action.oldWidth,
        sourceHeight: action.oldHeight,
      );
      _rebuildSourceImage(action.oldWidth, action.oldHeight,
          -action.anchorOffsetX, -action.anchorOffsetY,
          action.newWidth, action.newHeight);
    }
    _session = _session!.copyWith(historyIndex: _session!.historyIndex - 1);
    notifyListeners();
  }

  void redo() {
    if (_session == null || !_session!.canRedo) return;
    final action = _session!.history[_session!.historyIndex];
    _applyAction(action);
    // Handle dimension changes for resize actions
    if (action is ResizeCanvasAction) {
      _session = _session!.copyWith(
        sourceWidth: action.newWidth,
        sourceHeight: action.newHeight,
      );
      _rebuildSourceImage(action.newWidth, action.newHeight,
          action.anchorOffsetX, action.anchorOffsetY,
          action.oldWidth, action.oldHeight);
    }
    _session = _session!.copyWith(historyIndex: _session!.historyIndex + 1);
    notifyListeners();
  }

  /// Rebuild source image bytes for a resize operation.
  void _rebuildSourceImage(int newW, int newH, int offX, int offY, int fromW, int fromH) {
    compute(_resizeSourceImage, _ResizeParams(
      sourceBytes: _session!.sourceImageBytes,
      newWidth: newW,
      newHeight: newH,
      anchorOffsetX: offX,
      anchorOffsetY: offY,
    )).then((resizedBytes) {
      if (_session != null &&
          _session!.sourceWidth == newW &&
          _session!.sourceHeight == newH) {
        _session = _session!.copyWith(sourceImageBytes: resizedBytes);
        notifyListeners();
      }
    });
  }

  /// Resize the canvas with the existing content anchored at the given offset.
  Future<void> resizeCanvas(int newWidth, int newHeight, int anchorOffsetX, int anchorOffsetY) async {
    if (_session == null) return;
    final action = ResizeCanvasAction(
      oldWidth: _session!.sourceWidth,
      oldHeight: _session!.sourceHeight,
      newWidth: newWidth,
      newHeight: newHeight,
      anchorOffsetX: anchorOffsetX,
      anchorOffsetY: anchorOffsetY,
    );

    // Discard future branch
    final trimmedHistory = _session!.history.sublist(0, _session!.historyIndex);
    _session = _session!.copyWith(
      history: [...trimmedHistory, action],
      historyIndex: trimmedHistory.length + 1,
    );
    _applyAction(action);

    // Resize the actual source image bytes to match the new dimensions
    final resizedBytes = await compute(_resizeSourceImage, _ResizeParams(
      sourceBytes: _session!.sourceImageBytes,
      newWidth: newWidth,
      newHeight: newHeight,
      anchorOffsetX: anchorOffsetX,
      anchorOffsetY: anchorOffsetY,
    ));

    _session = _session!.copyWith(
      sourceImageBytes: resizedBytes,
      sourceWidth: newWidth,
      sourceHeight: newHeight,
    );
    notifyListeners();
  }

  // --- Action system ---

  void _pushAction(CanvasAction action) {
    // Discard future branch
    final trimmedHistory =
        _session!.history.sublist(0, _session!.historyIndex);
    _session = _session!.copyWith(
      history: [...trimmedHistory, action],
      historyIndex: trimmedHistory.length + 1,
    );
    _applyAction(action);
    notifyListeners();
  }

  void _applyAction(CanvasAction action) {
    final layers = List<CanvasLayer>.from(_session!.layers);
    action.apply(layers, activeLayerId: _session!.activeLayerId);
    _session = _session!.copyWith(layers: layers);
  }

  void _revertAction(CanvasAction action) {
    final layers = List<CanvasLayer>.from(_session!.layers);
    action.revert(layers);
    _session = _session!.copyWith(layers: layers);
  }
}
