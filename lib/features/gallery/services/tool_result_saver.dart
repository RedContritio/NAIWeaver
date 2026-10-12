import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/web_download.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../providers/gallery_notifier.dart';

/// Where a saved tool result ended up.
enum ToolResultDestination { gallery, download }

class ToolResultSaveOutcome {
  const ToolResultSaveOutcome.saved(
    this.fileName,
    ToolResultDestination this.destination,
  ) : error = null;

  const ToolResultSaveOutcome.failed(this.fileName, Object this.error)
    : destination = null;

  final String fileName;

  /// Null when nothing was written.
  final ToolResultDestination? destination;
  final Object? error;

  bool get succeeded => destination != null;
}

typedef GalleryResultWriter =
    Future<void> Function(
      Uint8List bytes,
      String fileName, {
      Uint8List? sourceBytes,
    });

typedef BrowserDownload = bool Function(List<int> bytes, String fileName);

/// Persists tool output (Enhance, Director Tools, NAI and local ML actions).
///
/// Web has no filesystem gallery, so results are downloaded through the
/// browser; native platforms write them into the gallery. Both carry the
/// source image's metadata over when [sourceBytes] is given. Failures are
/// returned rather than thrown, so callers can report what really happened.
class ToolResultSaver {
  ToolResultSaver({
    required GalleryResultWriter writeToGallery,
    bool? web,
    BrowserDownload? download,
  }) : _writeToGallery = writeToGallery,
       _web = web ?? kIsWeb,
       _download = download ?? downloadBytes;

  ToolResultSaver.of(BuildContext context)
    : this(
        writeToGallery: context
            .read<GalleryNotifier>()
            .saveMLResultWithMetadata,
      );

  final GalleryResultWriter _writeToGallery;
  final bool _web;
  final BrowserDownload _download;

  Future<ToolResultSaveOutcome> save(
    Uint8List bytes,
    String fileName, {
    Uint8List? sourceBytes,
  }) async {
    try {
      if (_web) {
        final payload = sourceBytes == null
            ? bytes
            : await GalleryNotifier.withSourceMetadata(bytes, sourceBytes);
        if (!_download(payload, fileName)) {
          throw StateError('The browser download did not start');
        }
        return ToolResultSaveOutcome.saved(
          fileName,
          ToolResultDestination.download,
        );
      }
      await _writeToGallery(bytes, fileName, sourceBytes: sourceBytes);
      return ToolResultSaveOutcome.saved(
        fileName,
        ToolResultDestination.gallery,
      );
    } catch (e) {
      debugPrint('ToolResultSaver: saving $fileName failed: $e');
      return ToolResultSaveOutcome.failed(fileName, e);
    }
  }
}

/// Saves a tool result and tells the user what really happened.
///
/// Uses the gallery from [context] unless a [saver] is given. A gallery save
/// shows [savedMessage] (default: the saved file name), a Web download shows a
/// download notice, and a failure shows an error instead of a success.
Future<ToolResultSaveOutcome> saveToolResult(
  BuildContext context, {
  required Uint8List bytes,
  required String fileName,
  Uint8List? sourceBytes,
  String? savedMessage,
  ToolResultSaver? saver,
}) async {
  final outcome = await (saver ?? ToolResultSaver.of(context)).save(
    bytes,
    fileName,
    sourceBytes: sourceBytes,
  );
  if (context.mounted) {
    showToolResultSaveFeedback(context, outcome, savedMessage: savedMessage);
  }
  return outcome;
}

void showToolResultSaveFeedback(
  BuildContext context,
  ToolResultSaveOutcome outcome, {
  String? savedMessage,
}) {
  final l = context.l;
  switch (outcome.destination) {
    case ToolResultDestination.gallery:
      showAppSnackBar(
        context,
        savedMessage ?? l.gallerySavedTo(outcome.fileName),
      );
    case ToolResultDestination.download:
      showAppSnackBar(context, l.galleryResultDownloaded(outcome.fileName));
    case null:
      showErrorSnackBar(context, l.galleryResultSaveFailed('${outcome.error}'));
  }
}

/// Asks before a tool's back action throws away a result that was never
/// saved. Returns true when it is fine to leave.
Future<bool> confirmDiscardUnsavedResult(BuildContext context) async {
  final l = context.l;
  final confirmed = await showConfirmDialog(
    context,
    title: l.toolDiscardResultTitle,
    message: l.toolDiscardResultMessage,
    confirmLabel: l.toolDiscardResultConfirm,
    cancelLabel: l.commonCancel,
  );
  return confirmed == true;
}
