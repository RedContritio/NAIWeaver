import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../../../core/utils/image_utils.dart';
import '../providers/gallery_notifier.dart';

class GalleryImportService {
  /// Import files into the gallery output directory.
  ///
  /// For each successfully imported file, [onFileImported] is called with the
  /// destination [File] and its source modification date, allowing the caller
  /// to register the file in the gallery.
  Future<ImportResult> importFiles(
    List<String> filePaths, {
    required String outputDir,
    required void Function(File file, DateTime date) onFileImported,
    void Function(int current, int total)? onProgress,
  }) async {
    final fmt = DateFormat('yyyyMMdd_HHmmssSSS');
    int succeeded = 0;
    int withMetadata = 0;
    int converted = 0;
    final errors = <String>[];
    final filesWithMetadata = <File>[];

    for (int i = 0; i < filePaths.length; i++) {
      onProgress?.call(i + 1, filePaths.length);
      try {
        final srcFile = File(filePaths[i]);
        final bytes = await srcFile.readAsBytes();
        Uint8List pngBytes;

        if (isPng(bytes)) {
          pngBytes = bytes;
        } else {
          // Check if the original file had a .png extension or if the bytes
          // look like a JPEG transcoded from PNG — Android's SAF photo picker
          // may transcode PNGs, stripping metadata chunks. Content URIs may
          // also lack a proper extension, so also check for JPEG magic bytes
          // when no extension is present.
          final ext = p.extension(filePaths[i]).toLowerCase();
          final isJpeg = bytes.length >= 3 &&
              bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
          final likelyTranscoded = ext == '.png' ||
              (isJpeg && (ext.isEmpty || ext == '.'));
          if (likelyTranscoded) {
            // Likely transcoded from PNG — convert back to PNG.
            final result = await compute(convertToPng, bytes);
            if (result == null) {
              errors.add(p.basename(filePaths[i]));
              continue;
            }
            pngBytes = result;
          } else {
            final result = await compute(convertToPng, bytes);
            if (result == null) {
              errors.add(p.basename(filePaths[i]));
              continue;
            }
            pngBytes = result;
          }
          converted++;
        }

        // Extract original date from EXIF metadata, falling back to file stat
        final srcStat = await srcFile.stat();
        final extractedDateStr = await compute(extractOriginalDate, {
          'bytes': bytes,
          'statModified': srcStat.modified.toIso8601String(),
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
        errors.add(p.basename(filePaths[i]));
      }
    }

    return ImportResult(
      total: filePaths.length,
      succeeded: succeeded,
      withMetadata: withMetadata,
      converted: converted,
      errors: errors,
      filesWithMetadata: filesWithMetadata,
    );
  }
}
