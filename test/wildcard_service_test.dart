import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/wildcard_processor.dart';
import 'package:naiweaver/core/services/wildcard_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('wildcard_service_test_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> write(String name, [String content = 'x']) =>
      File(p.join(dir.path, '$name.txt')).writeAsString(content);

  Future<WildcardService> fresh() async {
    final service = WildcardService(wildcardDir: dir.path);
    await service.refresh();
    return service;
  }

  test('a missing directory yields no wildcards', () async {
    await dir.delete(recursive: true);
    final service = WildcardService(wildcardDir: dir.path);
    await service.refresh();
    expect(service.wildcardNames, isEmpty);
  });

  test(
    'only .txt files are listed; favorites sort first, then alphabetical',
    () async {
      await write('zebra');
      await write('apple');
      await write('mango');
      await File(p.join(dir.path, 'notes.md')).writeAsString('ignored');

      final service = await fresh();
      expect(service.wildcardNames, ['apple', 'mango', 'zebra']);

      await service.toggleFavorite('zebra');
      expect(service.wildcardNames, ['zebra', 'apple', 'mango']);
      expect(service.isFavorite('zebra'), isTrue);
    },
  );

  test(
    'favorites, modes and order persist across a new service instance',
    () async {
      await write('a');
      await write('b');
      await write('c');
      final service = await fresh();
      await service.toggleFavorite('c');
      await service.setMode('b', WildcardMode.weighted);
      await service.reorderWildcard(0, 3); // favorite "c" leads; move it last

      final reloaded = await fresh();
      expect(reloaded.isFavorite('c'), isTrue);
      expect(reloaded.getMode('b'), WildcardMode.weighted);
      expect(reloaded.getMode('a'), WildcardMode.random);
      expect(reloaded.wildcardNames, service.wildcardNames);
    },
  );

  test(
    'a custom order wins over favorites and new files are appended',
    () async {
      await write('a');
      await write('b');
      final service = await fresh();
      await service.reorderWildcard(0, 2); // [b, a]
      await service.toggleFavorite('a');
      expect(service.wildcardNames, ['b', 'a']);

      await write('new');
      final reloaded = await fresh();
      expect(reloaded.wildcardNames, ['b', 'a', 'new']);
    },
  );

  test('setMode(random) clears the stored mode', () async {
    await write('a');
    final service = await fresh();
    await service.setMode('a', WildcardMode.shuffle);
    await service.setMode('a', WildcardMode.random);
    expect((await fresh()).getMode('a'), WildcardMode.random);
  });

  group('renameWildcard', () {
    test(
      'moves the file and carries favorite, mode and order with it',
      () async {
        await write('old', 'line');
        await write('other');
        final service = await fresh();
        await service.toggleFavorite('old');
        await service.setMode('old', WildcardMode.sequential);
        await service.reorderWildcard(0, 2);

        expect(await service.renameWildcard('old', 'new'), isTrue);
        expect(File(p.join(dir.path, 'old.txt')).existsSync(), isFalse);
        expect(File(p.join(dir.path, 'new.txt')).readAsStringSync(), 'line');

        final reloaded = await fresh();
        expect(reloaded.wildcardNames, contains('new'));
        expect(reloaded.wildcardNames, isNot(contains('old')));
        expect(reloaded.isFavorite('new'), isTrue);
        expect(reloaded.isFavorite('old'), isFalse);
        expect(reloaded.getMode('new'), WildcardMode.sequential);
        expect(reloaded.getMode('old'), WildcardMode.random);
      },
    );

    test(
      'refuses to overwrite an existing wildcard or rename a missing one',
      () async {
        await write('a', 'keep me');
        await write('b');
        final service = await fresh();
        expect(await service.renameWildcard('a', 'b'), isFalse);
        expect(File(p.join(dir.path, 'a.txt')).readAsStringSync(), 'keep me');
        expect(await service.renameWildcard('ghost', 'c'), isFalse);
      },
    );
  });

  group('suggestions', () {
    test('wrap names in __ __ and flag favorites', () async {
      await write('hair_color');
      await write('hair_style');
      await write('pose');
      final service = await fresh();
      await service.toggleFavorite('hair_style');

      final hits = service.getSuggestions('HAIR');
      expect(hits.map((t) => t.tag), ['__hair_style__', '__hair_color__']);
      expect(hits.first.typeName, 'wildcard_favorite');
      expect(hits.last.typeName, 'wildcard');

      expect(service.getAll().length, 3);
      expect(service.getSuggestions('zzz'), isEmpty);
    });
  });
}
