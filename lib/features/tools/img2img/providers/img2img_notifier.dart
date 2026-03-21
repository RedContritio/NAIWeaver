import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/img2img_preset.dart';
import '../models/img2img_session.dart';

/// Visual pattern applied to the mask overlay.
enum MaskPattern { solid, stripe, crosshatch }

class Img2ImgNotifier extends ChangeNotifier {
  Img2ImgSession? _session;
  Img2ImgSession? get session => _session;

  List<Img2ImgPreset> _presets = [];
  List<Img2ImgPreset> get presets => _presets;

  void loadPresets(String jsonStr) {
    _presets = Img2ImgPreset.listFromJson(jsonStr);
  }

  String presetsToJson() => Img2ImgPreset.listToJson(_presets);

  void savePreset(String name) {
    final s = _session?.settings ?? const Img2ImgSettings();
    _presets.add(Img2ImgPreset(
      name: name,
      strength: s.strength,
      noise: s.noise,
      colorCorrect: s.colorCorrect,
      maskBlur: s.maskBlur,
    ));
    notifyListeners();
  }

  void applyPreset(Img2ImgPreset preset) {
    if (_session == null) return;
    _session = _session!.copyWith(
      settings: Img2ImgSettings(
        strength: preset.strength,
        noise: preset.noise,
        colorCorrect: preset.colorCorrect,
        maskBlur: preset.maskBlur,
      ),
    );
    notifyListeners();
  }

  void deletePreset(int index) {
    if (index < 0 || index >= _presets.length) return;
    _presets.removeAt(index);
    notifyListeners();
  }

  /// Current in-progress stroke (built up during a pan gesture).
  List<Offset>? _currentStrokePoints;
  double _brushRadius = 0.05;
  bool _isEraseMode = false;

  double get brushRadius => _brushRadius;
  bool get isEraseMode => _isEraseMode;

  // --- Mask display settings ---
  int _maskColor = 0xFFFF0066;
  double _maskOpacity = 0.19; // ~48/255
  bool _maskShowBorder = false;
  MaskPattern _maskPattern = MaskPattern.solid;

  int get maskColor => _maskColor;
  double get maskOpacity => _maskOpacity;
  bool get maskShowBorder => _maskShowBorder;
  MaskPattern get maskPattern => _maskPattern;

  void setMaskColor(int color) {
    _maskColor = color;
    notifyListeners();
  }

  void setMaskOpacity(double opacity) {
    _maskOpacity = opacity.clamp(0.05, 1.0);
    notifyListeners();
  }

  void setMaskShowBorder(bool show) {
    _maskShowBorder = show;
    notifyListeners();
  }

  void setMaskPattern(MaskPattern pattern) {
    _maskPattern = pattern;
    notifyListeners();
  }
  bool get hasSession => _session != null;
  bool get hasMask => _session?.hasMask ?? false;

  /// Load a source image from raw bytes. Decodes to get dimensions.
  Future<void> loadSourceImage(Uint8List bytes, {String? prompt, String? negativePrompt, String? filePath}) async {
    final decoded = await compute(_decodeImageDimensions, bytes);
    if (decoded == null) return;

    _session = Img2ImgSession(
      sourceImageBytes: bytes,
      sourceWidth: decoded.$1,
      sourceHeight: decoded.$2,
      prompt: prompt ?? '',
      negativePrompt: negativePrompt ?? '',
      sourceFilePath: filePath,
      outputWidth: _session?.outputWidth,
      outputHeight: _session?.outputHeight,
    );
    notifyListeners();
  }

  void clearSession() {
    _session = null;
    notifyListeners();
  }

  // --- Brush settings ---

  void setBrushRadius(double radius) {
    _brushRadius = radius.clamp(0.005, 0.2);
    notifyListeners();
  }

  void setEraseMode(bool erase) {
    _isEraseMode = erase;
    notifyListeners();
  }

  // --- Stroke management ---

  void beginStroke(Offset normalizedPoint) {
    _currentStrokePoints = [normalizedPoint];
    notifyListeners();
  }

  void addStrokePoint(Offset normalizedPoint) {
    _currentStrokePoints?.add(normalizedPoint);
    notifyListeners();
  }

  void endStroke() {
    if (_session == null || _currentStrokePoints == null || _currentStrokePoints!.isEmpty) {
      _currentStrokePoints = null;
      return;
    }

    final stroke = MaskStroke(
      points: List<Offset>.from(_currentStrokePoints!),
      radius: _brushRadius,
      isErase: _isEraseMode,
    );

    _session = _session!.copyWith(
      maskStrokes: [..._session!.maskStrokes, stroke],
    );
    _currentStrokePoints = null;
    notifyListeners();
  }

