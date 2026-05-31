import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/characters/outfit/outfit_classifier.dart';
import 'package:naiweaver/features/characters/outfit/outfit_renderer.dart';

void main() {
  group('renderItemsToTags / applyConcealment', () {
    test('intact outfit round-trips (concealed underwear hidden)', () {
      final r = applyConcealment(
          'white blouse, navy skirt, white cotton bra, white cotton panties, black tights, brown loafers');
      // Bra/panties are covered by an intact blouse/skirt → not in output.
      expect(r.tags.contains('cotton bra'), isFalse);
      expect(r.tags.contains('cotton panties'), isFalse);
      expect(r.tags.contains('white blouse'), isTrue);
      expect(r.tags.contains('navy skirt'), isTrue);
      expect(r.tags.contains('black tights'), isTrue);
      expect(r.isDishevelled, isFalse);
    });

    test('bra under open jacket is visible; under intact kimono hidden', () {
      // Open jacket — bra visible.
      final items1 = classifyOutfitTags('black leather jacket, blue bra, jeans');
      (items1['outerwear'] as Map)['state'] = 'open';
      final r1 = renderItemsToTags(items1);
      expect(r1.tags.contains('blue bra'), isTrue);

      // Intact kimono (closed-front) — bra hidden.
      final items2 = classifyOutfitTags('silk kimono jacket, red bra');
      final r2 = renderItemsToTags(items2);
      expect(r2.tags.contains('red bra'), isFalse);
    });

    test('intact armor hides the base top', () {
      final items = classifyOutfitTags('steel breastplate, linen tunic, leather boots');
      final r = renderItemsToTags(items);
      expect(r.tags.contains('breastplate'), isTrue);
      expect(r.tags.contains('linen tunic'), isFalse); // concealed by armor
      // ...but the top stays in the items map for continuity.
      expect(items.containsKey('top'), isTrue);
    });

    test('undress: top unbuttoned → verb tags', () {
      final items = classifyOutfitTags('white shirt, blue jeans');
      (items['top'] as Map)['state'] = 'unbuttoned';
      final r = renderItemsToTags(items);
      expect(r.tags.contains('unbuttoned shirt'), isTrue);
      expect(r.tags.contains('partially unbuttoned'), isTrue);
      expect(r.isDishevelled, isTrue);
    });

    test('undress: skirt lifted → skirt lift', () {
      final items = classifyOutfitTags('white shirt, red skirt');
      (items['bottom'] as Map)['state'] = 'lifted';
      final r = renderItemsToTags(items);
      expect(r.tags.contains('skirt lift'), isTrue);
      expect(r.tags.contains('clothes lift'), isTrue);
    });

    test('nudity consolidation: topless+bottomless → nude → completely nude', () {
      // Only top + bottom present, both removed → "nude" (legwear etc. absent).
      final items = classifyOutfitTags('white shirt, blue jeans, white socks, brown boots');
      (items['top'] as Map)['state'] = 'removed';
      (items['bottom'] as Map)['state'] = 'removed';
      // legwear/footwear still intact → just "nude", not "completely nude"
      var r = renderItemsToTags(items);
      expect(r.tags.contains('nude'), isTrue);
      expect(r.tags.contains('completely nude'), isFalse);
      // Now strip legwear + footwear too.
      (items['legwear'] as Map)['state'] = 'removed';
      (items['footwear'] as Map)['state'] = 'removed';
      r = renderItemsToTags(items);
      expect(r.tags.contains('completely nude'), isTrue);
      expect(r.tags.contains('topless'), isFalse);
      expect(r.tags.contains('bottomless'), isFalse);
    });

    test('half-bare cases stay topless / bottomless', () {
      final items = classifyOutfitTags('white shirt, blue jeans');
      (items['top'] as Map)['state'] = 'removed';
      final r = renderItemsToTags(items);
      expect(r.tags.contains('topless'), isTrue);
      expect(r.tags.contains('nude'), isFalse);
    });

    test('bra lifted → "bra lift" (not "bra aside")', () {
      // top removed so the bra is revealed; lifted = pushed up above breasts.
      final items = classifyOutfitTags('white shirt, red bra, blue jeans');
      (items['top'] as Map)['state'] = 'removed';
      (items['bra'] as Map)['state'] = 'lifted';
      final r = renderItemsToTags(items);
      expect(r.tags.contains('bra lift'), isTrue);
      expect(r.tags.contains('bra aside'), isFalse);
      expect(r.isDishevelled, isTrue);
    });

    test('bra pulled_down → "bra pull"', () {
      final items = classifyOutfitTags('white shirt, red bra, blue jeans');
      (items['top'] as Map)['state'] = 'removed';
      (items['bra'] as Map)['state'] = 'pulled_down';
      final r = renderItemsToTags(items);
      expect(r.tags.contains('bra pull'), isTrue);
    });

    test('legacy bra "aside" data remaps to the exposing "bra pull"', () {
      // Older saved closets may still carry state:"aside" on a bra. There is no
      // "bra aside" Danbooru tag, so it must render as "bra pull".
      final items = classifyOutfitTags('white shirt, red bra, blue jeans');
      (items['top'] as Map)['state'] = 'removed';
      (items['bra'] as Map)['state'] = 'aside';
      final r = renderItemsToTags(items);
      expect(r.tags.contains('bra pull'), isTrue);
      expect(r.tags.contains('bra aside'), isFalse);
    });

    test('visible intact bra suppresses "topless"', () {
      // top removed but a visible bra (no concealing outer layer) → no topless.
      final items = classifyOutfitTags('white shirt, red bra, blue jeans');
      // shirt removed; bra was concealed by intact shirt, now revealed & intact.
      (items['top'] as Map)['state'] = 'removed';
      final r = renderItemsToTags(items);
      expect(r.tags.contains('topless'), isFalse);
      expect(r.tags.contains('red bra'), isTrue);
    });

    test('barefoot suppressed when intact legwear present', () {
      final items = classifyOutfitTags('white shirt, blue jeans, black tights, brown boots');
      (items['footwear'] as Map)['state'] = 'removed';
      final r = renderItemsToTags(items);
      expect(r.tags.contains('barefoot'), isFalse);
    });

    test('isDishevelled false for plain intact outfit', () {
      final r = applyConcealment('white shirt, blue jeans, brown boots');
      expect(r.isDishevelled, isFalse);
    });

    test('empty input', () {
      expect(applyConcealment('').tags, '');
      expect(applyConcealment(null).tags, '');
    });
  });
}
