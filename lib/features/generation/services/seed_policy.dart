import 'dart:math' as math;

/// The largest seed the gateway and NovelAI accept for an image.
const int maxImageSeed = 0xFFFFFFFF;

/// The seed box holds something that is not a seed (empty, not a whole number,
/// or outside `0..4294967295`).
class InvalidSeedInput implements Exception {
  const InvalidSeedInput();

  @override
  String toString() => 'InvalidSeedInput';
}

/// A random seed over the whole range, including 0xFFFFFFFF.
int randomSeed([math.Random? source]) {
  // Two 16-bit draws work consistently on native and web.
  final random = source ?? math.Random();
  return random.nextInt(1 << 16) * (1 << 16) + random.nextInt(1 << 16);
}

/// The value of the seed box, or null when it is not a valid seed. Nothing is
/// rounded, wrapped or replaced: a value outside the range is invalid.
int? parseSeedInput(String text) {
  final trimmed = text.trim();
  if (!RegExp(r'^\d+$').hasMatch(trimmed)) return null;
  final value = BigInt.parse(trimmed);
  if (value > BigInt.from(maxImageSeed)) return null;
  return value.toInt();
}

/// The seeds of one run: [count] consecutive seeds from [fixedSeed], or
/// [count] distinct random ones.
List<int> buildBatchSeeds({
  required int count,
  required bool randomize,
  required int fixedSeed,
  math.Random? random,
}) {
  if (!randomize) {
    return List<int>.generate(
      count,
      (index) => (fixedSeed + index) & maxImageSeed,
    );
  }
  final source = random ?? math.Random();
  final used = <int>{};
  final seeds = <int>[];
  while (seeds.length < count) {
    final seed = randomSeed(source);
    if (used.add(seed)) seeds.add(seed);
  }
  return seeds;
}

/// The seeds a run will use, from the form: random ones, or the seed box
/// (throws [InvalidSeedInput] when it is not a valid seed).
List<int> resolveSeeds({
  required int count,
  required bool randomize,
  required String seedText,
}) {
  final fixed = randomize ? 0 : parseSeedInput(seedText);
  if (fixed == null) throw const InvalidSeedInput();
  return buildBatchSeeds(count: count, randomize: randomize, fixedSeed: fixed);
}
