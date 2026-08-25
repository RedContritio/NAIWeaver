import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/generation/providers/generation_notifier.dart';

void main() {
  group('GenerationNotifier.buildBatchSeeds', () {
    test('increments a fixed seed and wraps across uint32', () {
      final seeds = GenerationNotifier.buildBatchSeeds(
        count: 4,
        randomize: false,
        fixedSeed: 0xFFFFFFFE,
      );

      expect(seeds, [0xFFFFFFFE, 0xFFFFFFFF, 0, 1]);
    });

    test('produces unique random uint32 seeds within one batch', () {
      final seeds = GenerationNotifier.buildBatchSeeds(
        count: 10,
        randomize: true,
        fixedSeed: 0,
        random: math.Random(42),
      );

      expect(seeds.toSet(), hasLength(seeds.length));
      expect(seeds, everyElement(inInclusiveRange(0, 0xFFFFFFFF)));
    });
  });
}
