import 'dart:math' as math;

import 'backend_exception.dart';
import 'backend_rules.dart';

/// How a request is charged (docs/GATEWAY_CONTRACT.md §3).
abstract final class QuoteMode {
  static const free = 'free';
  static const paid = 'paid';
}

/// Why a request is `paid`, in the contract's canonical order.
abstract final class QuoteReason {
  static const sizeNotFree = 'size_not_free';
  static const stepsOverFreeLimit = 'steps_over_free_limit';
  static const smea = 'smea';
  static const imageInput = 'image_input';
  static const directorRefs = 'director_refs';
  static const vibes = 'vibes';
  static const allowanceExhausted = 'allowance_exhausted';
  static const paidTool = 'paid_tool';

  static const ordered = [
    sizeNotFree,
    stepsOverFreeLimit,
    smea,
    imageInput,
    directorRefs,
    vibes,
    allowanceExhausted,
    paidTool,
  ];
}

/// The request cannot be priced because the gateway would reject it.
/// [field] names the offending request path, as in the gateway's
/// `invalid_parameters` error.
class InvalidQuoteRequest implements Exception {
  const InvalidQuoteRequest(this.field);

  final String field;

  /// The `invalid_parameters` error the gateway would answer with.
  BackendException toBackendException() => BackendException(
    statusCode: null,
    code: BackendErrorCode.invalidParameters,
    details: {'field': field},
  );

  @override
  String toString() => 'InvalidQuoteRequest($field)';
}

/// The price of one image request times its seeds.
class ImageQuote {
  const ImageQuote({
    required this.mode,
    required this.perImage,
    required this.images,
    required this.base,
    required this.directorRefs,
    required this.extraVibes,
    required this.reasons,
  });

  final String mode;
  final int perImage;
  final int images;
  final int base;
  final int directorRefs;
  final int extraVibes;
  final List<String> reasons;

  int get points => perImage * images;

  bool get isPaid => mode == QuoteMode.paid;

  /// The `expected_quote` of a submission (§4).
  Map<String, dynamic> toExpectedQuote() => {'mode': mode, 'points': points};
}

const _requestKeys = {'input', 'model', 'action', 'parameters'};
const _imageActions = {null, 'generate', 'img2img', 'infill'};
const _imageInputParameters = [
  'image',
  'mask',
  'strength',
  'noise',
  'extra_noise_seed',
  'add_original_image',
  'mask_blur',
];
const _directorReferenceParameters = [
  'director_reference_images',
  'director_reference_descriptions',
  'director_reference_strength_values',
  'director_reference_secondary_strength_values',
  'director_reference_information_extracted',
];
const _vibeParameters = [
  'reference_image_multiple',
  'reference_strength_multiple',
  'reference_information_extracted_multiple',
];
const _allowedParameters = {
  'params_version',
  'width',
  'height',
  'scale',
  'sampler',
  'steps',
  'seed',
  'n_samples',
  'noise_schedule',
  'sm',
  'sm_dyn',
  'autoSmea',
  'dynamic_thresholding',
  'uc',
  'characterPrompts',
  'v4_prompt',
  'v4_negative_prompt',
  ..._imageInputParameters,
  ..._directorReferenceParameters,
  ..._vibeParameters,
};

