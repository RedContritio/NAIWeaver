import 'dart:convert';

class Img2ImgPreset {
  final String name;
  final double strength;
  final double noise;
  final bool colorCorrect;
  final int maskBlur;

  const Img2ImgPreset({
    required this.name,
    this.strength = 1.0,
    this.noise = 0.0,
    this.colorCorrect = true,
    this.maskBlur = 0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'strength': strength,
    'noise': noise,
    'colorCorrect': colorCorrect,
    'maskBlur': maskBlur,
  };

  factory Img2ImgPreset.fromJson(Map<String, dynamic> json) => Img2ImgPreset(
    name: json['name'] as String,
    strength: (json['strength'] as num?)?.toDouble() ?? 1.0,
    noise: (json['noise'] as num?)?.toDouble() ?? 0.0,
    colorCorrect: json['colorCorrect'] as bool? ?? true,
    maskBlur: json['maskBlur'] as int? ?? 0,
  );

  static List<Img2ImgPreset> listFromJson(String jsonStr) {
    if (jsonStr.isEmpty) return [];
    final list = jsonDecode(jsonStr) as List;
    return list.map((e) => Img2ImgPreset.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<Img2ImgPreset> presets) =>
      jsonEncode(presets.map((p) => p.toJson()).toList());
}
