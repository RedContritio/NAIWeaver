import 'package:flutter/foundation.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

/// Thin wrapper around the Storage Access Framework (SAF) for exporting images
/// to a user-chosen folder — including a removable SD card, which plain
/// `dart:io` `File` writes cannot reach under Android scoped storage (issue #13).
///
/// The export-folder preference stores either a plain filesystem path (internal
/// storage, written via `dart:io`) or a SAF tree URI (`content://…`, written
/// via this service). [isSafUri] distinguishes the two so callers can route a
/// write to the correct backend.
class SafExportService {
  SafExportService._();
  static final SafExportService instance = SafExportService._();

  final SafUtil _util = SafUtil();
  final SafStream _stream = SafStream();

  /// True if [path] is a SAF document-tree URI rather than a filesystem path.
  static bool isSafUri(String path) => path.startsWith('content://');

  /// SAF is only available on Android. Other platforms keep using `dart:io`.
  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Opens the system folder picker and requests a persistable write grant.
  /// Returns the chosen folder, or null if the user cancelled.
  ///
  /// The returned [SafFolder.uri] is a `content://…` string safe to store in
  /// preferences; the grant survives reboots thanks to `persistablePermission`.
  Future<SafFolder?> pickFolder() async {
    final dir = await _util.pickDirectory(
      writePermission: true,
      persistablePermission: true,
    );
    if (dir == null) return null;
    return SafFolder(uri: dir.uri, name: dir.name);
  }

  /// Whether we still hold a persisted write grant for [treeUri]. The user can
  /// revoke access (or pop the SD card), so callers should re-check before use.
  Future<bool> hasWriteAccess(String treeUri) async {
    try {
      return await _util.hasPersistedPermission(treeUri, checkWrite: true);
    } catch (_) {
      return false;
    }
  }

  /// Writes [bytes] as `<fileName>.png` into the SAF tree [treeUri].
  /// A `.png` extension is appended if not already present.
  Future<void> writePng(String treeUri, String fileName, Uint8List bytes) async {
    final name = fileName.toLowerCase().endsWith('.png') ? fileName : '$fileName.png';
    await _stream.writeFileBytes(treeUri, name, 'image/png', bytes);
  }
}

/// A picked SAF folder: a persistable [uri] plus a human-readable [name].
class SafFolder {
  final String uri;
  final String name;
  const SafFolder({required this.uri, required this.name});
}
