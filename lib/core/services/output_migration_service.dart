import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/migration_planner.dart';

/// Outcome of executing a [MigrationPlan].
class OutputMigrationResult {
  /// Files whose move fully completed (copied + size-verified + source
  /// deleted, or a previously verified copy whose source was deleted).
  final int moved;

  /// Files that errored (copy failure or post-copy size mismatch). Their
  /// sources are left in place, so a retry can pick them up.
  final int failed;

  /// True when [OutputMigrationService.run] stopped early via `shouldCancel`.
  final bool cancelled;

  /// First few error messages, for logs/snackbars.
  final List<String> errors;

  const OutputMigrationResult({
    required this.moved,
    required this.failed,
    required this.cancelled,
    required this.errors,
  });
}

/// Executes output-library moves planned by [planMigration].
///
/// Per-file contract: copy → size-verify → delete original. Files are
/// processed one at a time, so an interrupted run leaves at worst one
/// partial destination file, which the next plan detects by size mismatch
/// and recopies. Sources are only ever deleted after the destination copy
/// is verified.
class OutputMigrationService {
  OutputMigrationService._();

  /// Recursively lists regular files under [root] as root-relative
  /// forward-slash paths with sizes. A missing directory yields `[]`.
  static Future<List<MigrationFile>> scanDir(String root) async {
    final dir = Directory(root);
    if (!await dir.exists()) return const [];
    final files = <MigrationFile>[];
    await for (final entity
        in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel =
          p.relative(entity.path, from: root).replaceAll('\\', '/');
      files.add(MigrationFile(rel, await entity.length()));
    }
    return files;
  }

  static String _abs(String root, String relPath) =>
      p.joinAll([root, ...relPath.split('/')]);

  /// Runs [plan], moving files from [sourceDir] to [destDir].
  ///
  /// [onProgress] fires after every file with (done, total). [shouldCancel]
  /// is checked between files; cancelling never leaves a file half-moved on
  /// the source side. [onSourceFileRemoved] fires with the absolute source
  /// path of each deleted original so callers can evict image caches.
  static Future<OutputMigrationResult> run({
    required String sourceDir,
    required String destDir,
    required MigrationPlan plan,
    void Function(int done, int total)? onProgress,
    bool Function()? shouldCancel,
    void Function(String absoluteSourcePath)? onSourceFileRemoved,
  }) async {
    var done = 0;
    var moved = 0;
    var failed = 0;
    var cancelled = false;
    final errors = <String>[];

    for (final action in plan.actions) {
      if (shouldCancel?.call() ?? false) {
        cancelled = true;
        break;
      }
      final src = File(_abs(sourceDir, action.relPath));
      final dst = File(_abs(destDir, action.relPath));
      try {
        if (action.type == MigrationActionType.copy) {
          await dst.parent.create(recursive: true);
          await src.copy(dst.path);
          final copiedLength = await dst.length();
          final sourceLength = await src.length();
          if (copiedLength != sourceLength) {
            throw FileSystemException(
                'size mismatch after copy ($copiedLength != $sourceLength)',
                dst.path);
          }
          await src.delete();
        } else {
          // Destination was size-verified at plan time; finish the move.
          if (await src.exists()) await src.delete();
        }
        onSourceFileRemoved?.call(src.path);
        moved++;
      } catch (e) {
        failed++;
        if (errors.length < 10) errors.add('${action.relPath}: $e');
      }
      done++;
      onProgress?.call(done, plan.totalFiles);
    }

    return OutputMigrationResult(
      moved: moved,
      failed: failed,
      cancelled: cancelled,
      errors: errors,
    );
  }
}
