import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns a path under [directoryPath] using [baseName].[extension], appending
/// `_(2)`, `_(3)`, ... if the file already exists, until a free name is found.
///
/// Used so that generations with identical filename inputs (same prompt + seed
/// but different character prompts, for example) don't silently overwrite each
/// other. See issue #12.
/// Next value for a `<digits>` sequence counter in [directoryPath]: one more
/// than the number of images already there (issue #27). Counting — rather
/// than parsing numbers back out of arbitrary user patterns — keeps this a
/// single directory listing and resets naturally in each auto-created
/// subfolder; [uniqueFilePath] still guards the final name if two saves race
/// to the same number.
Future<int> nextImageSequence(String directoryPath) async {
  final dir = Directory(directoryPath);
  if (!await dir.exists()) return 1;
  var count = 0;
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path).toLowerCase();
    if (name.contains('.canvas.')) continue; // canvas sidecar files
    final ext = p.extension(name);
    if (ext == '.png' || ext == '.webp' || ext == '.jpg' || ext == '.jpeg') {
      count++;
    }
  }
  return count + 1;
}

Future<String> uniqueFilePath(
  String directoryPath,
  String baseName,
  String extension,
) async {
  final ext = extension.startsWith('.') ? extension.substring(1) : extension;
  final candidate = p.join(directoryPath, '$baseName.$ext');
  if (!await File(candidate).exists()) {
    return candidate;
  }
  var i = 2;
  while (true) {
    final next = p.join(directoryPath, '${baseName}_($i).$ext');
    if (!await File(next).exists()) {
      return next;
    }
    i++;
    if (i > 9999) {
      // Defensive ceiling: should never hit in practice. Fall back to a
      // timestamp-suffixed name rather than spin forever.
      return p.join(
        directoryPath,
        '${baseName}_${DateTime.now().microsecondsSinceEpoch}.$ext',
      );
    }
  }
}
