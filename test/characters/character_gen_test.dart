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

// A lean-shape response: only name, gender, and tag buckets — NO personality,
// NO soul_md, NO outfit_tags (clothing is the wardrobe step's job).
const _leanCharacterJson = '''
{
  "name": "Mara Velho",
  "gender": "female",
  "tags": {
    "base": "1girl, tan, freckles",
    "face": "hazel eyes, tareme, eyelashes",
    "hair": "dark brown hair, medium hair, messy hair, straight hair",
    "body": "petite, toned, small breasts, tall",
    "nsfw_top": "",
    "nsfw_bottom": "",
    "nsfw_always": "",
    "nsfw": ""
  }
}
''';

void main() {
  // Common test setup — the service loads the lean prompt template from the
  // asset bundle; inject a stub so tests don't need rootBundle plumbing.
  setUp(() {
    CharacterGenService.setLeanTemplateForTesting(
      'STUB TEMPLATE — gender:{gender} period:{period} location:{location}',
    );
  });

  tearDown(() {
    CharacterGenService.setLeanTemplateForTesting(null);
  });

  // --------------------------------------------------------------------
  // JSON parsing / repair
  // --------------------------------------------------------------------
  group('parseCharacterJson', () {
    test('parses a clean lean-shape object', () {
      final m = CharacterGenService.parseCharacterJsonForTesting(_leanCharacterJson);
      expect(m, isNotNull);
      expect(m!['name'], 'Mara Velho');
      expect(m['gender'], 'female');
      expect(m['tags'], isA<Map>());
      expect((m['tags'] as Map)['base'], contains('1girl'));
    });

    test('strips ```json fences', () {
      final wrapped = '```json\n$_leanCharacterJson\n```';
      final m = CharacterGenService.parseCharacterJsonForTesting(wrapped);
      expect(m, isNotNull);
      expect(m!['name'], 'Mara Velho');
    });

    test('strips a trailing <<END>> sentinel', () {
      final wrapped = '$_leanCharacterJson\n<<END>>';
      final m = CharacterGenService.parseCharacterJsonForTesting(wrapped);
      expect(m, isNotNull);
      expect(m!['name'], 'Mara Velho');
    });

    test('strips a leading <think> block', () {
      final wrapped = '<think>let me design this person...</think>\n$_leanCharacterJson';
      final m = CharacterGenService.parseCharacterJsonForTesting(wrapped);
      expect(m, isNotNull);
      expect(m!['name'], 'Mara Velho');
    });

    test('repairs JSON cut off mid-string (recovers name)', () {
      const truncated = '{"name": "Kai", "gender": "male", "tags": {"base": "1boy, ';
      final m = CharacterGenService.parseCharacterJsonForTesting(truncated);
      expect(m, isNotNull);
      expect(m!['name'], 'Kai');
    });

    test('returns null when there is no name', () {
      expect(CharacterGenService.parseCharacterJsonForTesting('not json at all'), isNull);
      expect(CharacterGenService.parseCharacterJsonForTesting('{"foo": 1, "bar": 2}'), isNull);
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
    });

    test('lean prompt substitution fills the placeholders', () {
      const era = CharacterEra(id: 'roaring-twenties', year: 1925, label: 'The Roaring Twenties');
      final prompt = substituteLeanCharacterPrompt(
        template:
            'GENDER:{gender} PERIOD:{period} LOCATION:{location} NSFW:{nsfw_mode}\n{vibe_context}{era_context}{nsfw_block}',
        gender: 'female',
        era: era,
        locationName: 'Berlin',
        vibeHint: 'Mysterious',
        nsfw: false,
      );
      expect(prompt, contains('GENDER:female'));
      expect(prompt, contains('PERIOD:The Roaring Twenties'));
      expect(prompt, contains('LOCATION:Berlin'));
      expect(prompt, contains('NSFW:OFF'));
      expect(prompt, contains('Overall vibe: Mysterious'));
      expect(prompt, contains('KNOWLEDGE BOUNDARY'));
      expect(prompt, contains('Leave nsfw_top, nsfw_bottom, nsfw_always, and nsfw ALL as empty strings'));
    });
  });

  // --------------------------------------------------------------------
  // full pipeline via the service (with a scripted fake)
  // --------------------------------------------------------------------
  group('CharacterGenService.generate', () {
    const modernEra = CharacterEra(id: 'present-day', year: 2026, label: 'Present Day');

    test('one good response + no wardrobe → a populated appearance-only SavedCharacter', () async {
      final svc = ScriptedTextGenService([_leanCharacterJson]);
      final gen = CharacterGenService(svc, maxTokens: 4096);
      final result = await gen.generate(CharacterGenForm(
        vibe: kCharacterVibes.first,
        era: modernEra,
        location: 'a coastal town',
        wardrobeCount: 0,
      ));
      final c = result.character;
      expect(c.name, 'Mara Velho');
      expect(c.gender, 'female');
      expect(c.baseTags, contains('1girl'));
      expect(c.faceTags, contains('hazel eyes'));
      expect(c.hairTags, contains('dark brown hair'));
      expect(c.bodyTags_, contains('petite'));

      // The lean path emits NO personality / NO clothing.
      expect(c.soulMd, isEmpty);
      expect(c.personalitySummary, isEmpty);
      expect(c.characterDescription, isEmpty);
      expect(c.notes, isEmpty);
      expect(c.themeAccent, isNull);
      // No meet outfit — the closet is empty unless the wardrobe step ran.
      expect(result.closet, isEmpty);
      expect(c.primaryOutfitId, isNull);

      // Round-trips through JSON.
      final round = SavedCharacter.fromJson(jsonDecode(jsonEncode(c.toJson())));
      expect(round.name, c.name);
      expect(round.baseTags, c.baseTags);
      expect(round.soulMd, isEmpty);
    });

    test('NSFW off → nsfw_* buckets are dropped even if the model returns them', () async {
      const withNsfw = '''
{
  "name": "Test",
  "gender": "female",
  "tags": {
    "base": "1girl",
    "face": "blue eyes",
    "hair": "blonde hair",
    "body": "petite",
    "nsfw_top": "should-be-dropped",
    "nsfw_bottom": "should-be-dropped",
    "nsfw_always": "should-be-dropped",
    "nsfw": ""
  }
}
''';
      final svc = ScriptedTextGenService([withNsfw]);
      final gen = CharacterGenService(svc, maxTokens: 4096);
      final result = await gen.generate(CharacterGenForm(
        vibe: kCharacterVibes.first,
        era: modernEra,
        wardrobeCount: 0,
        nsfw: false,
      ));
      expect(result.character.nsfwTop, isEmpty);
      expect(result.character.nsfwBottom, isEmpty);
      expect(result.character.nsfwAlways, isEmpty);
    });

    test('NSFW on → nsfw_* buckets are persisted from the model output', () async {
      const withNsfw = '''
{
  "name": "Test",
  "gender": "female",
  "tags": {
    "base": "1girl",
    "face": "blue eyes",
    "hair": "blonde hair",
    "body": "petite",
    "nsfw_top": "nipples",
    "nsfw_bottom": "pubic hair",
    "nsfw_always": "",
    "nsfw": ""
  }
}
''';
      final svc = ScriptedTextGenService([withNsfw]);
      final gen = CharacterGenService(svc, maxTokens: 4096);
      final result = await gen.generate(CharacterGenForm(
        vibe: kCharacterVibes.first,
        era: modernEra,
        wardrobeCount: 0,
        nsfw: true,
      ));
      expect(result.character.nsfwTop, 'nipples');
      expect(result.character.nsfwBottom, 'pubic hair');
      expect(result.character.nsfwAlways, isEmpty);
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
      final svc = ScriptedTextGenService([_leanCharacterJson], delay: const Duration(milliseconds: 30));
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

    test('generate() saves the character and exposes the id', () async {
      final textGen = TextGenNotifier()..updateService(ScriptedTextGenService([_leanCharacterJson]));
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

      final c = library.characterById(id!);
      expect(c, isNotNull);
      expect(c!.name, 'Mara Velho');
      expect(c.soulMd, isEmpty);

      final file = File('${tmp.path}/$id.json');
      expect(await file.exists(), isTrue);
      final onDisk = SavedCharacter.fromJson(jsonDecode(await file.readAsString()));
      expect(onDisk.name, 'Mara Velho');
      expect(onDisk.baseTags, contains('1girl'));
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
        ..updateService(ScriptedTextGenService([_leanCharacterJson], delay: const Duration(milliseconds: 40)));
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
