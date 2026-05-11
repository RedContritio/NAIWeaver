import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/features/characters/models/closet_outfit.dart';
import 'package:naiweaver/features/characters/models/saved_character.dart';

void main() {
  group('SavedCharacter JSON round-trip', () {
    test('full record', () {
      final c = SavedCharacter(
        id: 'abc123def456',
        name: 'Yuki',
        gender: 'female',
        baseTags: '1girl, japanese',
        faceTags: 'blue eyes',
        hairTags: 'long black hair',
        bodyTags: 'slender',
        nsfwAlways: 'pussy',
        artistTag: 'wlop',
        stylePrefix: 'masterpiece',
        characterDescription: 'A quiet bookish girl.',
        themeAccent: '#FF8800',
        primaryOutfitId: 'out1',
        notes: 'protagonist',
      );
      final round = SavedCharacter.fromJson(c.toJson());
      expect(round.id, c.id);
      expect(round.name, 'Yuki');
      expect(round.gender, 'female');
      expect(round.baseTags, '1girl, japanese');
      expect(round.faceTags, 'blue eyes');
      expect(round.hairTags, 'long black hair');
      expect(round.bodyTags_, 'slender');
      expect(round.nsfwAlways, 'pussy');
      expect(round.artistTag, 'wlop');
      expect(round.stylePrefix, 'masterpiece');
      expect(round.characterDescription, 'A quiet bookish girl.');
      expect(round.themeAccent, '#FF8800');
      expect(round.primaryOutfitId, 'out1');
      expect(round.notes, 'protagonist');
      expect(round.derivedBodyTags, '1girl, japanese, blue eyes, long black hair, slender');
    });

    test('minimal record', () {
      final c = SavedCharacter.create(name: 'Bob');
      final round = SavedCharacter.fromJson(c.toJson());
      expect(round.name, 'Bob');
      expect(round.id.length, greaterThanOrEqualTo(8));
      expect(round.derivedBodyTags, '');
    });

    test('copyWith sentinel clears nullable theme/primary', () {
      final c = SavedCharacter.create(name: 'X').copyWith(
          themeAccent: '#112233', primaryOutfitId: 'p1');
      final cleared = c.copyWith(themeAccent: null, primaryOutfitId: null);
      expect(cleared.themeAccent, isNull);
      expect(cleared.primaryOutfitId, isNull);
      // unchanged field stays
      final still = c.copyWith(name: 'Y');
      expect(still.themeAccent, '#112233');
      expect(still.primaryOutfitId, 'p1');
    });

    test('toNaiCharacter composes body + outfit + nsfw', () {
      final c = SavedCharacter(
        id: 'i', name: 'Z', baseTags: '1girl', stylePrefix: 'best quality',
        artistTag: 'someartist',
      );
      final n = c.toNaiCharacter(outfitTags: 'red dress', dishevelled: true);
      expect(n.name, 'Z');
      expect(n.prompt, 'best quality, 1girl, red dress, nsfw, someartist');
    });
  });

  group('ClosetOutfit JSON round-trip', () {
    test('full record with items', () {
      final o = ClosetOutfit(
        id: 'out12345',
        name: 'Rainy Day Chic',
        tags: 'yellow raincoat, white shirt, jeans, rubber boots',
        seasons: ['fall', 'spring'],
        weather: ['rain', 'cloudy'],
        activities: ['casual', 'outdoor'],
        temperatureRange: [5, 18],
        slots: ['daytime'],
        items: {
          'top': {'garment': 'white shirt', 'base_tags': 'white shirt', 'state': 'intact', 'turns_in_state': 0}
        },
      );
      final round = ClosetOutfit.fromJson(o.toJson());
      expect(round.id, 'out12345');
      expect(round.name, 'Rainy Day Chic');
      expect(round.tags, 'yellow raincoat, white shirt, jeans, rubber boots');
      expect(round.seasons, ['fall', 'spring']);
      expect(round.weather, ['rain', 'cloudy']);
      expect(round.activities, ['casual', 'outdoor']);
      expect(round.temperatureRange, [5, 18]);
      expect(round.slots, ['daytime']);
      expect((round.items!['top'] as Map)['garment'], 'white shirt');
    });

    test('defaults: empty arrays, [-10,35] temp range', () {
      final o = ClosetOutfit.create(name: 'Plain');
      expect(o.temperatureRange, [-10, 35]);
      expect(o.seasons, isEmpty);
      final round = ClosetOutfit.fromJson(o.toJson());
      expect(round.temperatureRange, [-10, 35]);
    });

    test('fromGeneratedJson maps snake_case + assigns id', () {
      final o = ClosetOutfit.fromGeneratedJson({
        'name': 'Summer Festival',
        'tags': 'blue yukata, geta',
        'seasons': ['summer'],
        'weather': ['hot', 'mild'],
        'activities': ['casual'],
        'temperature_range': [22, 34],
        'slots': ['evening'],
      });
      expect(o.name, 'Summer Festival');
      expect(o.tags, 'blue yukata, geta');
      expect(o.temperatureRange, [22, 34]);
      expect(o.slots, ['evening']);
      expect(o.id.isNotEmpty, isTrue);
    });

    test('fromGeneratedJson filters bogus enum values', () {
      final o = ClosetOutfit.fromGeneratedJson({
        'name': 'X',
        'tags': 'a, b',
        'seasons': ['summer', 'monsoon'], // monsoon not valid
        'weather': ['rain', 'apocalypse'],
      });
      expect(o.seasons, ['summer']);
      expect(o.weather, ['rain']);
    });
  });
}
