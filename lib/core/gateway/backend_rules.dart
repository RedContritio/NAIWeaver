/// The pricing and limit rules of `GET /api/me` → `rules.image`
/// (docs/GATEWAY_CONTRACT.md §2).
class ImageRules {
  const ImageRules({
    required this.freeSizes,
    required this.freeMaxSteps,
    required this.maxSteps,
    required this.maxDimension,
    required this.allowedSamplers,
    required this.batchLimit,
    required this.greenPointDiscount,
    required this.freeAllowanceExhausted,
    required this.pricing,
    required this.toolCaps,
  });

  final List<({int width, int height})> freeSizes;
  final int freeMaxSteps;
  final int maxSteps;
  final int maxDimension;
  final List<String> allowedSamplers;
  final int batchLimit;
  final int greenPointDiscount;
  final bool freeAllowanceExhausted;
  final ImagePricing pricing;
  final ToolCaps toolCaps;

  /// Null when [json] is not the `rules` object of the contract.
  static ImageRules? tryParse(Object? rules) {
    final image = rules is Map<String, dynamic> ? rules['image'] : null;
    if (image is! Map<String, dynamic>) return null;
    int integer(String key, int fallback) =>
        (image[key] as num?)?.toInt() ?? fallback;
    final sizes = <({int width, int height})>[];
    for (final entry in image['free_sizes'] as List<dynamic>? ?? const []) {
      if (entry is List && entry.length == 2) {
        sizes.add((
          width: (entry[0] as num).toInt(),
          height: (entry[1] as num).toInt(),
        ));
      }
    }
    return ImageRules(
      freeSizes: sizes,
      freeMaxSteps: integer('free_max_steps', 0),
      maxSteps: integer('max_steps', 0),
      maxDimension: integer('max_dimension', 0),
      allowedSamplers: [
        for (final sampler in image['allowed_samplers'] as List<dynamic>? ?? [])
          sampler.toString(),
      ],
      batchLimit: integer('batch_limit', 1),
      greenPointDiscount: integer('green_point_discount', 0),
      freeAllowanceExhausted: image['free_allowance_exhausted'] == true,
      pricing: ImagePricing.fromJson(
        image['pricing'] as Map<String, dynamic>? ?? const {},
      ),
      toolCaps: ToolCaps.fromJson(
        image['tool_caps'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class ImagePricing {
  const ImagePricing({
    required this.areaCoefficient,
    required this.stepAreaCoefficient,
    required this.smeaMultiplier,
    required this.smeaDynMultiplier,
    required this.minPoints,
    required this.directorReferencePoints,
    required this.freeVibeCount,
    required this.extraVibePoints,
  });

  final double areaCoefficient;
  final double stepAreaCoefficient;
  final double smeaMultiplier;
  final double smeaDynMultiplier;
  final int minPoints;
  final int directorReferencePoints;
  final int freeVibeCount;
  final int extraVibePoints;

  factory ImagePricing.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;
    int integer(String key) => (json[key] as num?)?.toInt() ?? 0;
    return ImagePricing(
      areaCoefficient: number('area_coefficient'),
      stepAreaCoefficient: number('step_area_coefficient'),
      smeaMultiplier: number('smea_multiplier'),
      smeaDynMultiplier: number('smea_dyn_multiplier'),
      minPoints: integer('min_points'),
      directorReferencePoints: integer('director_reference_points'),
      freeVibeCount: integer('free_vibe_count'),
      extraVibePoints: integer('extra_vibe_points'),
    );
  }
}

/// Fixed prices of the paid tools; sent as `X-NAIWeaver-Expected-Points`.
class ToolCaps {
  const ToolCaps({
    required this.upscale,
    required this.augment,
    required this.encodeVibe,
  });

  final int upscale;
  final int augment;
  final int encodeVibe;

  factory ToolCaps.fromJson(Map<String, dynamic> json) => ToolCaps(
    upscale: (json['upscale'] as num?)?.toInt() ?? 0,
    augment: (json['augment'] as num?)?.toInt() ?? 0,
    encodeVibe: (json['encode_vibe'] as num?)?.toInt() ?? 0,
  );
}
