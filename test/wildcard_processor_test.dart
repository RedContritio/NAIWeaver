import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/wildcard_processor.dart';
import 'package:naiweaver/core/services/wildcard_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('wildcard_processor_test_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> write(String name, String content) =>
      File(p.join(dir.path, '$name.txt')).writeAsString(content);

  WildcardProcessor processor([WildcardService? service, Random? random]) =>
      WildcardProcessor(
        wildcardDir: dir.path,
        wildcardService: service,
        random: random,
      );

  group('expansion', () {
    test('text without wildcard tokens is returned untouched', () async {
      expect(
        await processor().process('1girl, {blue eyes}, __ not a token'),
        '1girl, {blue eyes}, __ not a token',
      );
    });

    test('a single-entry wildcard is replaced in place', () async {
      await write('hair', 'silver hair\n');
      expect(
        await processor().process('1girl, __hair__, smile'),
        '1girl, silver hair, smile',
      );
    });

    test('blank lines are skipped and entries are trimmed', () async {
      await write('eyes', '\n   \n  red eyes  \n\n');
      expect(await processor().process('__eyes__'), 'red eyes');
    });

    test('nested wildcards expand until nothing is left to expand', () async {
      await write('outfit', '__top__, __bottom__');
      await write('top', 'white shirt');
      await write('bottom', '__skirt__');
      await write('skirt', 'pleated skirt');
      expect(
        await processor().process('1girl, __outfit__'),
        '1girl, white shirt, pleated skirt',
      );
    });

    test('names may contain dots, dashes and digits', () async {
      await write('a-b.c_1', 'ok');
      expect(await processor().process('__a-b.c_1__'), 'ok');
    });
  });

  group('recursion limit', () {
    test('five levels of nesting still resolve completely', () async {
      for (var i = 1; i < 5; i++) {
        await write('w$i', '__w${i + 1}__');
      }
      await write('w5', 'end');
      expect(await processor().process('__w1__'), 'end');
    });

    test('a sixth level is left as a literal token', () async {
      for (var i = 1; i < 6; i++) {
        await write('w$i', '__w${i + 1}__');
      }
      await write('w6', 'end');
      expect(await processor().process('__w1__'), '__w6__');
    });

    test('a self-referencing wildcard terminates after five passes', () async {
      await write('loop', 'x __loop__');
      expect(await processor().process('__loop__'), 'x x x x x __loop__');
    });

    test('two wildcards referencing each other terminate', () async {
      await write('ping', 'a __pong__');
      await write('pong', 'b __ping__');
      final result = await processor().process('__ping__');
      expect(result, 'a b a b a __pong__');
    });
  });

  group('unresolvable references', () {
    test('a missing wildcard stays as its literal token', () async {
      expect(await processor().process('1girl, __nope__'), '1girl, __nope__');
    });

    test(
      'a missing wildcard does not stop other tokens from expanding',
      () async {
        await write('hair', 'blonde hair');
        expect(
          await processor().process('__nope__, __hair__'),
          '__nope__, blonde hair',
        );
      },
    );

    test('an empty or blank-only file stays as its literal token', () async {
      await write('empty', '');
      await write('blank', '\n  \n');
      expect(
        await processor().process('__empty__ __blank__'),
        '__empty__ __blank__',
      );
    });
  });

  group('selection modes', () {
    test('sequential cycles through the entries in file order', () async {
      await write('seq', 'one\ntwo\nthree');
      final service = WildcardService(wildcardDir: dir.path);
      await service.setMode('seq', WildcardMode.sequential);
      final proc = processor(service);

      final out = <String>[];
      for (var i = 0; i < 7; i++) {
        out.add(await proc.process('__seq__'));
      }
      expect(out, ['one', 'two', 'three', 'one', 'two', 'three', 'one']);
    });

    test('sequential state is per wildcard and per processor', () async {
      await write('a', 'a1\na2');
      await write('b', 'b1\nb2');
      final service = WildcardService(wildcardDir: dir.path);
      await service.setMode('a', WildcardMode.sequential);
      await service.setMode('b', WildcardMode.sequential);

      final first = processor(service);
      expect(await first.process('__a__'), 'a1');
      expect(await first.process('__b__'), 'b1');
      expect(await first.process('__a__'), 'a2');

      // A fresh processor starts from the top again: same inputs, same output.
      final second = processor(service);
      expect(await second.process('__a__'), 'a1');
    });

    test('sequential hands out values left to right within one prompt', () async {
      await write('c', 'one\ntwo\nthree');
      final service = WildcardService(wildcardDir: dir.path);
      await service.setMode('c', WildcardMode.sequential);
      expect(
        await processor(service).process('__c__ __c__ __c__'),
        'one two three',
      );
    });

    test('an injected Random makes the expansion reproducible', () async {
      await write('pick', 'a\nb\nc\nd\ne\nf');
      Future<List<String>> draw(int seed) async {
        final proc = processor(null, Random(seed));
        return [for (var i = 0; i < 12; i++) await proc.process('__pick__')];
      }

      expect(await draw(7), await draw(7));
    });

    test('weighted mode with all-zero weights picks uniformly', () async {
      await write('w', '0::a\n0::b');
      final service = WildcardService(wildcardDir: dir.path);
      await service.setMode('w', WildcardMode.weighted);
      final proc = processor(service, Random(3));
      final seen = {
        for (var i = 0; i < 40; i++) await proc.process('__w__'),
      };
      expect(seen, {'a', 'b'});
    });

    test('shuffle uses every entry once before repeating', () async {
      await write('deck', 'a\nb\nc\nd');
      final service = WildcardService(wildcardDir: dir.path);
      await service.setMode('deck', WildcardMode.shuffle);
      final proc = processor(service);

      for (var round = 0; round < 3; round++) {
        final drawn = <String>[];
        for (var i = 0; i < 4; i++) {
          drawn.add(await proc.process('__deck__'));
        }
        expect(drawn.toSet(), {'a', 'b', 'c', 'd'}, reason: 'round $round');
      }
    });

    test('random mode only ever returns entries from the file', () async {
      await write('pick', 'x\ny\nz');
      final proc = processor();
      final seen = <String>{};
      for (var i = 0; i < 60; i++) {
        seen.add(await proc.process('__pick__'));
      }
      expect(seen.difference({'x', 'y', 'z'}), isEmpty);
      expect(seen.length, greaterThan(1));
    });

    test(
      'weighted mode honours N:: prefixes and never picks weight 0',
      () async {
        await write('w', '0::never\n5::always');
        final service = WildcardService(wildcardDir: dir.path);
        await service.setMode('w', WildcardMode.weighted);
        final proc = processor(service);
        for (var i = 0; i < 40; i++) {
          expect(await proc.process('__w__'), 'always');
        }
      },
    );

    test(
      'weighted lines without a weight count as 1 and keep their text',
      () async {
        await write('w', '0::skip\nplain text: with colon');
        final service = WildcardService(wildcardDir: dir.path);
        await service.setMode('w', WildcardMode.weighted);
        expect(
          await processor(service).process('__w__'),
          'plain text: with colon',
        );
      },
    );
  });
}
