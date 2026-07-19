import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/output_migration_service.dart';
import 'package:naiweaver/core/utils/migration_planner.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late String source;
  late String dest;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('output_migration_');
    source = p.join(tmp.path, 'src');
    dest = p.join(tmp.path, 'dst');
    await Directory(source).create(recursive: true);
    await Directory(dest).create(recursive: true);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  Future<void> writeSource(String relPath, String content) async {
    final f = File(p.joinAll([source, ...relPath.split('/')]));
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
  }

  Future<void> writeDest(String relPath, String content) async {
    final f = File(p.joinAll([dest, ...relPath.split('/')]));
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
  }

  String readDest(String relPath) =>
      File(p.joinAll([dest, ...relPath.split('/')])).readAsStringSync();

  bool sourceExists(String relPath) =>
      File(p.joinAll([source, ...relPath.split('/')])).existsSync();

  Future<MigrationPlan> planFor() async => planMigration(
        source: await OutputMigrationService.scanDir(source),
        destination: await OutputMigrationService.scanDir(dest),
      );

  test('scanDir returns [] for a missing directory', () async {
    expect(
        await OutputMigrationService.scanDir(p.join(tmp.path, 'nope')), isEmpty);
  });

  test('scanDir reports forward-slash relative paths and sizes', () async {
    await writeSource('a.png', 'aaaa');
    await writeSource('2026/07/img.png', 'bb');
    final files = await OutputMigrationService.scanDir(source);
    final bySize = {for (final f in files) f.relPath: f.size};
    expect(bySize, {'a.png': 4, '2026/07/img.png': 2});
  });

  test('fresh move copies, verifies, and deletes sources', () async {
    await writeSource('img.png', 'image-bytes');
    await writeSource('img.canvas.json', '{}');
    await writeSource('2026/07/nested.png', 'nested');

    final progress = <(int, int)>[];
    final removed = <String>[];
    final result = await OutputMigrationService.run(
      sourceDir: source,
      destDir: dest,
      plan: await planFor(),
      onProgress: (done, total) => progress.add((done, total)),
      onSourceFileRemoved: removed.add,
    );

    expect(result.moved, 3);
    expect(result.failed, 0);
    expect(result.cancelled, isFalse);
    expect(readDest('img.png'), 'image-bytes');
    expect(readDest('img.canvas.json'), '{}');
    expect(readDest('2026/07/nested.png'), 'nested');
    expect(sourceExists('img.png'), isFalse);
    expect(sourceExists('img.canvas.json'), isFalse);
    expect(sourceExists('2026/07/nested.png'), isFalse);
    expect(progress.length, 3);
    expect(progress.last, (3, 3));
    expect(removed.length, 3);
  });

  test('resume deletes sources whose verified copies already exist',
      () async {
    await writeSource('done.png', 'same-size');
    await writeDest('done.png', 'same-size');
    await writeSource('todo.png', 'fresh');

    final result = await OutputMigrationService.run(
      sourceDir: source,
      destDir: dest,
      plan: await planFor(),
    );

    expect(result.moved, 2);
    expect(result.failed, 0);
    expect(sourceExists('done.png'), isFalse);
    expect(sourceExists('todo.png'), isFalse);
    expect(readDest('todo.png'), 'fresh');
  });

  test('a partial destination file is recopied, not trusted', () async {
    await writeSource('img.png', 'full-content');
    await writeDest('img.png', 'part');

    final result = await OutputMigrationService.run(
      sourceDir: source,
      destDir: dest,
      plan: await planFor(),
    );

    expect(result.moved, 1);
    expect(readDest('img.png'), 'full-content');
    expect(sourceExists('img.png'), isFalse);
  });

  test('cancel stops between files and leaves the rest in place', () async {
    for (var i = 0; i < 5; i++) {
      await writeSource('img_$i.png', 'content-$i');
    }

    var processed = 0;
    final result = await OutputMigrationService.run(
      sourceDir: source,
      destDir: dest,
      plan: await planFor(),
      onProgress: (done, total) => processed = done,
      shouldCancel: () => processed >= 2,
    );

    expect(result.cancelled, isTrue);
    expect(result.moved, 2);
    final remaining = await OutputMigrationService.scanDir(source);
    expect(remaining.length, 3);
    // A rerun from a fresh plan finishes the job.
    final second = await OutputMigrationService.run(
      sourceDir: source,
      destDir: dest,
      plan: await planFor(),
    );
    expect(second.moved, 3);
    expect(await OutputMigrationService.scanDir(source), isEmpty);
    expect((await OutputMigrationService.scanDir(dest)).length, 5);
  });

  test('refuses to run with source == destination (would self-delete)',
      () async {
    await writeSource('img.png', 'precious');
    await expectLater(
      OutputMigrationService.run(
        sourceDir: source,
        destDir: source,
        plan: await planFor(),
      ),
      throwsArgumentError,
    );
    expect(sourceExists('img.png'), isTrue);
  });

  test('a failed copy keeps the source and reports the error', () async {
    await writeSource('ok.png', 'fine');
    await writeSource('bad.png', 'doomed');
    // Make the destination path uncopyable by occupying it with a directory.
    await Directory(p.join(dest, 'bad.png')).create(recursive: true);

    final result = await OutputMigrationService.run(
      sourceDir: source,
      destDir: dest,
      plan: await planFor(),
    );

    expect(result.moved, 1);
    expect(result.failed, 1);
    expect(result.errors, hasLength(1));
    expect(result.errors.single, contains('bad.png'));
    expect(sourceExists('bad.png'), isTrue);
    expect(sourceExists('ok.png'), isFalse);
  });
}
