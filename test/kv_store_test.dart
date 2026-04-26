import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/kv_store.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('kv_store_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('KvStore (native)', () {
    test('returns null when file does not exist', () async {
      final result = await KvStore.readString(
        path: p.join(tmp.path, 'missing.json'),
        prefsKey: 'kv_test_missing',
      );
      expect(result, isNull);
    });

    test('round-trips a string via the file backend', () async {
      final path = p.join(tmp.path, 'value.json');
      await KvStore.writeString(
        path: path,
        prefsKey: 'kv_test_value',
        value: '{"a":1}',
      );

      expect(await File(path).exists(), isTrue);
      expect(await File(path).readAsString(), '{"a":1}');

      final read = await KvStore.readString(
        path: path,
        prefsKey: 'kv_test_value',
      );
      expect(read, '{"a":1}');
    });

    test('overwrites existing file content', () async {
      final path = p.join(tmp.path, 'value.json');
      await KvStore.writeString(path: path, prefsKey: 'k', value: 'first');
      await KvStore.writeString(path: path, prefsKey: 'k', value: 'second');
      expect(await KvStore.readString(path: path, prefsKey: 'k'), 'second');
    });

    test('creates parent directories on write', () async {
      final path = p.join(tmp.path, 'nested', 'deeper', 'file.json');
      await KvStore.writeString(path: path, prefsKey: 'k', value: 'hi');
      expect(await File(path).exists(), isTrue);
    });

    test('treats empty file as null', () async {
      final path = p.join(tmp.path, 'empty.json');
      await File(path).writeAsString('');
      expect(
        await KvStore.readString(path: path, prefsKey: 'k'),
        isNull,
      );
    });

    test('exists() reflects file presence', () async {
      final path = p.join(tmp.path, 'present.json');
      expect(await KvStore.exists(path: path, prefsKey: 'k'), isFalse);
      await KvStore.writeString(path: path, prefsKey: 'k', value: 'x');
      expect(await KvStore.exists(path: path, prefsKey: 'k'), isTrue);
    });

    test('remove() deletes the file', () async {
      final path = p.join(tmp.path, 'gone.json');
      await KvStore.writeString(path: path, prefsKey: 'k', value: 'x');
      await KvStore.remove(path: path, prefsKey: 'k');
      expect(await File(path).exists(), isFalse);
    });

    test('remove() of missing file is a no-op', () async {
      await KvStore.remove(
        path: p.join(tmp.path, 'never_existed.json'),
        prefsKey: 'k',
      );
    });
  });
}
