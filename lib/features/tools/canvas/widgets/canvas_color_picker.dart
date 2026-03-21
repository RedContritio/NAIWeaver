import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../../../../core/widgets/vision_slider.dart';

/// Extract dominant colors from an image by sampling and clustering.
/// Runs in an isolate via [compute] to avoid blocking the UI.
Future<List<Color>> extractDominantColors(Uint8List imageBytes, {int count = 8}) async {
  return compute(_extractColorsIsolate, _ExtractParams(imageBytes, count));
}

class _ExtractParams {
  final Uint8List bytes;
  final int count;
  _ExtractParams(this.bytes, this.count);
}

List<Color> _extractColorsIsolate(_ExtractParams params) {
  final decoded = img.decodeImage(params.bytes);
  if (decoded == null) return [];

  // Sample pixels on a grid (skip transparent/near-black/near-white)
  final step = math.max(1, math.min(decoded.width, decoded.height) ~/ 32);
  final samples = <_LabColor>[];

  for (int y = 0; y < decoded.height; y += step) {
    for (int x = 0; x < decoded.width; x += step) {
      final pixel = decoded.getPixel(x, y);
      final r = pixel.r.toInt().clamp(0, 255);
      final g = pixel.g.toInt().clamp(0, 255);
      final b = pixel.b.toInt().clamp(0, 255);

      // Skip near-black, near-white, and very desaturated
      final maxC = math.max(r, math.max(g, b));
      final minC = math.min(r, math.min(g, b));
      if (maxC < 20) continue; // too dark
      if (minC > 235) continue; // too bright
      // Keep some grays but skip if chroma is 0 AND brightness is mid
      samples.add(_LabColor.fromRGB(r, g, b));
    }
  }

  if (samples.isEmpty) {
    return [const Color(0xFF000000), const Color(0xFFFFFFFF)];
  }

  // Simple k-means clustering in Lab color space
  final k = math.min(params.count, samples.length);
  // Initialize centroids from evenly spaced samples
  final centroids = List<_LabColor>.generate(
    k, (i) => samples[(i * samples.length ~/ k).clamp(0, samples.length - 1)],
  );

  for (int iter = 0; iter < 10; iter++) {
    final clusters = List<List<_LabColor>>.generate(k, (_) => []);

    // Assign each sample to nearest centroid
    for (final s in samples) {
      int bestIdx = 0;
      double bestDist = double.infinity;
      for (int c = 0; c < k; c++) {
        final d = s.distanceTo(centroids[c]);
        if (d < bestDist) {
          bestDist = d;
          bestIdx = c;
        }
      }
      clusters[bestIdx].add(s);
    }

    // Update centroids
    for (int c = 0; c < k; c++) {
      if (clusters[c].isNotEmpty) {
        double lSum = 0, aSum = 0, bSum = 0;
        for (final s in clusters[c]) {
          lSum += s.l;
          aSum += s.a;
          bSum += s.b;
        }
        final n = clusters[c].length;
        centroids[c] = _LabColor(lSum / n, aSum / n, bSum / n);
      }
    }
  }

  // Sort by cluster population (most common first), then convert to Color
  final centroidCounts = <int, int>{};
  for (final s in samples) {
    int bestIdx = 0;
    double bestDist = double.infinity;
    for (int c = 0; c < k; c++) {
      final d = s.distanceTo(centroids[c]);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = c;
      }
    }
    centroidCounts[bestIdx] = (centroidCounts[bestIdx] ?? 0) + 1;
  }

  final sortedIndices = List<int>.generate(k, (i) => i)
    ..sort((a, b) => (centroidCounts[b] ?? 0).compareTo(centroidCounts[a] ?? 0));

  // Deduplicate colors that are too close together
  final results = <Color>[];
  for (final idx in sortedIndices) {
    final c = centroids[idx].toColor();
    bool tooClose = false;
    for (final existing in results) {
      final elab = _LabColor.fromRGB(
        (existing.r * 255.0).round().clamp(0, 255),
        (existing.g * 255.0).round().clamp(0, 255),
        (existing.b * 255.0).round().clamp(0, 255),
      );
      if (centroids[idx].distanceTo(elab) < 15) {
        tooClose = true;
        break;
      }
    }
    if (!tooClose) results.add(c);
    if (results.length >= params.count) break;
  }

  return results;
}

/// Simple CIE Lab color for perceptual distance comparison.
class _LabColor {
  final double l, a, b;
  const _LabColor(this.l, this.a, this.b);

