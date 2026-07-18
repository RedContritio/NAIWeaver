import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/utils/unique_file_path.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('unique_path_');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('returns the base path when nothing exists', () async {
    final path = await uniqueFilePath(tmp.path, 'cat_12345', 'png');
    expect(path, p.join(tmp.path, 'cat_12345.png'));
  });

  test('appends _(2) when the base file exists', () async {
    final base = p.join(tmp.path, 'cat_12345.png');
    await File(base).writeAsBytes([1, 2, 3]);

    final path = await uniqueFilePath(tmp.path, 'cat_12345', 'png');
    expect(path, p.join(tmp.path, 'cat_12345_(2).png'));
  });

  test('keeps incrementing when collisions stack up', () async {
    await File(p.join(tmp.path, 'a.png')).writeAsBytes([0]);
    await File(p.join(tmp.path, 'a_(2).png')).writeAsBytes([0]);
    await File(p.join(tmp.path, 'a_(3).png')).writeAsBytes([0]);

    final path = await uniqueFilePath(tmp.path, 'a', 'png');
    expect(path, p.join(tmp.path, 'a_(4).png'));
  });

  test('handles extension with leading dot', () async {
    final path = await uniqueFilePath(tmp.path, 'b', '.png');
    expect(path, p.join(tmp.path, 'b.png'));
  });

  test('repro: same prompt+seed twice yields different paths', () async {
    // Simulates two generations whose _buildFileName returns the same string
    // (same base prompt, same seed, different character prompts).
    final base = 'a_wizard_12345';
    final first = await uniqueFilePath(tmp.path, base, 'png');
    await File(first).writeAsBytes([1]); // first save claims the slot

    final second = await uniqueFilePath(tmp.path, base, 'png');
    expect(second, isNot(equals(first)));
    expect(second, p.join(tmp.path, '${base}_(2).png'));
  });

  group('nextImageSequence', () {
    test('is 1 for a missing directory', () async {
      expect(
          await nextImageSequence(p.join(tmp.path, 'nope')), 1);
    });

    test('is 1 for an empty directory', () async {
      expect(await nextImageSequence(tmp.path), 1);
    });

    test('counts existing images and adds one', () async {
      await File(p.join(tmp.path, 'a.png')).writeAsBytes([0]);
      await File(p.join(tmp.path, 'b.PNG')).writeAsBytes([0]);
      await File(p.join(tmp.path, 'c.webp')).writeAsBytes([0]);
      expect(await nextImageSequence(tmp.path), 4);
    });

    test('ignores canvas sidecars, non-images, and subfolders', () async {
      await File(p.join(tmp.path, 'a.png')).writeAsBytes([0]);
      await File(p.join(tmp.path, 'a.canvas.json')).writeAsString('{}');
      await File(p.join(tmp.path, 'a.canvas.layer_1.png')).writeAsBytes([0]);
      await File(p.join(tmp.path, 'notes.txt')).writeAsString('x');
      await Directory(p.join(tmp.path, 'sub')).create();
      expect(await nextImageSequence(tmp.path), 2);
    });
  });
}
