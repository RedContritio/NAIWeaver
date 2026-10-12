import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../../../core/utils/file_picker_helper.dart';
import '../../../core/utils/image_utils.dart';
import '../providers/gallery_notifier.dart';

/// One file to import. Content is read lazily, one file at a time, so a large
/// multi-select is never held in memory at once.
class GalleryImportSource {
  const GalleryImportSource({
    required this.name,
    required this.readBytes,
    required this.readModified,
  });

  GalleryImportSource.picked(PlatformFile file)
    : this(
        name: file.name,
        readBytes: () => readPickedFileBytes(file),
        readModified: () => readPickedFileModified(file),
      );

  final String name;
  final Future<Uint8List?> Function() readBytes;

  /// Fallback date for images without an EXIF date; null when unknown.
  final Future<DateTime?> Function() readModified;
}

class GalleryImportService {
  /// Import files into the gallery output directory.
  ///
  /// For each successfully imported file, [onFileImported] is called with the
  /// destination [File] and its source modification date, allowing the caller
  /// to register the file in the gallery.
  Future<ImportResult> importFiles(
    List<GalleryImportSource> sources, {
    required String outputDir,
    required void Function(File file, DateTime date) onFileImported,
    void Function(int current, int total)? onProgress,
  }) async {
    if (kIsWeb) {
      // Filesystem-based import is not available on web. Callers should
      // disable the import UI on web; this guard is defensive.
      return ImportResult(
        total: sources.length,
        succeeded: 0,
        withMetadata: 0,
        converted: 0,
        errors: sources.map((source) => source.name).toList(),
        filesWithMetadata: const [],
      );
    }
    final fmt = DateFormat('yyyyMMdd_HHmmssSSS');
    int succeeded = 0;
    int withMetadata = 0;
    int converted = 0;
    final errors = <String>[];
    final filesWithMetadata = <File>[];

    for (int i = 0; i < sources.length; i++) {
      final source = sources[i];
      onProgress?.call(i + 1, sources.length);
      try {
        final bytes = await source.readBytes();
        if (bytes == null) {
          errors.add(source.name);
          continue;
        }
        Uint8List pngBytes;

        if (isPng(bytes)) {
          pngBytes = bytes;
        } else {
          // Check if the original file had a .png extension or if the bytes
          // Convert to PNG while preserving metadata (NAI Comment chunk, etc.)
          final result = await compute(convertToPngPreservingMetadata, {
            'bytes': bytes,
            'originalBytes': bytes,
          });
          if (result == null) {
            errors.add(source.name);
            continue;
          }
          pngBytes = result;
          converted++;
        }

        // Extract original date from EXIF metadata, falling back to file stat
        final modified = await source.readModified() ?? DateTime.now();
        final extractedDateStr = await compute(extractOriginalDate, {
          'bytes': bytes,
          'statModified': modified.toIso8601String(),
        });
        final sourceDate = DateTime.parse(extractedDateStr);

        // Inject OriginalDate chunk into PNG for refresh resilience
        pngBytes = await compute(injectOriginalDate, {
          'bytes': pngBytes,
          'date': sourceDate.toIso8601String(),
        });

        final now = DateTime.now();
        final destName = 'Imp_${fmt.format(now)}.png';
        final destPath = p.join(outputDir, destName);
        final destFile = File(destPath);
        await destFile.writeAsBytes(pngBytes);
        await destFile.setLastModified(sourceDate);

        onFileImported(destFile, sourceDate);

        // Check for NovelAI metadata
        final metadata = await compute(extractMetadata, pngBytes);
        if (metadata != null && metadata.containsKey('Comment')) {
          withMetadata++;
          filesWithMetadata.add(destFile);
        }

        succeeded++;
      } catch (e) {
        errors.add(source.name);
      }
    }

    return ImportResult(
      total: sources.length,
      succeeded: succeeded,
      withMetadata: withMetadata,
      converted: converted,
      errors: errors,
      filesWithMetadata: filesWithMetadata,
    );
  }
}
