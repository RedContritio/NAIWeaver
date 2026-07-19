import 'package:path/path.dart' as p;

/// Pure helpers for locating removable-storage (SD card) app directories.
///
/// On Android, `getExternalStorageDirectories()` returns the app-specific
/// files directory on every mounted volume. Index 0 is always the primary
/// (internal/emulated) volume; anything after it is removable media such as
/// an SD card, e.g. `/storage/1234-ABCD/Android/data/dev.naiweaver.app/files`.
/// Those paths are dart:io-writable with zero runtime permissions on every
/// Android version. These helpers are pure so they can be unit-tested
/// without platform channels; paths are always Android-style, so the posix
/// context is used regardless of the host running the tests.

/// Returns the removable-volume app directories (everything after index 0).
List<String> removableStorageDirs(List<String>? externalDirs) {
  if (externalDirs == null || externalDirs.length < 2) return const [];
  return externalDirs.sublist(1);
}

/// The output directory to use inside a removable volume's app files dir.
String removableOutputDir(String appFilesDir) =>
    p.posix.join(appFilesDir, 'output');

/// Extracts a short volume label (e.g. `1234-ABCD`) from an Android
/// app-files path like `/storage/1234-ABCD/Android/data/<pkg>/files`.
/// Falls back to the full path when the shape is unfamiliar.
String volumeLabel(String appFilesDir) {
  final parts = p.posix.split(appFilesDir);
  final storageIdx = parts.indexOf('storage');
  if (storageIdx >= 0 && storageIdx + 1 < parts.length) {
    return parts[storageIdx + 1];
  }
  return appFilesDir;
}
