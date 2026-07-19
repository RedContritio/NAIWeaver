/// Pure planning logic for moving an output library between directories
/// (issue #21: relocating the generated-images library to an SD card).
///
/// The planner never touches the filesystem: callers scan the source and
/// destination trees into [MigrationFile] lists, and the plan describes, per
/// file, whether it still needs copying or whether a verified copy already
/// exists at the destination (the resume case). Execution lives in
/// `OutputMigrationService`; the per-file contract there is
/// copy → size-verify → delete original, so an interrupted run leaves at
/// worst one partial destination file, which the next plan detects by size
/// mismatch and recopies.
library;

/// A file inside an output library, relative to the library root.
/// [relPath] always uses forward slashes, regardless of host platform.
class MigrationFile {
  final String relPath;
  final int size;
  const MigrationFile(this.relPath, this.size);
}

enum MigrationActionType {
  /// Copy source → destination (fresh file, or the destination copy has a
  /// different size — i.e. a partial copy from an interrupted run).
  copy,

  /// Destination already holds a size-verified copy — only the source file
  /// still needs deleting to complete the move.
  deleteSourceOnly,
}

class MigrationAction {
  final MigrationActionType type;
  final String relPath;
  final int size;
  const MigrationAction(this.type, this.relPath, this.size);
}

/// Space kept free on the destination volume beyond the bytes being copied,
/// so the move can never run the card completely full.
const int migrationHeadroomBytes = 64 * 1024 * 1024;

class MigrationPlan {
  /// Actions sorted by [MigrationAction.relPath], which keeps a canvas PNG
  /// adjacent to its `.canvas.*` sidecars (shared basename prefix).
  final List<MigrationAction> actions;
  const MigrationPlan(this.actions);

  int get totalFiles => actions.length;

  int get bytesToCopy => actions
      .where((a) => a.type == MigrationActionType.copy)
      .fold(0, (sum, a) => sum + a.size);

  /// Whether [freeBytes] of destination space can hold the remaining copies
  /// while preserving [headroomBytes] of slack.
  bool fitsIn(int freeBytes, {int headroomBytes = migrationHeadroomBytes}) =>
      freeBytes - headroomBytes >= bytesToCopy;
}

/// Builds the action list for moving [source] into a directory that already
/// contains [destination]. A destination file with the same relative path and
/// size counts as verified (resume: copied by a previous run); a size
/// mismatch means a partial copy and forces a recopy.
MigrationPlan planMigration({
  required List<MigrationFile> source,
  required List<MigrationFile> destination,
}) {
  final destSizes = {for (final f in destination) f.relPath: f.size};
  final sorted = [...source]..sort((a, b) => a.relPath.compareTo(b.relPath));
  final actions = [
    for (final f in sorted)
      MigrationAction(
        destSizes[f.relPath] == f.size
            ? MigrationActionType.deleteSourceOnly
            : MigrationActionType.copy,
        f.relPath,
        f.size,
      ),
  ];
  return MigrationPlan(actions);
}

/// Human-readable byte count for dialogs ("312.4 MB", "1.2 GB").
String formatMigrationBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}
