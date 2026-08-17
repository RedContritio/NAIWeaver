import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/nai_cost_estimator.dart';

void main() {
  group('estimateNaiImageCost', () {
    test('treats Opus normal serial images as zero Anlas', () {
      final estimate = estimateNaiImageCost(
        width: 832,
        height: 1216,
        steps: 28,
        smea: false,
        smeaDyn: false,
        serialImages: 4,
      );

      expect(estimate.totalAnlas, 0);
      expect(estimate.baseAnlas, 0);
      expect(estimate.opusBaseDiscountApplied, isTrue);
      expect(estimate.serialImages, 4);
    });

    test('adds precise reference cost per serial image', () {
      final estimate = estimateNaiImageCost(
        width: 1024,
        height: 1024,
        steps: 28,
        smea: false,
        smeaDyn: false,
        serialImages: 2,
        directorReferenceCount: 2,
      );

      expect(estimate.baseAnlas, 0);
      expect(estimate.directorReferenceAnlas, 20);
      expect(estimate.totalAnlas, 20);
    });

    test('adds Vibe generation cost only above four vibes', () {
      final estimate = estimateNaiImageCost(
        width: 1024,
        height: 1024,
        steps: 28,
        smea: false,
        smeaDyn: false,
        serialImages: 3,
        vibeReferenceCount: 5,
      );

      expect(estimate.baseAnlas, 0);
      expect(estimate.vibeReferenceAnlas, 6);
      expect(estimate.totalAnlas, 6);
    });

    test(
      'keeps the Opus base discount with SMEA like the official frontend',
      () {
        final estimate = estimateNaiImageCost(
          width: 1024,
          height: 1024,
          steps: 28,
          smea: true,
          smeaDyn: false,
        );

        expect(estimate.baseAnlas, 0);
        expect(estimate.totalAnlas, 0);
        expect(estimate.opusBaseDiscountApplied, isTrue);
      },
    );

    test('charges base Anlas above the Opus free size limit', () {
      final estimate = estimateNaiImageCost(
        width: 1216,
        height: 1216,
        steps: 28,
        smea: false,
        smeaDyn: false,
      );

      expect(estimate.baseAnlas, greaterThan(0));
      expect(estimate.totalAnlas, estimate.baseAnlas);
      expect(estimate.opusBaseDiscountApplied, isFalse);
    });
  });
}
