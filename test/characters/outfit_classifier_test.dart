import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/characters/outfit/outfit_classifier.dart';

void main() {
  group('classifyOutfitTags', () {
    test('basic garment buckets', () {
      final items = classifyOutfitTags(
          'cream knit sweater, navy pleated skirt, charcoal tights, brown ankle boots');
      expect(items.keys, containsAll(['top', 'bottom', 'legwear', 'footwear']));
      expect((items['top'] as Map)['garment'], 'cream knit sweater');
      expect((items['bottom'] as Map)['garment'], 'navy pleated skirt');
      // pleated skirt → bottom, tights → legwear, ankle boots → footwear
      expect((items['top'] as Map)['state'], 'intact');
    });

    test('whole-word matching: "bracers" → accessory, not bra', () {
      final items = classifyOutfitTags('leather bracers, white tunic');
      // bracers explicitly maps to accessory; tunic → top
      expect(items.containsKey('bra'), isFalse);
      expect(items.containsKey('accessory'), isTrue);
      expect(items.containsKey('top'), isTrue);
    });

    test('bloomers ambiguity: gym → bottom, plain → panties', () {
      final gym = classifyOutfitTags('gym bloomers, white shirt');
      expect(gym.containsKey('bottom'), isTrue);
      // buruma always bottom
      final buruma = classifyOutfitTags('buruma');
      expect(buruma.containsKey('bottom'), isTrue);
      final plain = classifyOutfitTags('cotton bloomers');
      expect(plain.containsKey('panties'), isTrue);
    });

    test('dress gets topState/bottomState, not state', () {
      final items = classifyOutfitTags('red sundress, brown sandals');
      final dress = items['dress'] as Map;
      expect(dress['top_state'], 'intact');
      expect(dress['bottom_state'], 'intact');
      expect(dress.containsKey('state'), isFalse);
    });

    test('accessory carries per-sub-item states', () {
      final items = classifyOutfitTags('white shirt, gold necklace, silver bracelet');
      final acc = items['accessory'] as Map;
      expect((acc['items'] as Map).keys, containsAll(['gold necklace', 'silver bracelet']));
      expect(acc['state'], 'intact');
    });

    test('unknown tags bucket into accessory', () {
      final items = classifyOutfitTags('white shirt, glorptronium widget');
      final acc = items['accessory'] as Map;
      expect((acc['items'] as Map).keys, contains('glorptronium widget'));
    });

    test('empty input → empty map', () {
      expect(classifyOutfitTags(''), isEmpty);
      expect(classifyOutfitTags(null), isEmpty);
      expect(classifyOutfitTags('   '), isEmpty);
    });

    test('armor torso piece classifies to armor', () {
      final items = classifyOutfitTags('steel breastplate, linen tunic, leather boots');
      expect(items.containsKey('armor'), isTrue);
      expect(items.containsKey('top'), isTrue); // tunic stays
    });
  });

  group('classifySingleTag', () {
    test('exact + substring fallback', () {
      expect(classifySingleTag('blouse'), 'top');
      expect(classifySingleTag('cream knit sweater'), 'top'); // substring on "sweater"
      expect(classifySingleTag('pleated skirt'), 'bottom');
      expect(classifySingleTag('totally unknown thing'), isNull);
    });
  });
}