  factory _LabColor.fromRGB(int r, int g, int b) {
    // sRGB to XYZ
    double rl = r / 255.0, gl = g / 255.0, bl = b / 255.0;
    rl = rl > 0.04045 ? math.pow((rl + 0.055) / 1.055, 2.4).toDouble() : rl / 12.92;
    gl = gl > 0.04045 ? math.pow((gl + 0.055) / 1.055, 2.4).toDouble() : gl / 12.92;
    bl = bl > 0.04045 ? math.pow((bl + 0.055) / 1.055, 2.4).toDouble() : bl / 12.92;
    double x = (rl * 0.4124 + gl * 0.3576 + bl * 0.1805) / 0.95047;
    double y = (rl * 0.2126 + gl * 0.7152 + bl * 0.0722) / 1.00000;
    double z = (rl * 0.0193 + gl * 0.1192 + bl * 0.9505) / 1.08883;
    x = x > 0.008856 ? math.pow(x, 1.0 / 3.0).toDouble() : (7.787 * x) + 16.0 / 116.0;
    y = y > 0.008856 ? math.pow(y, 1.0 / 3.0).toDouble() : (7.787 * y) + 16.0 / 116.0;
    z = z > 0.008856 ? math.pow(z, 1.0 / 3.0).toDouble() : (7.787 * z) + 16.0 / 116.0;
    return _LabColor((116.0 * y) - 16.0, 500.0 * (x - y), 200.0 * (y - z));
  }

  double distanceTo(_LabColor other) {
    final dl = l - other.l;
    final da = a - other.a;
    final db = b - other.b;
    return math.sqrt(dl * dl + da * da + db * db);
  }

  Color toColor() {
    double y = (l + 16.0) / 116.0;
    double x = a / 500.0 + y;
    double z = y - b / 200.0;
    x = x * x * x > 0.008856 ? x * x * x : (x - 16.0 / 116.0) / 7.787;
    y = y * y * y > 0.008856 ? y * y * y : (y - 16.0 / 116.0) / 7.787;
    z = z * z * z > 0.008856 ? z * z * z : (z - 16.0 / 116.0) / 7.787;
    x *= 0.95047; y *= 1.00000; z *= 1.08883;
    double r = x * 3.2406 + y * -1.5372 + z * -0.4986;
    double g = x * -0.9689 + y * 1.8758 + z * 0.0415;
    double bl = x * 0.0557 + y * -0.2040 + z * 1.0570;
    r = r > 0.0031308 ? 1.055 * math.pow(r, 1.0 / 2.4) - 0.055 : 12.92 * r;
    g = g > 0.0031308 ? 1.055 * math.pow(g, 1.0 / 2.4) - 0.055 : 12.92 * g;
    bl = bl > 0.0031308 ? 1.055 * math.pow(bl, 1.0 / 2.4) - 0.055 : 12.92 * bl;
    return Color.fromARGB(
      255,
      (r * 255).round().clamp(0, 255),
      (g * 255).round().clamp(0, 255),
      (bl * 255).round().clamp(0, 255),
    );
  }
}

/// Inline HSV color picker for the canvas toolbar.
/// Collapsed: color swatch + quick palette row.
/// Expanded: SV rectangle + hue bar + opacity slider + palette + hex input.
class CanvasColorPicker extends StatefulWidget {
  final Color currentColor;
  final double opacity;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onOpacityChanged;
  final bool compact;

  /// Colors extracted from the source image. Shown first in the quick palette.
  final List<Color> sourceImageColors;

  const CanvasColorPicker({
    super.key,
    required this.currentColor,
    required this.opacity,
    required this.onColorChanged,
    required this.onOpacityChanged,
    this.compact = true,
    this.sourceImageColors = const [],
  });

  @override
  State<CanvasColorPicker> createState() => _CanvasColorPickerState();
}

class _CanvasColorPickerState extends State<CanvasColorPicker> {
  bool _expanded = false;
  late HSVColor _hsv;
  late TextEditingController _hexController;
  final List<Color> _recentColors = [];

  /// The default built-in palette colors.
  static const List<Color> _defaultPalette = [
    Color(0xFF000000), Color(0xFF1E1E1E), Color(0xFF555555),
    Color(0xFFAAAAAA), Color(0xFFFFFFFF), Color(0xFFFF0066),
    Color(0xFFFF5252), Color(0xFFE91E63), Color(0xFFFF6F00),
    Color(0xFFFFD600), Color(0xFF4CAF50), Color(0xFF00BCD4),
    Color(0xFF3F51B5), Color(0xFF7C4DFF), Color(0xFF1A237E),
    Color(0xFF69F0AE),
  ];

  /// The user-customizable quick palette (shown collapsed + in expanded grid).
  /// Initialized from source image colors + defaults.
  late List<Color> _quickPalette;
  bool _quickPaletteInitialized = false;

