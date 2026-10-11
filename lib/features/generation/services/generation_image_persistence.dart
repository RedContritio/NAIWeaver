import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/services/saf_export_service.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/filename_pattern.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/nai_filename.dart';
import '../../../core/utils/unique_file_path.dart';
import '../../../core/utils/web_download.dart';
import '../../../core/widgets/ui/app_tone.dart';
import '../../gallery/providers/gallery_notifier.dart';
import '../../gallery/services/tool_result_saver.dart';

/// Writes generated images out: the gallery folder, browser downloads, the
/// export target and the clipboard. Every method takes the bytes and the
/// metadata of one image, never "the current image", so a result that
/// finishes or is selected meanwhile cannot change what is written.
class GenerationImagePersistence {
  GenerationImagePersistence({
    required PreferencesService prefs,
    required String Function() outputDir,
    required GalleryNotifier? Function() gallery,
  }) : _prefs = prefs,
       _outputDir = outputDir,
       _gallery = gallery;

  final PreferencesService _prefs;
  final String Function() _outputDir;
  final GalleryNotifier? Function() _gallery;

  /// Filenames already triggered as web downloads this session. Web has no
  /// filesystem to probe for collisions like [uniqueFilePath] does, so we track
  /// emitted names here and apply the same `_(2)`, `_(3)`, … suffix convention
  /// when [_buildFileName] yields a name we've handed out before.
  final Set<String> _webDownloadedNames = {};

  /// Generates a NovelAI-style filename from the prompt and seed.
  /// Format: `<prompt> s-<seed>.png`, matching NAI's own convention (issue #28).
  String _buildFileName(
    Map<String, dynamic> metadata, {
    String prefix = 'Gen',
  }) {
    try {
      final prompt = (metadata['prompt'] as String? ?? '').trim();
      final seed = metadata['seed']?.toString() ?? '';
      if (prompt.isNotEmpty && seed.isNotEmpty) {
        return naiFilenameBase(prompt, seed);
      }
    } catch (_) {}
    // Fallback to timestamp
    return '${prefix}_${DateFormat('yyyyMMdd_HHmmssSSS').format(DateTime.now())}';
  }

  /// Name of the default-save album — the album a fresh save lands in — for
  /// the `<album>` pattern token, or '' when none is configured.
  String _defaultSaveAlbumName() {
    final id = _prefs.defaultSaveAlbumId;
    if (id == null || id.isEmpty) return '';
    final albums = _gallery()?.albums;
    if (albums == null) return '';
    for (final album in albums) {
      if (album.id == id) return album.name;
    }
    return '';
  }

  /// Applies the custom filename pattern (issue #27) with [sequence] for
  /// `<digits>` tokens. Returns [fallback] when no pattern is set, when
  /// prompt/seed are unavailable (the same condition under which the
  /// NAI-style default itself applies), or when the pattern expands to
  /// nothing. Used directly for targets whose contents we can't cheaply
  /// count (SAF trees, the device gallery) — there `<digits>` stays at 1.
  String _patternedName(
    Map<String, dynamic>? metadata,
    String fallback, {
    int sequence = 1,
  }) {
    final pattern = _prefs.filenamePattern;
    if (pattern.isEmpty || metadata == null) return fallback;
    final prompt = (metadata['prompt'] as String? ?? '').trim();
    final seed = metadata['seed']?.toString() ?? '';
    if (prompt.isEmpty || seed.isEmpty) return fallback;
    final expanded = expandFilenamePattern(
      pattern,
      FilenamePatternContext(
        prompt: prompt,
        seed: seed,
        savedAt: DateTime.now(),
        albumName: _defaultSaveAlbumName(),
        sequence: sequence,
      ),
    );
    return expanded.isEmpty ? fallback : expanded;
  }

