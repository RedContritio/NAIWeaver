import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/text_gen_service.dart';
import 'package:naiweaver/features/characters/gen/character_gen_data.dart';
import 'package:naiweaver/features/characters/gen/character_gen_prompts.dart';
import 'package:naiweaver/features/characters/gen/character_gen_service.dart';
import 'package:naiweaver/features/characters/gen/providers/character_gen_notifier.dart';
import 'package:naiweaver/features/characters/models/saved_character.dart';
import 'package:naiweaver/features/characters/providers/character_library_notifier.dart';
import 'package:naiweaver/features/characters/services/character_library_service.dart';
import 'package:naiweaver/features/characters/services/closet_service.dart';
import 'package:naiweaver/features/text_gen/providers/text_gen_notifier.dart';

/// A scripted [TextGenService]: `generate()` returns the next entry from
/// [responses] each call (repeating the last once exhausted). Lets a test drive
/// the multi-call character pipeline deterministically.
class ScriptedTextGenService implements TextGenService {
  final List<String> responses;
  int calls = 0;
  Duration delay;

  ScriptedTextGenService(this.responses, {this.delay = Duration.zero});

  String _next() {
    if (responses.isEmpty) return '';
    final r = calls < responses.length ? responses[calls] : responses.last;
    calls++;
    return r;
  }

  @override
  String get providerId => 'scripted';

  @override
  Future<String> generate(TextGenRequest req) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    return _next();
  }

  @override
  Stream<String> generateStream(TextGenRequest req) async* {
    yield await generate(req);
  }

  @override
  Future<TextGenResult> generateStructured(TextGenRequest req) async =>
      TextGenResult(text: await generate(req));
}

// A reasonably complete "good" main-generation response.
const _goodCharacterJson = '''
{
  "name": "Mara Vel/Mara",
  "gender": "female",
  "aliases": "Goes by Mara; signs notes 'M.V.'",
  "soul_md": "You are Mara Velho, twenty-eight, a tide-pool naturalist in a small coastal town. You wake before dawn most days. Your hands are always a little salt-cracked. You speak in short bursts when something delights you and trail off when it doesn't. There was a year you spent away, in the city, and you came back changed. You are wary with strangers and disarmingly direct with people you trust. You never lie about the sea. When you are nervous you over-narrate. You are not a manic pixie and you are not a wise mentor. You are a person who counts barnacles.",
  "reaction_patterns": {
    "nervous": "She narrates whatever's in front of her, naming species under her breath.",
    "angry": "Goes very quiet, voice drops a register, words get clipped.",
    "attracted": "Brings you things — a shell, a smooth stone — without explaining why.",
    "sad": "Disappears to the tide pools alone before sunrise.",
    "scared": "Plants her feet, stops blinking, asks fast practical questions.",
    "embarrassed": "Laughs once, sharp, then changes the subject to the weather.",
    "happy": "Talks twice as fast, hands moving, half in Portuguese."
  },
  "character_description": "A Portuguese woman in her late twenties with a wiry, sun-weathered build and freckled olive skin. Shoulder-length dark brown hair, usually salt-stiff and pushed back. Hazel eyes, a slightly crooked nose, and a small scar on her left thumb.",
  "tags": {
    "base": "1girl, portuguese, 20yo, freckles",
    "face": "hazel eyes, crooked nose, thin lips, sharp jawline",
    "hair": "dark brown hair, shoulder length, messy hair, straight hair",
    "body": "slim, toned, small breasts, tall",
    "nsfw_top": "",
    "nsfw_bottom": "",
    "nsfw_always": "",
    "nsfw": ""
  },
  "outfit_tags": "olive cotton shirt, rolled sleeves, navy work shorts, brown leather sandals, woven straw hat",
  "preview_scene": "gentle smile, crouching, holding seashell, tide pool, rocky shore, upper body",
  "personality_summary": "A salt-cracked tide-pool naturalist who can name two hundred shore species but forgets her own birthday.",
  "theme": { "accent": "#2da89e", "accent_secondary": "#e8b04a", "bg": "#0a1414" },
  "meet_cute": "You crouch beside a tide pool at dawn and a woman two rocks over says, without looking up, 'Don't — that one stings.' The air smells of kelp and cold stone."
}
''';