  /// Build the quick palette: source image colors first, then fill with defaults.
  List<Color> _buildQuickPalette() {
    const maxQuick = 10;
    final result = <Color>[];

    // Add source image colors first (most relevant)
    for (final c in widget.sourceImageColors) {
      if (result.length >= maxQuick) break;
      if (!result.any((existing) => existing.toARGB32() == c.toARGB32())) {
        result.add(c);
      }
    }

    // Fill remaining with defaults, skipping duplicates
    for (final c in _defaultPalette) {
      if (result.length >= maxQuick) break;
      if (!result.any((existing) => existing.toARGB32() == c.toARGB32())) {
        result.add(c);
      }
    }

    return result;
  }

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.currentColor);
    _hexController = TextEditingController(text: _colorToHex(widget.currentColor));
    _quickPalette = _buildQuickPalette();
    _quickPaletteInitialized = widget.sourceImageColors.isNotEmpty;
  }

  @override
  void didUpdateWidget(CanvasColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentColor != widget.currentColor) {
      _hsv = HSVColor.fromColor(widget.currentColor);
      _hexController.text = _colorToHex(widget.currentColor);
    }
    // Rebuild quick palette when source image colors arrive for the first time
    if (!_quickPaletteInitialized && widget.sourceImageColors.isNotEmpty) {
      _quickPalette = _buildQuickPalette();
      _quickPaletteInitialized = true;
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _colorToHex(Color c) {
    return c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
  }

  Color? _hexToColor(String hex) {
    hex = hex.replaceAll('#', '').trim();
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final val = int.tryParse(hex, radix: 16);
    if (val == null) return null;
    return Color(val);
  }

  void _selectColor(Color c) {
    _hsv = HSVColor.fromColor(c);
    _hexController.text = _colorToHex(c);
    widget.onColorChanged(c);
    // Track recent colors
    _recentColors.remove(c);
    _recentColors.insert(0, c);
    if (_recentColors.length > 4) _recentColors.removeLast();
  }

  void _updateFromHSV() {
    final c = _hsv.toColor();
    _hexController.text = _colorToHex(c);
    widget.onColorChanged(c);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final currentColor = _hsv.toColor();

    if (!_expanded) {
      return _buildCollapsed(t, currentColor);
    }
    return _buildExpanded(t, currentColor);
  }

  Widget _buildCollapsed(VisionTokens t, Color currentColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Current color swatch (tap to expand)
        GestureDetector(
          onTap: () => setState(() => _expanded = true),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: currentColor,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: t.borderMedium, width: 1.5),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Quick palette row — tap to select, long-press to replace with current color
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(
                _quickPalette.length,
                (i) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: 'Tap: select  •  Hold: replace with current',
                    waitDuration: const Duration(milliseconds: 600),
                    child: GestureDetector(
                      onTap: () => _selectColor(_quickPalette[i]),
                      onLongPress: () {
                        setState(() {
                          _quickPalette[i] = currentColor;
                        });
                      },
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _quickPalette[i],
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: _quickPalette[i].toARGB32() == currentColor.toARGB32()
                                ? t.accent
                                : t.borderSubtle,
                            width: _quickPalette[i].toARGB32() == currentColor.toARGB32() ? 2 : 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpanded(VisionTokens t, Color currentColor) {
    final svHeight = widget.compact ? 140.0 : 180.0;
    final hueHeight = widget.compact ? 20.0 : 28.0;
    final swatchSize = widget.compact ? 24.0 : 32.0;

    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.borderMedium),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Close button row
          Row(
            children: [
              Text(
                'COLOR',
                style: TextStyle(
                  color: t.textDisabled,
                  fontSize: t.fontSize(8),
                  letterSpacing: 1,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _expanded = false),
                child: Icon(Icons.close, size: 14, color: t.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // SV Rectangle
          SizedBox(
            height: svHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanStart: (d) => _updateSV(d.localPosition, constraints, svHeight),
                  onPanUpdate: (d) => _updateSV(d.localPosition, constraints, svHeight),
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, svHeight),
                    painter: _SVRectPainter(hue: _hsv.hue, saturation: _hsv.saturation, value: _hsv.value),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Hue slider
          SizedBox(
            height: hueHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanStart: (d) => _updateHue(d.localPosition.dx, constraints.maxWidth),
                  onPanUpdate: (d) => _updateHue(d.localPosition.dx, constraints.maxWidth),
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, hueHeight),
                    painter: _HueBarPainter(hue: _hsv.hue, barHeight: hueHeight),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Opacity slider
          Row(
            children: [
              Text(
                'OPACITY',
                style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(7), letterSpacing: 1),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: VisionSlider(
                  value: widget.opacity,
                  min: 0.05,
                  onChanged: widget.onOpacityChanged,
                  activeColor: currentColor,
                  inactiveColor: t.textMinimal,
                  thumbColor: t.textPrimary,
                  thumbRadius: 6,
                  overlayRadius: 10,
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '${(widget.opacity * 100).round()}%',
                  style: TextStyle(color: t.textTertiary, fontSize: t.fontSize(8)),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Quick palette (customizable, from source image)
          if (_quickPalette.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'QUICK',
                  style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(7), letterSpacing: 1),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() {
                    _quickPalette = _buildQuickPalette();
                  }),
                  child: Text(
                    'RESET',
                    style: TextStyle(
                      color: t.textMinimal, fontSize: t.fontSize(6),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: List.generate(_quickPalette.length, (i) {
                final c = _quickPalette[i];
                final isSelected = c.toARGB32() == currentColor.toARGB32();
                return Tooltip(
                  message: 'Hold to replace',
                  waitDuration: const Duration(milliseconds: 600),
                  child: GestureDetector(
                    onTap: () => _selectColor(c),
                    onLongPress: () {
                      setState(() => _quickPalette[i] = currentColor);
                    },
                    child: Container(
                      width: swatchSize,
                      height: swatchSize,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: isSelected ? t.accent : t.borderSubtle,
                          width: isSelected ? 2 : 0.5,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
          ],

          // Default palette grid
          Text(
            'PALETTE',
            style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(7), letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: _defaultPalette.map((c) {
              final isSelected = c.toARGB32() == currentColor.toARGB32();
              return GestureDetector(
                onTap: () => _selectColor(c),
                child: Container(
                  width: swatchSize,
                  height: swatchSize,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isSelected ? t.accent : t.borderSubtle,
                      width: isSelected ? 2 : 0.5,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

          // Recent colors
          if (_recentColors.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'RECENT',
                  style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(7), letterSpacing: 1),
                ),
                const SizedBox(width: 8),
                ..._recentColors.map((c) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () => _selectColor(c),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: t.borderSubtle, width: 0.5),
                      ),
                    ),
                  ),
                )),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Hex input
          Row(
            children: [
              Text('#', style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(12))),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _hexController,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: t.fontSize(11),
                    fontFamily: 'monospace',
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(
                    hintText: 'FFFFFF',
                    hintStyle: TextStyle(color: t.textMinimal),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    isDense: true,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: t.borderMedium),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: t.accent),
                    ),
                  ),
                  onChanged: (val) {
                    final c = _hexToColor(val);
                    if (c != null) {
                      setState(() {
                        _hsv = HSVColor.fromColor(c);
                      });
                      widget.onColorChanged(c);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Preview swatch
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: currentColor.withValues(alpha: widget.opacity),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: t.borderMedium),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _updateSV(Offset local, BoxConstraints constraints, double height) {
    final s = (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final v = (1.0 - local.dy / height).clamp(0.0, 1.0);
    setState(() {
      _hsv = HSVColor.fromAHSV(1.0, _hsv.hue, s, v);
    });
    _updateFromHSV();
  }

  void _updateHue(double dx, double width) {
    final hue = (dx / width * 360.0).clamp(0.0, 359.99);
    setState(() {
      _hsv = HSVColor.fromAHSV(1.0, hue, _hsv.saturation, _hsv.value);
    });
    _updateFromHSV();
  }
}

/// Paints the Saturation-Value rectangle with a position indicator.
class _SVRectPainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double value;

  _SVRectPainter({required this.hue, required this.saturation, required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    // Base hue gradient (left to right: white to full hue)
    final hueColor = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
    final rectGradientH = LinearGradient(
      colors: [Colors.white, hueColor],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..shader = rectGradientH);

    // Value gradient (top to bottom: transparent to black)
    final rectGradientV = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..shader = rectGradientV);

    // Position indicator
    final cx = saturation * size.width;
    final cy = (1.0 - value) * size.height;
    canvas.drawCircle(
      Offset(cx, cy),
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SVRectPainter old) =>
      hue != old.hue || saturation != old.saturation || value != old.value;
}

/// Paints a horizontal hue spectrum bar with a position indicator.
class _HueBarPainter extends CustomPainter {
  final double hue;
  final double barHeight;

  _HueBarPainter({required this.hue, this.barHeight = 20.0});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    // Hue spectrum gradient
    final colors = List.generate(7, (i) {
      return HSVColor.fromAHSV(1.0, i * 60.0, 1.0, 1.0).toColor();
    });
    final shader = LinearGradient(colors: colors).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..shader = shader,
    );

    // Position indicator
    final x = (hue / 360.0) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, size.height / 2), width: 6, height: size.height),
        const Radius.circular(2),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_HueBarPainter old) => hue != old.hue;
}
