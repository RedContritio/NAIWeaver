import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

/// Shape type for a paint stroke.
enum StrokeType { freehand, line, rectangle, circle, fill, text, blur, cloneStamp }

/// A single paint or erase stroke on the canvas.
/// Points use normalized 0-1 coordinates (same system as MaskStroke).
class PaintStroke {
  final List<Offset> points;
  final double radius; // normalized 0-1 relative to image width
  final int colorValue; // ARGB int
  final double opacity; // 0.0-1.0, applied per-stroke
  final bool isErase;
  final StrokeType strokeType;
  final bool smooth;
  final String? text;
  final double? fontSize; // normalized 0-1 relative to image height
  final String? fontFamily; // Google Fonts family name (null = default)
  final double? letterSpacing; // normalized relative to image height
  final double? blurSigma; // blur intensity for blur strokes
  final Offset? cloneSourceOffset; // normalized offset from source for clone stamp

  /// Flood-fill region for fill strokes: a source-resolution PNG holding the
  /// fill color at full alpha inside the region, transparent elsewhere.
  /// Null on fill strokes from old sessions — those fill the whole canvas.
  final Uint8List? fillRegionPng;

  /// The seed point the region was computed from. When the layer is moved,
  /// points[0] shifts while this stays put; renderers draw the region offset
  /// by (points[0] - fillSeed).
  final Offset? fillSeed;

  const PaintStroke({
    required this.points,
    required this.radius,
    required this.colorValue,
    this.opacity = 1.0,
    this.isErase = false,
    this.strokeType = StrokeType.freehand,
    this.smooth = false,
    this.text,
    this.fontSize,
    this.fontFamily,
    this.letterSpacing,
    this.blurSigma,
    this.cloneSourceOffset,
    this.fillRegionPng,
    this.fillSeed,
  });

  Color get color => Color(colorValue);

  /// A copy with every point shifted by [delta] (normalized units).
  /// [cloneSourceOffset] is relative to the stroke and stays unchanged, as
  /// does [fillSeed] — the fill region renders offset by points[0] - fillSeed.
  PaintStroke translated(Offset delta) => PaintStroke(
        points: points.map((p) => p + delta).toList(),
        radius: radius,
        colorValue: colorValue,
        opacity: opacity,
        isErase: isErase,
        strokeType: strokeType,
        smooth: smooth,
        text: text,
        fontSize: fontSize,
        fontFamily: fontFamily,
        letterSpacing: letterSpacing,
        blurSigma: blurSigma,
        cloneSourceOffset: cloneSourceOffset,
        fillRegionPng: fillRegionPng,
        fillSeed: fillSeed,
      );

  Map<String, dynamic> toJson() => {
        'points': points.map((p) => [p.dx, p.dy]).toList(),
        'radius': radius,
        'colorValue': colorValue,
        'opacity': opacity,
        'isErase': isErase,
        'strokeType': strokeType.name,
        'smooth': smooth,
        if (text != null) 'text': text,
        if (fontSize != null) 'fontSize': fontSize,
        if (fontFamily != null) 'fontFamily': fontFamily,
        if (letterSpacing != null) 'letterSpacing': letterSpacing,
        if (blurSigma != null) 'blurSigma': blurSigma,
        if (cloneSourceOffset != null)
          'cloneSourceOffset': [cloneSourceOffset!.dx, cloneSourceOffset!.dy],
        if (fillRegionPng != null) 'fillRegionPng': base64Encode(fillRegionPng!),
        if (fillSeed != null) 'fillSeed': [fillSeed!.dx, fillSeed!.dy],
      };

  factory PaintStroke.fromJson(Map<String, dynamic> json) {
    return PaintStroke(
      points: (json['points'] as List)
          .map((p) => Offset((p as List)[0] as double, p[1] as double))
          .toList(),
      radius: (json['radius'] as num).toDouble(),
      colorValue: json['colorValue'] as int,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      isErase: json['isErase'] as bool? ?? false,
      strokeType: StrokeType.values.firstWhere(
        (e) => e.name == json['strokeType'],
        orElse: () => StrokeType.freehand,
      ),
      smooth: json['smooth'] as bool? ?? false,
      text: json['text'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      fontFamily: json['fontFamily'] as String?,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble(),
      blurSigma: (json['blurSigma'] as num?)?.toDouble(),
      cloneSourceOffset: json['cloneSourceOffset'] != null
          ? Offset(
              (json['cloneSourceOffset'] as List)[0] as double,
              (json['cloneSourceOffset'] as List)[1] as double,
            )
          : null,
      fillRegionPng: json['fillRegionPng'] != null
          ? base64Decode(json['fillRegionPng'] as String)
          : null,
      fillSeed: json['fillSeed'] != null
          ? Offset(
              ((json['fillSeed'] as List)[0] as num).toDouble(),
              ((json['fillSeed'] as List)[1] as num).toDouble(),
            )
          : null,
    );
  }
}