void main() {
  // --------------------------------------------------------------------
  // soul_md truncation detection (ported from bri.'s _soul_md_truncated)
  // --------------------------------------------------------------------
  group('soulMdTruncated', () {
    test('empty / whitespace-only is truncated', () {
      expect(CharacterGenService.soulMdTruncated(''), isTrue);
      expect(CharacterGenService.soulMdTruncated('   \n  '), isTrue);
    });
    test('ending mid-sentence is truncated', () {
      expect(CharacterGenService.soulMdTruncated('You are a person who counts'), isTrue);
      expect(CharacterGenService.soulMdTruncated('You are a person who counts,'), isTrue);
      expect(CharacterGenService.soulMdTruncated('You are a person who counts barnacles and'), isTrue);
    });
    test('ending on sentence-final punctuation is complete', () {
      expect(CharacterGenService.soulMdTruncated('You count barnacles.'), isFalse);
      expect(CharacterGenService.soulMdTruncated('Do you?'), isFalse);
      expect(CharacterGenService.soulMdTruncated('Stop!'), isFalse);
      expect(CharacterGenService.soulMdTruncated('"she said."'), isFalse);
      expect(CharacterGenService.soulMdTruncated('and that was that. \n\n'), isFalse);
    });
  });

  // --------------------------------------------------------------------
  // JSON parsing / repair
  // --------------------------------------------------------------------
  group('parseCharacterJson', () {
    test('parses a clean object', () {
      final m = CharacterGenService.parseCharacterJsonForTesting(_goodCharacterJson);
      expect(m, isNotNull);
      expect((m!['name'] as String).contains('Mara'), isTrue);
      expect(m['gender'], 'female');
      expect(m['soul_md'], isA<String>());
    });

    test('strips ```json fences', () {
      final wrapped = '```json\n$_goodCharacterJson\n```';
      final m = CharacterGenService.parseCharacterJsonForTesting(wrapped);
      expect(m, isNotNull);
      expect(m!['soul_md'], isA<String>());
    });

    test('strips a leading <think> block', () {
      final wrapped = '<think>let me design this person...</think>\n$_goodCharacterJson';
      final m = CharacterGenService.parseCharacterJsonForTesting(wrapped);
      expect(m, isNotNull);
      expect((m!['name'] as String).contains('Mara'), isTrue);
    });

    test('repairs JSON cut off mid-string', () {
      // Truncate inside the soul_md value.
      const truncated = '{"name": "Kai", "soul_md": "You are Kai, a fisherman. You wake before dawn and you ';
      final m = CharacterGenService.parseCharacterJsonForTesting(truncated);
      expect(m, isNotNull);
      expect(m!['name'], 'Kai');
      expect((m['soul_md'] as String).startsWith('You are Kai'), isTrue);
    });

    test('repairs JSON cut off after a key, mid-object (recovers earlier keys)', () {
      const truncated = '{"name": "Lena", "soul_md": "You are Lena. Done.", "tags": {"base": "1girl, 20yo", "face": "blue eyes';
      final m = CharacterGenService.parseCharacterJsonForTesting(truncated);
      expect(m, isNotNull);
      expect(m!['name'], 'Lena');
      expect(m['soul_md'], 'You are Lena. Done.');
    });

    test('returns null when there is no name+soul_md', () {
      expect(CharacterGenService.parseCharacterJsonForTesting('not json at all'), isNull);
      expect(CharacterGenService.parseCharacterJsonForTesting('{"foo": 1, "bar": 2}'), isNull);
    });

    test('loose parse accepts any object (for the completion pass)', () {
      final m = CharacterGenService.parseLooseJsonForTesting('{"personality_summary": "A baker."}');
      expect(m, isNotNull);
      expect(m!['personality_summary'], 'A baker.');
    });

    test('loose parse repairs a truncated completion object', () {
      const truncated = '{"soul_md_completion": " and that is the whole of it.", "personality_summary": "A wandering';
      final m = CharacterGenService.parseLooseJsonForTesting(truncated);
      expect(m, isNotNull);
      expect(m!['soul_md_completion'], ' and that is the whole of it.');
    });
  });

  // --------------------------------------------------------------------
  // continuation stitching
  // --------------------------------------------------------------------
  group('joinContinuation', () {
    test('inserts a space when joining would glue two words', () {
      expect(CharacterGenService.joinContinuationForTesting('the keeper', 'said nothing.'),
          'the keeper said nothing.');
    });
    test('does not double-space across existing whitespace', () {
      expect(CharacterGenService.joinContinuationForTesting('the keeper ', 'said.'),
          'the keeper said.');
      expect(CharacterGenService.joinContinuationForTesting('end of line.', '\nNew para.'),
          'end of line.\nNew para.');
    });
    test('handles empties', () {
      expect(CharacterGenService.joinContinuationForTesting('', 'abc'), 'abc');
      expect(CharacterGenService.joinContinuationForTesting('abc', ''), 'abc');
    });
  });

  // --------------------------------------------------------------------
  // prompt-block injection (vibe / era / knowledge boundary)
  // --------------------------------------------------------------------
  group('prompt blocks', () {
    test('vibe guidance: surprise-me is empty, traditional has its blob', () {
      expect(vibeById('surprise_me')!.resolvedGuidance(), '');
      final trad = vibeById('traditional')!.resolvedGuidance();
      expect(trad, contains('VIBE -- TRADITIONAL'));
      expect(trad, contains('don\'t default to Western assumptions'));
    });

    test('custom vibe substitutes the free text', () {
      final c = vibeById('custom')!.resolvedGuidance(customVibe: 'weary war veteran turned baker');
      expect(c, 'VIBE -- CUSTOM: weary war veteran turned baker');
      expect(vibeById('custom')!.resolvedGuidance(customVibe: '  '), '');
    });

    test('addicted vibe substitutes (or generalises) the subject', () {
      final withSubj = vibeById('addicted')!.resolvedGuidance(addictionSubject: 'gambling');
      expect(withSubj, contains('The addiction is: GAMBLING'));
      expect(withSubj, isNot(contains('{addictionPick}')));
      final blank = vibeById('addicted')!.resolvedGuidance();
      expect(blank, contains('Pick a SPECIFIC addiction'));
      expect(blank, isNot(contains('{addictionPick}')));
    });

    test('era block: modern has no constraints, historical has the knowledge boundary', () {
      const modern = CharacterEra(id: 'present-day', year: 2026, label: 'Present Day');
      expect(eraBlockFor(modern, 'Lisbon'), contains('Modern day'));
      expect(soulAddendumFor(modern, 'Lisbon'), '');

      const medieval = CharacterEra(id: 'black-death-arrives', year: 1347, label: 'The Black Death Arrives');
      final hist = eraBlockFor(medieval, 'Florence');
      expect(hist, contains('KNOWLEDGE BOUNDARY'));
      expect(hist, contains('The Black Death Arrives'));
      expect(hist, contains('Florence'));
      final addendum = soulAddendumFor(medieval, 'Florence');
      expect(addendum, contains('KNOWLEDGE BOUNDARY'));
      expect(addendum, contains('5-8 specific'));
    });

    test('generation prompt embeds the vibe + era blocks and the field schema', () {
      const era = CharacterEra(id: 'roaring-twenties', year: 1925, label: 'The Roaring Twenties', moment: 'Jazz spills out of every doorway.');
      final prompt = CharacterGenPrompts.buildGeneration(CharacterGenPromptInputs(
        gender: 'female',
        vibe: 'Mysterious',
        vibeGuidance: '',
        era: era,
        locationName: 'Berlin',
        nsfw: false,
      ));
      expect(prompt, contains('GENDER: female'));
      expect(prompt, contains('PERIOD: The Roaring Twenties'));
      expect(prompt, contains('Berlin'));
      expect(prompt, contains('Jazz spills out of every doorway.'));
      expect(prompt, contains('"soul_md"'));
      expect(prompt, contains('"reaction_patterns"'));
      expect(prompt, contains('"outfit_tags"'));
      expect(prompt, contains('Respond with ONLY valid JSON'));
      // NSFW off => the schema tells the model to leave the nsfw_* buckets empty.
      expect(prompt, contains('leave all four empty'));
    });

    test('completion prompt asks only for the listed fields', () {
      final p = CharacterGenPrompts.buildCompletion(
        name: 'Mara',
        locationName: 'Lisbon',
        periodDisplay: 'modern day',
        vibe: 'Friendly',
        soulExcerpt: '…counts barnacles.',
        soulNeedsCompletion: false,
        fieldNames: const ['outfit_tags', 'preview_scene'],
        nsfw: false,
      );
      expect(p, contains('["outfit_tags", "preview_scene"]'));
      expect(p, contains('do not regenerate it'));
      final p2 = CharacterGenPrompts.buildCompletion(
        name: 'Mara',
        locationName: 'Lisbon',
        periodDisplay: 'modern day',
        vibe: 'Friendly',
        soulExcerpt: '…and then',
        soulNeedsCompletion: true,
        fieldNames: const ['soul_md_completion', 'outfit_tags'],
        nsfw: false,
      );
      expect(p2, contains('CUT OFF mid-sentence'));
      expect(p2, contains('soul_md_completion'));
    });
  });

  // --------------------------------------------------------------------
  // full pipeline via the service (with a scripted fake)
  // --------------------------------------------------------------------
  group('CharacterGenService.generate', () {
    final modernEra = const CharacterEra(id: 'present-day', year: 2026, label: 'Present Day');

    test('one good response + no wardrobe → a fully populated SavedCharacter', () async {
      final svc = ScriptedTextGenService([_goodCharacterJson]);
      final gen = CharacterGenService(svc, maxTokens: 4096);
      final result = await gen.generate(CharacterGenForm(
        vibe: kCharacterVibes.first,
        era: modernEra,
        location: 'a coastal town',
        wardrobeCount: 0,
      ));
      final c = result.character;
      expect(c.name.contains('Mara'), isTrue);
      expect(c.gender, 'female');
      expect(c.baseTags, contains('1girl'));
      expect(c.faceTags, contains('hazel eyes'));
      expect(c.hairTags, contains('dark brown hair'));
      expect(c.bodyTags_, contains('slim'));
      expect(c.soulMd, contains('You are Mara'));
      expect(CharacterGenService.soulMdTruncated(c.soulMd), isFalse);
      expect(c.personalitySummary, contains('naturalist'));
      expect(c.characterDescription, contains('Portuguese woman'));
      expect(c.themeAccent, '#2DA89E');
      expect(c.notes, contains('Reaction patterns:'));
      // The meet outfit became the primary closet entry.
      expect(result.closet, isNotEmpty);
      expect(result.closet.first.tags, contains('olive cotton shirt'));
      expect(c.primaryOutfitId, result.closet.first.id);

      // Round-trips through JSON.
      final round = SavedCharacter.fromJson(jsonDecode(jsonEncode(c.toJson())));
      expect(round.name, c.name);
      expect(round.soulMd, c.soulMd);
      expect(round.personalitySummary, c.personalitySummary);
      expect(round.themeAccent, c.themeAccent);
    });

    test('truncated soul_md → chunked continuation loop fires and stitches a complete doc', () async {
      // 1st response: a character with a soul_md cut off mid-sentence.
      const partial = '{"name": "Rua", "soul_md": "You are Rua, a clockmaker. You speak slowly. You";'
          ' "tags": {"base": "1girl, 25yo", "face": "grey eyes", "hair": "black hair", "body": "average build"},'
          ' "outfit_tags": "grey wool waistcoat, white shirt, black trousers, leather shoes",'
          ' "preview_scene": "neutral expression, workbench, upper body",'
          ' "personality_summary": "A clockmaker who hears time differently.",'
          ' "character_description": "A woman in her mid-twenties with a slight frame.",'
          ' "reaction_patterns": {"nervous": "winds a pocket watch", "angry": "quiet", "attracted": "gives gears", "sad": "works late", "scared": "freezes", "embarrassed": "coughs", "happy": "hums"},'
          ' "theme": {"accent": "#888888", "accent_secondary": "#cccccc", "bg": "#101010"}}';
      // 2nd & 3rd responses: continuation chunks; the 3rd ends the sentence.
      final svc = ScriptedTextGenService([
        partial,
        ' choose your words like you choose a balance spring — carefully, and only after',
        ' a long pause. That is who you are.',
      ]);
      // maxTokens small so the loop is the realistic path; but big enough that
      // 3 calls suffice.
      final gen = CharacterGenService(svc, maxTokens: 150);
      final result = await gen.generate(CharacterGenForm(
        vibe: kCharacterVibes.first,
        era: modernEra,
        wardrobeCount: 0,
      ));
      // First response wasn't even valid JSON as written above (note the stray
      // ';') — the repair path recovers name + the partial soul_md, then the
      // continuation loop finishes the sentence.
      expect(result.character.soulMd, startsWith('You are Rua, a clockmaker.'));
      expect(result.character.soulMd, endsWith('That is who you are.'));
      expect(CharacterGenService.soulMdTruncated(result.character.soulMd), isFalse);
      // At least the initial call + ≥1 continuation.
      expect(svc.calls, greaterThanOrEqualTo(2));
    });

    test('no usable JSON at all → throws TextGenException', () async {
      final svc = ScriptedTextGenService(['I would love to help but here is some prose instead.']);
      final gen = CharacterGenService(svc, maxTokens: 4096);
      expect(
        () => gen.generate(CharacterGenForm(vibe: kCharacterVibes.first, era: modernEra, wardrobeCount: 0)),
        throwsA(isA<TextGenException>()),
      );
    });

    test('cancellation between steps aborts cleanly', () async {
      final svc = ScriptedTextGenService([_goodCharacterJson], delay: const Duration(milliseconds: 30));
      final gen = CharacterGenService(svc, maxTokens: 4096);
      final token = CharacterGenCancelToken();
      final fut = gen.generate(
        CharacterGenForm(vibe: kCharacterVibes.first, era: modernEra, wardrobeCount: 3),
        cancelToken: token,
      );
      // Cancel almost immediately (during the first LLM call's delay).
      token.cancel();
      await expectLater(fut, throwsA(isA<CharacterGenCancelled>()));
    });
  });

  // --------------------------------------------------------------------
  // notifier wiring: a successful run persists the character
  // --------------------------------------------------------------------
  group('CharacterGenNotifier', () {
    late Directory tmp;
    late CharacterLibraryNotifier library;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('naiweaver_chargen_test');
      library = CharacterLibraryNotifier(
        service: CharacterLibraryService(charactersDir: tmp.path),
        closetService: ClosetService(charactersDir: tmp.path),
      );
      await library.loadAll();
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('generate() saves the character + closet and exposes the id', () async {
      final textGen = TextGenNotifier()..updateService(ScriptedTextGenService([_goodCharacterJson]));
      final notifier = CharacterGenNotifier(library: library, textGen: textGen);
      expect(notifier.hasService, isTrue);

      final id = await notifier.generate(CharacterGenForm(
        vibe: kCharacterVibes.first,
        era: const CharacterEra(id: 'present-day', year: 2026, label: 'Present Day'),
        wardrobeCount: 0,
      ));
      expect(id, isNotNull);
      expect(notifier.lastError, isNull);
      expect(notifier.lastGeneratedId, id);

      // The character is in the in-memory library...
      final c = library.characterById(id!);
      expect(c, isNotNull);
      expect(c!.name.contains('Mara'), isTrue);
      expect(library.closetFor(id), isNotEmpty);

      // ...and was written to disk.
      final file = File('${tmp.path}/$id.json');
      expect(await file.exists(), isTrue);
      final onDisk = SavedCharacter.fromJson(jsonDecode(await file.readAsString()));
      expect(onDisk.soulMd, contains('You are Mara'));
    });

    test('generate() with no service set surfaces an error and writes nothing', () async {
      final notifier = CharacterGenNotifier(library: library, textGen: TextGenNotifier());
      final id = await notifier.generate(CharacterGenForm(
        vibe: kCharacterVibes.first,
        era: const CharacterEra(id: 'present-day', year: 2026, label: 'Present Day'),
      ));
      expect(id, isNull);
      expect(notifier.lastError, isNotNull);
      expect(library.characters, isEmpty);
      expect(tmp.listSync(), isEmpty);
    });

    test('cancel() during a run leaves no character behind', () async {
      final textGen = TextGenNotifier()
        ..updateService(ScriptedTextGenService([_goodCharacterJson], delay: const Duration(milliseconds: 40)));
      final notifier = CharacterGenNotifier(library: library, textGen: textGen);
      final fut = notifier.generate(CharacterGenForm(
        vibe: kCharacterVibes.first,
        era: const CharacterEra(id: 'present-day', year: 2026, label: 'Present Day'),
        wardrobeCount: 2,
      ));
      notifier.cancel();
      final id = await fut;
      expect(id, isNull);
      expect(notifier.lastError, isNull); // cancellation isn't an error
      expect(library.characters, isEmpty);
    });
  });
}