  /// Resolves the destination folder and filename base for a plain-filesystem
  /// save under [baseDir] from the pattern settings (issue #27). The path
  /// pattern can add auto-subfolders; `<digits>` counts the images already in
  /// the final folder, so counters reset per subfolder.
  Future<_SaveTarget> _patternedTarget(
    String baseDir,
    Map<String, dynamic> metadata,
    String fallbackBase,
  ) async {
    final pathPattern = _prefs.savePathPattern;
    final fnPattern = _prefs.filenamePattern;
    final prompt = (metadata['prompt'] as String? ?? '').trim();
    final seed = metadata['seed']?.toString() ?? '';
    if ((pathPattern.isEmpty && fnPattern.isEmpty) ||
        prompt.isEmpty ||
        seed.isEmpty) {
      return _SaveTarget(baseDir, fallbackBase);
    }
    final savedAt = DateTime.now();
    final albumName = _defaultSaveAlbumName();
    var dirPath = baseDir;
    final sub = expandSavePathPattern(
      pathPattern,
      FilenamePatternContext(
        prompt: prompt,
        seed: seed,
        savedAt: savedAt,
        albumName: albumName,
      ),
    );
    if (sub.isNotEmpty) dirPath = p.join(dirPath, sub);
    var base = fallbackBase;
    if (fnPattern.isNotEmpty) {
      // Only pay for a directory listing when the pattern actually counts.
      final seq = fnPattern.contains('<digits')
          ? await nextImageSequence(dirPath)
          : 1;
      final expanded = expandFilenamePattern(
        fnPattern,
        FilenamePatternContext(
          prompt: prompt,
          seed: seed,
          savedAt: savedAt,
          albumName: albumName,
          sequence: seq,
        ),
      );
      if (expanded.isNotEmpty) base = expanded;
    }
    return _SaveTarget(dirPath, base);
  }

  /// Returns [baseName] if it hasn't been downloaded this session, otherwise
  /// appends `_(2)`, `_(3)`, … — the same convention as [uniqueFilePath], but
  /// tracked in memory since web has no filesystem to probe. The returned name
  /// is the bare base (no extension); the caller adds `.png`.
  String _uniqueWebName(String baseName) {
    if (!_webDownloadedNames.contains('$baseName.png')) return baseName;
    var i = 2;
    while (_webDownloadedNames.contains('${baseName}_($i).png')) {
      i++;
    }
    return '${baseName}_($i)';
  }

  /// Writes [bytes] with [metadata] into the gallery folder and returns the
  /// file name, or null on web (no filesystem) and when the write failed.
  Future<String?> saveToGallery(
    Uint8List bytes,
    Map<String, dynamic> metadata, {
    String prefix = 'Gen',
    String? timestamp,
  }) async {
    final file = await _writeToDisk(
      bytes,
      metadata,
      prefix: prefix,
      timestamp: timestamp,
    );
    if (file == null) return null;
    _gallery()?.addFile(file, DateTime.now());
    return p.basename(file.path);
  }

  /// The save the user asked for: a browser download on web, the gallery
  /// folder (plus the auto-export target) elsewhere. Returns the saved file
  /// name, or null when nothing was written.
  Future<String?> save(Uint8List bytes, Map<String, dynamic> metadata) async {
    // Web has no filesystem; trigger a browser download of the image (with
    // metadata injected) instead so the SAVE button isn't a silent no-op.
    if (kIsWeb) {
      final baseName = _uniqueWebName(_buildFileName(metadata));
      final bytesWithMetadata = await compute(injectMetadata, {
        'bytes': bytes,
        'metadata': metadata,
      });
      if (!downloadBytes(bytesWithMetadata, '$baseName.png')) return null;
      _webDownloadedNames.add('$baseName.png');
      return '$baseName.png';
    }
    final basename = await saveToGallery(bytes, metadata);
    if (basename != null) await autoExportIfEnabled(bytes, metadata);
    return basename;
  }

  /// The save after a generation finished (the "auto save" setting): gallery
  /// folder plus export target; never a browser download.
  Future<String?> autoSave(
    Uint8List bytes,
    Map<String, dynamic> metadata, {
    String? timestamp,
  }) async {
    if (kIsWeb) return null;
    final basename = await saveToGallery(bytes, metadata, timestamp: timestamp);
    if (basename != null) await autoExportIfEnabled(bytes, metadata);
    return basename;
  }

