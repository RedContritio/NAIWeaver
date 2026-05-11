import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/characters/outfit/outfit_classifier.dart';
import 'package:naiweaver/features/characters/outfit/outfit_delta.dart';

void main() {
  group('applyOutfitDelta', () {
    test('valid state change applies; turns reset', () {
      final items = classifyOutfitTags('white shirt, blue jeans');
      applyOutfitDelta(items, {
        'top': {'state': 'unbuttoned', 'mentioned': true}
      }, 1);
      expect((items['top'] as Map)['state'], 'unbuttoned');
      expect((items['top'] as Map)['turns_in_state'], 0);
      expect((items['top'] as Map)['last_mentioned_turn'], 1);
    });

    test('invalid (slot, state) is rejected', () {
      final items = classifyOutfitTags('red skirt, white shirt');
      applyOutfitDelta(items, {
        'bottom': {'state': 'aside'} // aside is NOT valid for bottom
      }, 1);
      expect((items['bottom'] as Map)['state'], 'intact'); // unchanged
    });

    test('unknown slot ignored', () {
      final items = classifyOutfitTags('white shirt');
      applyOutfitDelta(items, {
        'cape': {'state': 'removed'}
      }, 1);
      expect(items.containsKey('cape'), isFalse);
    });

    test('layer reroute: top:removed + intact outerwear → outerwear:removed', () {
      final items = classifyOutfitTags('navy cardigan, white tank top, jeans');
      // top:removed alone, outerwear not in delta, outerwear intact → reroute.
      applyOutfitDelta(items, {
        'top': {'state': 'removed'}
      }, 1);
      expect((items['outerwear'] as Map)['state'], 'removed');
      expect((items['top'] as Map)['state'], 'intact'); // tank top survives
    });

    test('no reroute when outerwear is also in the delta', () {
      final items = classifyOutfitTags('navy cardigan, white tank top, jeans');
      applyOutfitDelta(items, {
        'top': {'state': 'removed'},
        'outerwear': {'state': 'removed'}
      }, 1);
      expect((items['top'] as Map)['state'], 'removed');
      expect((items['outerwear'] as Map)['state'], 'removed');
    });

    test('decay: non-intact slot not in delta ages by one', () {
      final items = classifyOutfitTags('white shirt, jeans');
      (items['top'] as Map)['state'] = 'open';
      (items['top'] as Map)['turns_in_state'] = 2;
      applyOutfitDelta(items, {
        'bottom': {'state': 'pulled_down'}
      }, 2);
      expect((items['top'] as Map)['turns_in_state'], 3);
    });

    test('dress top/bottom states validated independently', () {
      final items = classifyOutfitTags('red dress, sandals');
      applyOutfitDelta(items, {
        'dress': {'top_state': 'pulled_down', 'bottom_state': 'lifted'}
      }, 1);
      expect((items['dress'] as Map)['top_state'], 'pulled_down');
      expect((items['dress'] as Map)['bottom_state'], 'lifted');
      // invalid top_state rejected
      applyOutfitDelta(items, {
        'dress': {'top_state': 'around_ankles'}
      }, 2);
      expect((items['dress'] as Map)['top_state'], 'pulled_down'); // unchanged
    });
  });

  group('filterFreshDelta', () {
    test('scrubs removal-type transitions from first post-swap delta', () {
      final cleaned = filterFreshDelta({
        'top': {'state': 'removed'},
        'bottom': {'state': 'unbuttoned'},
        'bra': {'state': 'pulled_down'},
      });
      expect(cleaned.containsKey('top'), isFalse); // removed scrubbed
      expect(cleaned.containsKey('bra'), isFalse); // pulled_down scrubbed
      expect(cleaned.containsKey('bottom'), isTrue); // unbuttoned passes
    });

    test('null/empty delta → empty', () {
      expect(filterFreshDelta(null), isEmpty);
      expect(filterFreshDelta({}), isEmpty);
    });

    test('dress half-state scrub', () {
      final cleaned = filterFreshDelta({
        'dress': {'top_state': 'removed', 'bottom_state': 'intact'}
      });
      // top_state removed → scrubbed; bottom_state intact survives → entry kept.
      expect((cleaned['dress'] as Map).containsKey('top_state'), isFalse);
      expect((cleaned['dress'] as Map)['bottom_state'], 'intact');
    });
  });

  group('resetItemsToIntact', () {
    test('sets all slots intact', () {
      final items = classifyOutfitTags('white shirt, red dress, jeans, gold necklace');
      (items['top'] as Map)['state'] = 'open';
      (items['dress'] as Map)['top_state'] = 'pulled_down';
      ((items['accessory'] as Map)['items'] as Map).values.first['state'] = 'removed';
      resetItemsToIntact(items);
      expect((items['top'] as Map)['state'], 'intact');
      expect((items['dress'] as Map)['top_state'], 'intact');
      expect((items['dress'] as Map)['bottom_state'], 'intact');
      expect(((items['accessory'] as Map)['items'] as Map).values.first['state'], 'intact');
    });
  });
}
