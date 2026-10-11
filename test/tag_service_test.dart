import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late String tagFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tag_service_test_');
    tagFile = p.join(dir.path, 'tags.json');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<TagService> load(List<Map<String, dynamic>> tags) async {
    await File(tagFile).writeAsString(jsonEncode(tags));
    final service = TagService(filePath: tagFile);
    await service.loadTags();
    return service;
  }

  Map<String, dynamic> tag(
    String name,
    int count, {
    String type = 'general',
    List<String> aliases = const [],
    bool favorite = false,
  }) => {
    'tag': name,
    'count': count,
    'type_name': type,
    'aliases': aliases,
    'is_favorite': favorite,
  };

  group('loading', () {
    test('a missing file leaves the service unloaded and empty', () async {
      final service = TagService(filePath: tagFile);
      await service.loadTags();
      expect(service.isLoaded, isFalse);
      expect(service.getSuggestions('blue'), isEmpty);
    });

    test(
      'a corrupt file leaves the service unloaded instead of throwing',
      () async {
        await File(tagFile).writeAsString('{not json');
        final service = TagService(filePath: tagFile);
        await service.loadTags();
        expect(service.isLoaded, isFalse);
      },
    );

    test(
      'tags are sorted by popularity and survive a save/load round trip',
      () async {
        final service = await load([tag('rare', 5), tag('common', 500)]);
        expect(service.tags.map((t) => t.tag), ['common', 'rare']);

        await service.toggleFavorite(service.tags.first);
        final reloaded = TagService(filePath: tagFile);
        await reloaded.loadTags();
        expect(reloaded.tags.first.tag, 'common');
        expect(reloaded.tags.first.isFavorite, isTrue);
      },
    );
  });

  group('getSuggestions', () {
    test('ASCII queries need three characters, CJK queries only one', () async {
      final service = await load([
        tag('blue_eyes', 100),
        tag('genshin_impact', 50, type: 'copyright', aliases: ['原神']),
      ]);
      expect(service.getSuggestions('bl'), isEmpty);
      expect(service.getSuggestions('blu').map((t) => t.tag), ['blue_eyes']);
      expect(service.getSuggestions('原').map((t) => t.tag), ['genshin_impact']);
    });

    test(
      'prefix matches rank before contains matches before alias matches',
      () async {
        final service = await load([
          tag('sky', 900, aliases: ['bluish']),
          tag('light_blue_background', 800),
          tag('blue_sky', 10),
        ]);
        final result = service.getSuggestions('blue');
        expect(result.map((t) => t.tag), ['blue_sky', 'light_blue_background']);

        final viaAlias = service.getSuggestions('bluis');
        expect(viaAlias.map((t) => t.tag), ['sky']);
        expect(viaAlias.single.matchedAlias, 'bluish');
      },
    );

    test('within a tier favorites come first, then higher counts', () async {
      final service = await load([
        tag('blue_a', 300),
        tag('blue_b', 100, favorite: true),
        tag('blue_c', 200),
      ]);
      expect(service.getSuggestions('blue').map((t) => t.tag), [
        'blue_b',
        'blue_a',
        'blue_c',
      ]);
    });

    test('a tag matched by name is not repeated through its alias', () async {
      final service = await load([
        tag('blue_eyes', 100, aliases: ['blue eyes alias', 'blue']),
      ]);
      expect(service.getSuggestions('blue').length, 1);
    });

    test('matching is case-insensitive and the limit is honoured', () async {
      final service = await load([
        for (var i = 0; i < 30; i++) tag('Blue_$i', 100 + i),
      ]);
      expect(service.getSuggestions('BLUE').length, 20);
      expect(service.getSuggestions('blue', limit: 5).length, 5);
    });
  });

  group('resolveAliases', () {
    late TagService service;

    setUp(() async {
      service = await load([
        tag('genshin_impact', 100, aliases: ['原神']),
        tag('long_hair', 900, aliases: ['长发', '长头发']),
        tag('red_hair', 800),
        // An alias that is also a real tag name must never shadow the tag.
        tag('sky', 700, aliases: ['red_hair']),
      ]);
    });

    test('replaces an alias with the English tag', () {
      expect(service.resolveAliases('原神'), 'genshin_impact');
      expect(service.resolveAliases('长头发'), 'long_hair');
    });

    test('keeps delimiters and surrounding whitespace byte-for-byte', () {
      expect(
        service.resolveAliases('1girl,  长发 | 原神 ,smile'),
        '1girl,  long_hair | genshin_impact ,smile',
      );
    });

    test('keeps brace and bracket weights around a resolved alias', () {
      expect(service.resolveAliases('{{长发}}'), '{{long_hair}}');
      expect(service.resolveAliases('[原神]'), '[genshin_impact]');
    });

    test('known English tags and unknown text pass through unchanged', () {
      const prompt = '1girl, Long_Hair, something unknown, {red_hair}';
      expect(service.resolveAliases(prompt), prompt);
    });

    test('an English tag name wins over another tag\'s identical alias', () {
      expect(service.resolveAliases('red_hair'), 'red_hair');
    });

    test('alias lookup is case-insensitive', () async {
      final svc = await load([
        tag('hatsune_miku', 50, aliases: ['Miku']),
      ]);
      expect(svc.resolveAliases('miku, MIKU'), 'hatsune_miku, hatsune_miku');
    });

    test('empty prompts and delimiter-only prompts are stable', () {
      expect(service.resolveAliases(''), '');
      expect(service.resolveAliases(',,|'), ',,|');
    });

    test('an unloaded service returns the prompt untouched', () {
      final unloaded = TagService(filePath: tagFile);
      expect(unloaded.resolveAliases('原神'), '原神');
    });
  });

  group('hasTag', () {
    test('ignores case and surrounding whitespace', () async {
      final service = await load([tag('blue_eyes', 1)]);
      expect(service.hasTag('  Blue_Eyes '), isTrue);
      expect(service.hasTag('red_eyes'), isFalse);
    });
  });
}
