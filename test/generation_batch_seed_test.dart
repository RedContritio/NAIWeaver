import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/generation/services/seed_policy.dart';

void main() {
  group('buildBatchSeeds', () {
    test('increments a fixed seed and wraps across uint32', () {
      final seeds = buildBatchSeeds(
        count: 4,
        randomize: false,
        fixedSeed: 0xFFFFFFFE,
      );

      expect(seeds, [0xFFFFFFFE, 0xFFFFFFFF, 0, 1]);
    });

    test('produces unique random uint32 seeds within one batch', () {
      final seeds = buildBatchSeeds(
        count: 10,
        randomize: true,
        fixedSeed: 0,
        random: math.Random(42),
      );

      expect(seeds.toSet(), hasLength(seeds.length));
      expect(seeds, everyElement(inInclusiveRange(0, 0xFFFFFFFF)));
    });
  });

  group('the seed box', () {
    test('accepts exactly 0..4294967295', () {
      expect(parseSeedInput('0'), 0);
      expect(parseSeedInput(' 4294967295 '), 4294967295);
      expect(parseSeedInput('4294967296'), isNull);
      // Past 2^63 nothing wraps to 0 or is replaced by a random seed.
      expect(parseSeedInput('9223372036854775808'), isNull);
      expect(parseSeedInput('99999999999999999999999'), isNull);
    });

    test('rejects what is not a whole number instead of using 0', () {
      for (final text in ['', 'abc', '-1', '1.5', '1e3', '12 3']) {
        expect(parseSeedInput(text), isNull, reason: text);
        expect(
          () => resolveSeeds(count: 2, randomize: false, seedText: text),
          throwsA(isA<InvalidSeedInput>()),
          reason: text,
        );
      }
    });

    test('is ignored while the seeds are random', () {
      final seeds = resolveSeeds(
        count: 3,
        randomize: true,
        seedText: 'not a seed',
      );
      expect(seeds, hasLength(3));
    });
  });
}