  /// The auto save of an img2img result: the gallery write is the one every
  /// tool result goes through ([ToolResultSaver]), with the generation
  /// metadata injected first so the file can be imported again.
  Future<String?> autoSaveToolResult(
    Uint8List bytes,
    Map<String, dynamic> metadata, {
    required String fileName,
  }) async {
    final gallery = _gallery();
    if (kIsWeb || gallery == null) return null;
    final withMetadata = await compute(injectMetadata, {
      'bytes': bytes,
      'metadata': metadata,
    });
    final outcome = await ToolResultSaver(
      writeToGallery: gallery.saveMLResultWithMetadata,
    ).save(withMetadata, fileName);
    if (!outcome.succeeded) return null;
    await autoExportIfEnabled(bytes, metadata);
    return fileName;
  }

  Future<File?> _writeToDisk(
    Uint8List bytes,
    Map<String, dynamic> metadata, {
    String prefix = 'Gen',
    String? timestamp,
  }) async {
    // No filesystem on web. Bytes remain in memory; users use the existing
    // download/share path (XFile / share_plus) to get the image off-app.
    if (kIsWeb) return null;
    try {
      // Explicit-timestamp saves (img2img Src/Gen pairs) keep their fixed
      // names and flat location; the pattern settings apply to standard
      // generation saves (issue #27).
      final target = timestamp != null
          ? _SaveTarget(_outputDir(), '${prefix}_$timestamp')
          : await _patternedTarget(
              _outputDir(),
              metadata,
              _buildFileName(metadata, prefix: prefix),
            );
      final directory = Directory(target.dir);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final filePath = await uniqueFilePath(directory.path, target.base, 'png');

      final bytesWithMetadata = await compute(injectMetadata, {
        'bytes': bytes,
        'metadata': metadata,
      });

      final file = File(filePath);
      await file.writeAsBytes(bytesWithMetadata);
      return file;
    } catch (e) {
      debugPrint("Save error: $e");
      return null;
    }
  }