/// Prices [request] (the body of an image generation, exactly as it will be
/// sent) for [images] seeds, the way the gateway's `classify_and_quote` does.
/// The gateway's quote is the one that is charged; this is its instant
/// estimate from [rules]. Throws [InvalidQuoteRequest] where the gateway
/// would answer `invalid_parameters`.
ImageQuote quoteImageRequest(
  ImageRules rules,
  Map<String, dynamic> request, {
  required int images,
}) {
  if (images < 1) throw const InvalidQuoteRequest('seeds');
  for (final key in request.keys) {
    if (!_requestKeys.contains(key)) throw InvalidQuoteRequest(key);
  }
  final action = request['action'];
  if (!_imageActions.contains(action)) {
    throw const InvalidQuoteRequest('action');
  }
  final params = request['parameters'];
  if (params is! Map<String, dynamic>) {
    throw const InvalidQuoteRequest('parameters');
  }
  for (final key in params.keys) {
    if (!_allowedParameters.contains(key)) {
      throw InvalidQuoteRequest('parameters.$key');
    }
  }

  final width = _integer(params, 'width');
  final height = _integer(params, 'height');
  final steps = _integer(params, 'steps');
  for (final (key, value) in [('width', width), ('height', height)]) {
    if (value < 64 || value > rules.maxDimension || value % 64 != 0) {
      throw InvalidQuoteRequest(key);
    }
  }
  if (steps < 1 || steps > rules.maxSteps) {
    throw const InvalidQuoteRequest('steps');
  }
  final sampler = params['sampler'];
  if (sampler is! String || !rules.allowedSamplers.contains(sampler)) {
    throw const InvalidQuoteRequest('sampler');
  }
  final scale = params['scale'];
  if (scale != null && (scale is! num || !scale.isFinite)) {
    throw const InvalidQuoteRequest('scale');
  }
  final smea = _flag(params, 'sm');
  final smeaDyn = _flag(params, 'sm_dyn');
  final autoSmea = _flag(params, 'autoSmea');
  final directorCount = _listLength(params, 'director_reference_images');
  final vibeCount = _listLength(params, 'reference_image_multiple');

  bool filled(String key) {
    final value = params[key];
    return value != null && !_isEmpty(value);
  }

  final reasons = <String>{};
  if (action != null && action != 'generate') {
    reasons.add(QuoteReason.imageInput);
  }
  if (!rules.freeSizes.any((s) => s.width == width && s.height == height)) {
    reasons.add(QuoteReason.sizeNotFree);
  }
  if (steps > rules.freeMaxSteps) reasons.add(QuoteReason.stepsOverFreeLimit);
  if (smea || smeaDyn || autoSmea) reasons.add(QuoteReason.smea);
  if (_imageInputParameters.any(filled)) reasons.add(QuoteReason.imageInput);
  if (_directorReferenceParameters.any(filled)) {
    reasons.add(QuoteReason.directorRefs);
  }
  if (_vibeParameters.any(filled)) reasons.add(QuoteReason.vibes);
  if (reasons.isEmpty && rules.freeAllowanceExhausted) {
    reasons.add(QuoteReason.allowanceExhausted);
  }

  final pricing = rules.pricing;
  // Left to right in IEEE-754 doubles, as the gateway does (§3).
  final raw =
      pricing.areaCoefficient * width * height +
      pricing.stepAreaCoefficient * width * height * steps;
  final multiplier = smeaDyn
      ? pricing.smeaDynMultiplier
      : (smea || autoSmea)
      ? pricing.smeaMultiplier
      : 1.0;
  final base = math.max((raw.ceil() * multiplier).ceil(), pricing.minPoints);
  final directorPoints = directorCount * pricing.directorReferencePoints;
  final vibePoints =
      math.max(0, vibeCount - pricing.freeVibeCount) * pricing.extraVibePoints;
  final points = base + directorPoints + vibePoints;

  final paid = reasons.isNotEmpty;
  final discount = rules.greenPointDiscount.clamp(0, 100);
  return ImageQuote(
    mode: paid ? QuoteMode.paid : QuoteMode.free,
    perImage: paid ? points : (points * (100 - discount) + 99) ~/ 100,
    images: images,
    base: base,
    directorRefs: directorPoints,
    extraVibes: vibePoints,
    reasons: [
      for (final reason in QuoteReason.ordered)
        if (reasons.contains(reason)) reason,
    ],
  );
}

/// A JSON integer; the gateway rejects bools, floats and strings.
int _integer(Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value is! int) throw InvalidQuoteRequest(key);
  return value;
}

bool _flag(Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value == null) return false;
  if (value is! bool) throw InvalidQuoteRequest(key);
  return value;
}

int _listLength(Map<String, dynamic> params, String key) {
  final value = params[key];
  if (value == null) return 0;
  if (value is! List) throw InvalidQuoteRequest(key);
  return value.length;
}

/// Python truthiness of an empty JSON value.
bool _isEmpty(Object value) => switch (value) {
  final String s => s.isEmpty,
  final List<dynamic> l => l.isEmpty,
  final Map<dynamic, dynamic> m => m.isEmpty,
  final bool b => !b,
  final num n => n == 0,
  _ => false,
};
