import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/utils/migration_planner.dart';

void main() {
  group('planMigration', () {
    test('empty source yields an empty plan', () {
      final plan = planMigration(source: [], destination: []);
      expect(plan.actions, isEmpty);
      expect(plan.totalFiles, 0);
      expect(plan.bytesToCopy, 0);
    });

    test('fresh migration copies everything', () {
      final plan = planMigration(
        source: [
          const MigrationFile('a.png', 100),
          const MigrationFile('b.png', 200),
        ],
        destination: [],
      );
      expect(plan.actions.length, 2);
      expect(plan.actions.every((a) => a.type == MigrationActionType.copy),
          isTrue);
      expect(plan.bytesToCopy, 300);
    });

    test('verified destination copy becomes deleteSourceOnly (resume)', () {
      final plan = planMigration(
        source: [
          const MigrationFile('a.png', 100),
          const MigrationFile('b.png', 200),
        ],
        destination: [const MigrationFile('a.png', 100)],
      );
      final byPath = {for (final a in plan.actions) a.relPath: a.type};
      expect(byPath['a.png'], MigrationActionType.deleteSourceOnly);
      expect(byPath['b.png'], MigrationActionType.copy);
      expect(plan.bytesToCopy, 200);
    });

    test('size mismatch at destination forces a recopy (partial copy)', () {
      final plan = planMigration(
        source: [const MigrationFile('a.png', 100)],
        destination: [const MigrationFile('a.png', 42)],
      );
      expect(plan.actions.single.type, MigrationActionType.copy);
      expect(plan.bytesToCopy, 100);
    });

    test('files only present at destination are ignored', () {
      final plan = planMigration(
        source: [const MigrationFile('a.png', 100)],
        destination: [
          const MigrationFile('a.png', 100),
          const MigrationFile('finished_earlier.png', 500),
        ],
      );
      expect(plan.actions.map((a) => a.relPath), ['a.png']);
    });

    test('zero-byte files count as verified when present', () {
      final plan = planMigration(
        source: [const MigrationFile('empty.png', 0)],
        destination: [const MigrationFile('empty.png', 0)],
      );
      expect(
          plan.actions.single.type, MigrationActionType.deleteSourceOnly);
    });

    test('actions are sorted so sidecars sit next to their image', () {
      final plan = planMigration(
        source: [
          const MigrationFile('Canvas_1.png', 10),
          const MigrationFile('zzz.png', 10),
          const MigrationFile('Canvas_1.canvas.json', 1),
          const MigrationFile('Canvas_1.canvas.src', 2),
          const MigrationFile('Canvas_1.canvas.layer_a.png', 3),
        ],
        destination: [],
      );
      expect(plan.actions.map((a) => a.relPath).toList(), [
        'Canvas_1.canvas.json',
        'Canvas_1.canvas.layer_a.png',
        'Canvas_1.canvas.src',
        'Canvas_1.png',
        'zzz.png',
      ]);
    });

    test('subfolder paths (save-path patterns) are planned as-is', () {
      final plan = planMigration(
        source: [const MigrationFile('2026/07/19/img.png', 10)],
        destination: [const MigrationFile('2026/07/19/img.png', 10)],
      );
      expect(
          plan.actions.single.type, MigrationActionType.deleteSourceOnly);
    });
  });

  group('MigrationPlan.fitsIn', () {
    final plan = planMigration(
      source: [const MigrationFile('a.png', 1000)],
      destination: [],
    );

    test('rejects when free space minus headroom is too small', () {
      expect(plan.fitsIn(1000, headroomBytes: 1), isFalse);
    });

    test('accepts when free space covers copy bytes plus headroom', () {
      expect(plan.fitsIn(1001, headroomBytes: 1), isTrue);
      expect(plan.fitsIn(1000 + migrationHeadroomBytes), isTrue);
    });

    test('a resume-only plan needs no space', () {
      final resume = planMigration(
        source: [const MigrationFile('a.png', 1000)],
        destination: [const MigrationFile('a.png', 1000)],
      );
      expect(resume.fitsIn(0, headroomBytes: 0), isTrue);
    });
  });

  group('formatMigrationBytes', () {
    test('picks sensible units', () {
      expect(formatMigrationBytes(512), '512 B');
      expect(formatMigrationBytes(2048), '2.0 KB');
      expect(formatMigrationBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatMigrationBytes((30.6 * 1024 * 1024 * 1024).round()),
          '30.6 GB');
    });
  });
}