  /// Copies [image] to the system clipboard.
  /// On desktop, uses super_clipboard for native image copy.
  /// On mobile, uses share_plus to share the image (native clipboard is unreliable).
  Future<void> copyToClipboard(BuildContext context, Uint8List image) async {
    // Mobile: use share sheet (super_clipboard's native lib is missing on Android)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final timestamp = DateFormat(
          'yyyyMMdd_HHmmssSSS',
        ).format(DateTime.now());
        await Share.shareXFiles([
          XFile.fromData(
            image,
            mimeType: 'image/png',
            name: 'Gen_$timestamp.png',
          ),
        ]);
      } catch (e) {
        if (context.mounted) {
          showAppSnackBar(context, context.l.galleryShareFailed('$e'), tone: AppTone.error);
        }
      }
      return;
    }

    // Desktop: use super_clipboard for native image clipboard
    try {
      final item = DataWriterItem();
      item.add(Formats.png(image));
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        await clipboard.write([item]);
        if (context.mounted) {
          showAppSnackBar(context, context.l.galleryCopiedToClipboard);
        }
        return;
      }
    } catch (_) {}
    if (context.mounted) {
      showAppSnackBar(context, context.l.galleryClipboardUnavailable, tone: AppTone.error);
    }
  }

  /// Exports [image] to the custom folder, device gallery, or file dialog.
  Future<void> exportToDevice(
    BuildContext context,
    Uint8List image,
    Map<String, dynamic>? metadata,
  ) async {
    try {
      final fallbackName = metadata != null
          ? _buildFileName(metadata)
          : 'Gen_${DateFormat('yyyyMMdd_HHmmssSSS').format(DateTime.now())}';
      // Custom filename pattern (issue #27); `<digits>` can't count a SAF
      // tree or the device gallery, so it stays at 1 for those targets.
      final exportName = _patternedName(metadata, fallbackName);

      // If a custom export folder is set, write directly there (any platform)
      final customFolder = _prefs.exportFolderPath;
      if (customFolder.isNotEmpty && !kIsWeb) {
        // For a SAF (SD-card) target, verify we still hold the write grant —
        // the card may have been removed or permission revoked. For a legacy
        // plain filesystem path on Android, scoped storage makes it unreachable.
        // Either way a clear message beats the cryptic PathAccessException
        // users used to see (issue #13).
        final unreachable =
            SafExportService.isStalePlainPath(customFolder) ||
            (SafExportService.isSafUri(customFolder) &&
                !await SafExportService.instance.hasWriteAccess(customFolder));
        if (unreachable) {
          if (context.mounted) {
            showAppSnackBar(
              context,
              context.l.galleryExportFolderUnavailable,
              tone: AppTone.error,
            );
          }
          return;
        }
        if (SafExportService.isSafUri(customFolder)) {
          await _exportToFolder(image, customFolder, exportName);
        } else {
          // Plain folders also honor the path pattern's auto-subfolders and
          // per-folder <digits> counting (issue #27).
          final target = await _patternedTarget(
            customFolder,
            metadata ?? const {},
            fallbackName,
          );
          await _exportToFolder(image, target.dir, target.base);
        }
        if (context.mounted) {
          final label = SafExportService.isSafUri(customFolder)
              ? context.l.gallerySdCard
              : p.basename(customFolder);
          showAppSnackBar(context, context.l.gallerySavedTo(label));
        }
        return;
      }

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _exportBytesToMobileGallery(image, exportName);
        if (context.mounted) {
          showAppSnackBar(context, context.l.gallerySavedToDevice);
        }
      } else {
        // Desktop: show save file dialog
        final result = await FilePicker.platform.saveFile(
          dialogTitle: context.l.galleryExportImageDialog,
          fileName: '$exportName.png',
          type: FileType.image,
        );
        if (result == null) return;
        await File(result).writeAsBytes(image);
        if (context.mounted) {
          showAppSnackBar(
            context,
            context.l.gallerySavedTo(p.basename(result)),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, context.l.galleryExportFailed('$e'), tone: AppTone.error);
      }
    }
  }

  Future<void> _exportBytesToMobileGallery(
    Uint8List bytes,
    String exportName,
  ) async {
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      final granted = await Gal.requestAccess();
      if (!granted) return;
    }
    final album = _prefs.exportAlbumName;
    await Gal.putImageBytes(bytes, name: exportName, album: album);
  }

  Future<void> _exportToFolder(
    Uint8List bytes,
    String folderPath,
    String fileName,
  ) async {
    // A SAF tree URI (content://…) targets a folder we can only reach through
    // the Storage Access Framework — e.g. a removable SD card (issue #13).
    if (SafExportService.isSafUri(folderPath)) {
      await SafExportService.instance.writePng(folderPath, fileName, bytes);
      return;
    }
    final dir = Directory(folderPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(await uniqueFilePath(folderPath, fileName, 'png'));
    await file.writeAsBytes(bytes);
  }

  Future<void> autoExportIfEnabled(
    Uint8List bytes,
    Map<String, dynamic> metadata,
  ) async {
    if (!_prefs.autoExportToDevice) return;
    try {
      final fallbackName = _buildFileName(metadata);

      // Custom folder takes priority on all platforms — but a legacy plain
      // filesystem path is unreachable under Android scoped storage (issue
      // #13), so skip it and fall through to the device gallery rather than
      // throwing a PathAccessException into the catch below (which would
      // silently drop the auto-export).
      final customFolder = _prefs.exportFolderPath;
      if (customFolder.isNotEmpty &&
          !kIsWeb &&
          !SafExportService.isStalePlainPath(customFolder)) {
        if (SafExportService.isSafUri(customFolder)) {
          await _exportToFolder(
            bytes,
            customFolder,
            _patternedName(metadata, fallbackName),
          );
        } else {
          final target = await _patternedTarget(
            customFolder,
            metadata,
            fallbackName,
          );
          await _exportToFolder(bytes, target.dir, target.base);
        }
        return;
      }

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _exportBytesToMobileGallery(
          bytes,
          _patternedName(metadata, fallbackName),
        );
      } else if (!kIsWeb) {
        final target = await _patternedTarget(
          _outputDir(),
          metadata,
          fallbackName,
        );
        await _exportToFolder(bytes, target.dir, target.base);
      }
    } catch (e) {
      debugPrint('Auto-export failed: $e');
    }
  }
}

/// Destination folder + filename base resolved from the pattern settings
/// (issue #27).
class _SaveTarget {
  final String dir;
  final String base;
  const _SaveTarget(this.dir, this.base);
}
