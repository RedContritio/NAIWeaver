import 'dart:convert';
import 'dart:typed_data';

class VibeTransfer {
  final String id;
  final Uint8List originalImageBytes;
  final Uint8List processedPreview;
  final String vibeVectorBase64;
  final double strength;
  final double infoExtracted;

  /// Whether this vibe is included in the generation payload. Disabled vibes
  /// stay in the list (and keep their encoded vector) but are filtered out of
  /// [VibeTransferNotifier.buildPayload], so toggling never re-encodes.
  final bool enabled;

  VibeTransfer({
    required this.id,
    required this.originalImageBytes,
    required this.processedPreview,
    required this.vibeVectorBase64,
    this.strength = 0.6,
    this.infoExtracted = 1.0,
    this.enabled = true,
  });

  VibeTransfer copyWith({
    double? strength,
    double? infoExtracted,
    bool? enabled,
  }) {
    return VibeTransfer(
      id: id,
      originalImageBytes: originalImageBytes,
      processedPreview: processedPreview,
      vibeVectorBase64: vibeVectorBase64,
      strength: strength ?? this.strength,
      infoExtracted: infoExtracted ?? this.infoExtracted,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'originalImageBytes': base64Encode(originalImageBytes),
        'vibeVectorBase64': vibeVectorBase64,
        'strength': strength,
        'infoExtracted': infoExtracted,
        'enabled': enabled,
      };

  factory VibeTransfer.fromJson(Map<String, dynamic> json) {
    final originalBytes = base64Decode(json['originalImageBytes'] as String);
    return VibeTransfer(
      id: json['id'] as String? ?? 'vibe_0',
      originalImageBytes: originalBytes,
      processedPreview: originalBytes, // Re-derived on load if needed
      vibeVectorBase64: json['vibeVectorBase64'] as String,
      strength: (json['strength'] as num?)?.toDouble() ?? 0.6,
      infoExtracted: (json['infoExtracted'] as num?)?.toDouble() ?? 1.0,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// DTO: the 3 parallel lists ready for API injection.
class VibeTransferPayload {
  final List<String> vibeVectors;
  final List<double> strengths;
  final List<double> infoExtracted;

  VibeTransferPayload({
    required this.vibeVectors,
    required this.strengths,
    required this.infoExtracted,
  });
}