  /// Returns current in-progress stroke for live preview rendering.
  MaskStroke? get activeStroke {
    if (_currentStrokePoints == null || _currentStrokePoints!.isEmpty) return null;
    return MaskStroke(
      points: _currentStrokePoints!,
      radius: _brushRadius,
      isErase: _isEraseMode,
    );
  }

  void undoLastStroke() {
    if (_session == null || _session!.maskStrokes.isEmpty) return;
    _session = _session!.copyWith(
      maskStrokes: _session!.maskStrokes.sublist(0, _session!.maskStrokes.length - 1),
    );
    notifyListeners();
  }

  void clearMask() {
    if (_session == null) return;
    _session = _session!.copyWith(maskStrokes: []);
    notifyListeners();
  }

  // --- Settings ---

  void updateSettings(Img2ImgSettings settings) {
    if (_session == null) return;
    _session = _session!.copyWith(settings: settings);
    notifyListeners();
  }

  void setStrength(double value) {
    if (_session == null) return;
    _session = _session!.copyWith(
      settings: _session!.settings.copyWith(strength: value),
    );
    notifyListeners();
  }

  void setNoise(double value) {
    if (_session == null) return;
    _session = _session!.copyWith(
      settings: _session!.settings.copyWith(noise: value),
    );
    notifyListeners();
  }

  void setColorCorrect(bool value) {
    if (_session == null) return;
    _session = _session!.copyWith(
      settings: _session!.settings.copyWith(colorCorrect: value),
    );
    notifyListeners();
  }

  void setMaskBlur(int value) {
    if (_session == null) return;
    _session = _session!.copyWith(
      settings: _session!.settings.copyWith(maskBlur: value),
    );
    notifyListeners();
  }

  void setResultImage(Uint8List bytes) {
    if (_session == null) return;
    _session = _session!.copyWith(resultImageBytes: bytes);
    notifyListeners();
  }

  void clearResult() {
    if (_session == null) return;
    _session = _session!.copyWith(clearResult: true);
    notifyListeners();
  }

  /// Replace the source image with the current result for iterative inpainting.
  Future<void> useResultAsSource() async {
    if (_session == null || _session!.resultImageBytes == null) return;
    final resultBytes = _session!.resultImageBytes!;

    final decoded = await compute(_decodeImageDimensions, resultBytes);
    if (decoded == null) return;

    _session = Img2ImgSession(
      sourceImageBytes: resultBytes,
      sourceWidth: decoded.$1,
      sourceHeight: decoded.$2,
      settings: _session!.settings,
      prompt: _session!.prompt,
      negativePrompt: _session!.negativePrompt,
      outputWidth: _session!.outputWidth,
      outputHeight: _session!.outputHeight,
    );
    notifyListeners();
  }

  /// Replace the source image with new bytes (e.g. from canvas editor).
  /// Decodes dimensions, replaces source, clears mask strokes and result.
  Future<void> replaceSourceImage(Uint8List bytes, {String? filePath}) async {
    final decoded = await compute(_decodeImageDimensions, bytes);
    if (decoded == null) return;

    _session = Img2ImgSession(
      sourceImageBytes: bytes,
      sourceWidth: decoded.$1,
      sourceHeight: decoded.$2,
      settings: _session?.settings ?? const Img2ImgSettings(),
      prompt: _session?.prompt ?? '',
      negativePrompt: _session?.negativePrompt ?? '',
      sourceFilePath: filePath,
      outputWidth: _session?.outputWidth,
      outputHeight: _session?.outputHeight,
    );
    notifyListeners();
  }

  void setOutputResolution(int width, int height) {
    if (_session == null) return;
    _session = _session!.copyWith(outputWidth: width, outputHeight: height);
    notifyListeners();
  }

  void resetOutputResolution() {
    if (_session == null) return;
    _session = _session!.copyWith(clearOutputResolution: true);
    notifyListeners();
  }

  void setPrompt(String value) {
    if (_session == null) return;
    _session = _session!.copyWith(prompt: value);
    // Don't notify for every keystroke to avoid rebuilds
  }

  void setNegativePrompt(String value) {
    if (_session == null) return;
    _session = _session!.copyWith(negativePrompt: value);
  }

  /// Load a pre-baked mask from PNG bytes.
  void loadMask(Uint8List pngBytes) {
    if (_session == null) return;
    _session = _session!.copyWith(
      prebakedMaskBytes: pngBytes,
      maskStrokes: [], // Clear strokes when loading external mask
    );
    notifyListeners();
  }

  /// Clear the pre-baked mask.
  void clearPrebakedMask() {
    if (_session == null) return;
    _session = _session!.copyWith(clearPrebakedMask: true);
    notifyListeners();
  }
}

/// Decode image to get width/height. Runs in isolate.
(int, int)? _decodeImageDimensions(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return (decoded.width, decoded.height);
}
