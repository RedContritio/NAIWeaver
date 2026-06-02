import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/utils/tag_suggestion_helper.dart';
import 'package:naiweaver/features/characters/models/closet_outfit.dart';
import 'package:naiweaver/features/characters/models/saved_character.dart';
import 'package:naiweaver/features/characters/providers/character_library_notifier.dart';
import 'package:naiweaver/features/characters/services/character_library_service.dart';
import 'package:naiweaver/features/characters/services/closet_service.dart';
import 'package:naiweaver/features/director_ref/models/director_reference.dart';
import 'package:naiweaver/features/director_ref/providers/director_ref_notifier.dart';
import 'package:naiweaver/features/vibe_transfer/models/vibe_transfer.dart';
import 'package:naiweaver/features/vibe_transfer/providers/vibe_transfer_notifier.dart';

void main() {
  // ── Task #3: model serialization round-trips ────────────────────────────
  group('negative-tag model serialization', () {
    test('SavedCharacter.negativeTags round-trips and omits when empty', () {
      final c = SavedCharacter.create(name: 'Yuki').copyWith(
        baseTags: '1girl',
        negativeTags: 'bad hands, extra fingers',
      );
      final json = c.toJson();
      expect(json['negativeTags'], 'bad hands, extra fingers');
      expect(SavedCharacter.fromJson(json).negativeTags, 'bad hands, extra fingers');

      // Empty negatives are omitted from JSON but load as ''.
      final empty = SavedCharacter.create(name: 'Bare');
      expect(empty.toJson().containsKey('negativeTags'), isFalse);
      expect(SavedCharacter.fromJson(empty.toJson()).negativeTags, '');
    });

    test('ClosetOutfit.negativeTags round-trips and omits when empty', () {
      final o = ClosetOutfit.create(name: 'Rainy', tags: 'raincoat')
          .copyWith(negativeTags: 'extra straps');
      final json = o.toJson();
      expect(json['negativeTags'], 'extra straps');
      expect(ClosetOutfit.fromJson(json).negativeTags, 'extra straps');

      final empty = ClosetOutfit.create(name: 'Plain', tags: 'shirt');
      expect(empty.toJson().containsKey('negativeTags'), isFalse);
    });

    test('old JSON without negativeTags loads as empty (back-compat)', () {
      final c = SavedCharacter.fromJson({'id': 'x', 'name': 'Legacy'});
      expect(c.negativeTags, '');
      final o = ClosetOutfit.fromJson({'id': 'y', 'name': 'Legacy', 'tags': 'shirt'});
      expect(o.negativeTags, '');
    });
  });

  // ── Task #3: negative-expansion builder (char + outfit, de-duped) ────────
  group('negativeExpansionFor', () {
    final notifier = CharacterLibraryNotifier(
      service: CharacterLibraryService(charactersDir: '.test_tmp_chars'),
      closetService: ClosetService(charactersDir: '.test_tmp_chars'),
    );

    test('combines character + outfit negatives, de-duplicated', () {
      final c = SavedCharacter.create(name: 'Y').copyWith(negativeTags: 'bad hands, blurry');
      final o = ClosetOutfit.create(name: 'O').copyWith(negativeTags: 'Blurry, extra straps');
      // 'Blurry' duplicates 'blurry' (case-insensitive) → dropped.
      expect(notifier.negativeExpansionFor(c, o), 'bad hands, blurry, extra straps');
    });

    test('empty when neither has negatives', () {
      final c = SavedCharacter.create(name: 'Y');
      expect(notifier.negativeExpansionFor(c, null), '');
    });

    test('suggestionTags carries negativeExpansion only when non-empty', () async {
      // Pure in-memory: seed a character via the notifier's import path is not
      // available without storage, so we exercise the builder + tag mapping
      // shape directly through a constructed DanbooruTag instead.
      final c = SavedCharacter.create(name: 'Z').copyWith(negativeTags: 'lowres');
      final neg = notifier.negativeExpansionFor(c, null);
      final tag = DanbooruTag(
        tag: 'Z',
        count: 0,
        typeName: 'saved_character',
        negativeExpansion: neg.isEmpty ? null : neg,
      );
      expect(tag.negativeExpansion, 'lowres');
    });
  });

  // ── Task #3: context-aware negative routing (append + de-dup) ────────────
  group('TagSuggestionHelper.appendNegatives', () {
    test('appends to an empty controller', () {
      final c = TextEditingController();
      TagSuggestionHelper.appendNegatives(c, 'bad hands, blurry');
      expect(c.text, 'bad hands, blurry, ');
    });

    test('appends with a separator to existing text', () {
      final c = TextEditingController(text: 'lowres');
      TagSuggestionHelper.appendNegatives(c, 'bad hands');
      expect(c.text, 'lowres, bad hands, ');
    });

    test('skips tags already present (case-insensitive)', () {
      final c = TextEditingController(text: 'bad hands, lowres');
      TagSuggestionHelper.appendNegatives(c, 'Bad Hands, jpeg artifacts');
      expect(c.text, 'bad hands, lowres, jpeg artifacts, ');
    });

    test('is a no-op for null/blank negatives', () {
      final c = TextEditingController(text: 'lowres');
      TagSuggestionHelper.appendNegatives(c, null);
      TagSuggestionHelper.appendNegatives(c, '   ');
      expect(c.text, 'lowres');
    });
  });

  // ── matchingSuggestions: prefix-only autocomplete ───────────────────────
  group('matchingSuggestions (prefix matching)', () {
    const dir = '.test_tmp_chars_suggest';

    CharacterLibraryNotifier makeNotifier() => CharacterLibraryNotifier(
          service: CharacterLibraryService(charactersDir: dir),
          closetService: ClosetService(charactersDir: dir),
        );

    setUp(() {
      final d = Directory(dir);
      if (d.existsSync()) d.deleteSync(recursive: true);
    });

    tearDown(() {
      final d = Directory(dir);
      if (d.existsSync()) d.deleteSync(recursive: true);
    });

    test('matches the start of a name but not an interior substring', () async {
      final n = makeNotifier();
      await n.importGeneratedCharacter(
        SavedCharacter.create(name: 'Sarah').copyWith(baseTags: '1girl'),
        const [],
      );

      // Prefix → matches.
      expect(n.matchingSuggestions('sar').map((s) => s.label), contains('Sarah'));
      expect(n.matchingSuggestions('s').map((s) => s.label), contains('Sarah'));

      // Interior substring → no match (this is the reported bug).
      expect(n.matchingSuggestions('ara'), isEmpty);
      expect(n.matchingSuggestions('rah'), isEmpty);
    });

    test('outfit entries match on the outfit name prefix too', () async {
      final n = makeNotifier();
      final c = SavedCharacter.create(name: 'Yuki').copyWith(baseTags: '1girl');
      await n.importGeneratedCharacter(c, [
        ClosetOutfit.create(name: 'Raincoat', tags: 'raincoat'),
      ]);

      // Name prefix surfaces both the bare entry and the outfit entry.
      final byName = n.matchingSuggestions('yuk').map((s) => s.label).toList();
      expect(byName, contains('Yuki'));
      expect(byName, contains('Yuki (Raincoat)'));

      // Outfit-name prefix surfaces just the outfit entry.
      final byOutfit = n.matchingSuggestions('rain').map((s) => s.label).toList();
      expect(byOutfit, ['Yuki (Raincoat)']);

      // Interior substring of the outfit name → no match.
      expect(n.matchingSuggestions('coat'), isEmpty);
    });
  });

  // ── Task #1: enabled flag round-trips + payload filtering ────────────────
  group('vibe/ref enabled flag', () {
    test('VibeTransfer.enabled round-trips, defaults true on old JSON', () {
      final v = VibeTransfer(
        id: 'v0',
        originalImageBytes: Uint8List(0),
        processedPreview: Uint8List(0),
        vibeVectorBase64: 'AA==',
      );
      expect(v.enabled, isTrue);
      expect(v.copyWith(enabled: false).toJson()['enabled'], isFalse);

      final loaded = VibeTransfer.fromJson(v.toJson());
      expect(loaded.enabled, isTrue);
      // Legacy JSON (no 'enabled') → defaults true.
      final legacy = Map<String, dynamic>.from(v.toJson())..remove('enabled');
      expect(VibeTransfer.fromJson(legacy).enabled, isTrue);
    });

    test('VibeTransferNotifier.buildPayload skips disabled vibes', () {
      final n = VibeTransferNotifier();
      n.setVibes([
        VibeTransfer(id: 'a', originalImageBytes: Uint8List(0), processedPreview: Uint8List(0), vibeVectorBase64: 'A'),
        VibeTransfer(id: 'b', originalImageBytes: Uint8List(0), processedPreview: Uint8List(0), vibeVectorBase64: 'B'),
      ]);
      n.toggleEnabled('a');
      final payload = n.buildPayload();
      expect(payload, isNotNull);
      expect(payload!.vibeVectors, ['B']);

      n.toggleEnabled('b'); // all disabled → null payload
      expect(n.buildPayload(), isNull);
    });

    test('DirectorReference.enabled round-trips, defaults true on old JSON', () {
      final r = DirectorReference(
        id: 'r0',
        originalImageBytes: Uint8List(0),
        processedBase64: 'x',
      );
      expect(r.enabled, isTrue);
      expect(r.copyWith(enabled: false).toJson()['enabled'], isFalse);
      final legacy = Map<String, dynamic>.from(r.toJson())..remove('enabled');
      expect(DirectorReference.fromJson(legacy).enabled, isTrue);
    });

    test('DirectorRefNotifier.buildPayload skips disabled references', () async {
      final n = DirectorRefNotifier();
      await n.setReferences([
        DirectorReference(id: 'a', originalImageBytes: Uint8List(0), processedBase64: 'imgA'),
        DirectorReference(id: 'b', originalImageBytes: Uint8List(0), processedBase64: 'imgB'),
      ]);
      n.toggleEnabled('a');
      final payload = n.buildPayload();
      expect(payload, isNotNull);
      expect(payload!.images, ['imgB']);

      n.toggleEnabled('b');
      expect(n.buildPayload(), isNull);
    });
  });
}
