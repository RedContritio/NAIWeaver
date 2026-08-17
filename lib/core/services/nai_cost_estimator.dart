import 'dart:math' as math;

const double _areaCoefficient = 2.951823174884865e-6;
const double _stepAreaCoefficient = 5.753298233447344e-7;
const int _opusFreeMaxPixels = 1024 * 1024;
const int _opusFreeMaxSteps = 28;
const int _preciseReferenceAnlas = 5;
const int _extraVibeAnlas = 2;

class NaiImageCostEstimate {
  final int totalAnlas;
  final int baseAnlas;
  final int directorReferenceAnlas;
  final int vibeReferenceAnlas;
  final int perImageBaseAnlas;
  final int serialImages;
  final bool opusBaseDiscountApplied;

  const NaiImageCostEstimate({
    required this.totalAnlas,
    required this.baseAnlas,
    required this.directorReferenceAnlas,
    required this.vibeReferenceAnlas,
    required this.perImageBaseAnlas,
    required this.serialImages,
    required this.opusBaseDiscountApplied,
  });

  bool get isZeroCost => totalAnlas == 0;
  bool get hasReferenceCost => directorReferenceAnlas > 0;
  bool get hasVibeCost => vibeReferenceAnlas > 0;
}

bool isOpusFreeBaseImage({
  required int width,
  required int height,
  required int steps,
  required bool hasImageInput,
}) {
  return !hasImageInput &&
      width * height <= _opusFreeMaxPixels &&
      steps <= _opusFreeMaxSteps;
}

NaiImageCostEstimate estimateNaiImageCost({
  required int width,
  required int height,
  required int steps,
  required bool smea,
  required bool smeaDyn,
  int serialImages = 1,
  bool isOpus = true,
  bool hasImageInput = false,
  double strengthFactor = 1.0,
  int directorReferenceCount = 0,
  int vibeReferenceCount = 0,
}) {
  final imageCount = math.max(1, serialImages);
  final area = math.max(1, width) * math.max(1, height);
  final multiplier = smeaDyn ? 1.4 : (smea ? 1.2 : 1.0);
  final rawBase =
      (_areaCoefficient * area) + (_stepAreaCoefficient * area * steps);
  final weightedBase = rawBase.ceil() * multiplier;
  final perImageBase = math.max((weightedBase * strengthFactor).ceil(), 2);
  final opusBaseDiscountApplied =
      isOpus &&
      isOpusFreeBaseImage(
        width: width,
        height: height,
        steps: steps,
        hasImageInput: hasImageInput,
      );
  final baseAnlas = opusBaseDiscountApplied ? 0 : perImageBase * imageCount;
  final directorAnlas =
      math.max(0, directorReferenceCount) * _preciseReferenceAnlas * imageCount;
  final extraVibes = math.max(0, vibeReferenceCount - 4);
  final vibeAnlas = extraVibes * _extraVibeAnlas * imageCount;

  return NaiImageCostEstimate(
    totalAnlas: baseAnlas + directorAnlas + vibeAnlas,
    baseAnlas: baseAnlas,
    directorReferenceAnlas: directorAnlas,
    vibeReferenceAnlas: vibeAnlas,
    perImageBaseAnlas: perImageBase,
    serialImages: imageCount,
    opusBaseDiscountApplied: opusBaseDiscountApplied,
  );
}
