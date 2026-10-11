import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/utils/removable_storage.dart';

void main() {
  const internal = '/storage/emulated/0/Android/data/dev.naiweaver.app/files';
  const sd = '/storage/1234-ABCD/Android/data/dev.naiweaver.app/files';
  const sd2 = '/storage/5678-EF01/Android/data/dev.naiweaver.app/files';

  group('removableStorageDirs', () {
    test('null list means no removable volumes', () {
      expect(removableStorageDirs(null), isEmpty);
    });

    test('empty list means no removable volumes', () {
      expect(removableStorageDirs([]), isEmpty);
    });

    test('a single entry is the primary volume, not removable', () {
      expect(removableStorageDirs([internal]), isEmpty);
    });

    test('entries after index 0 are removable', () {
      expect(removableStorageDirs([internal, sd]), [sd]);
    });

    test('multiple removable volumes all survive, in order', () {
      expect(removableStorageDirs([internal, sd, sd2]), [sd, sd2]);
    });
  });

}
