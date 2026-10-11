import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/gateway/backend_gateway.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/novel_ai_service.dart';
import '../../../core/services/reference_library_service.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/file_picker_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../../vibe_transfer/providers/vibe_transfer_notifier.dart';
import '../providers/director_ref_notifier.dart';

// The one implementation of "pick images and add them as references/vibes"
// used by the generation shelves and the Tools → References manager.

/// Picks one or more images and adds each as a precise reference. Stops at
/// the first image that cannot be processed and says so.
Future<void> pickAndAddReferences(
  BuildContext context, {
  bool useFileBrowser = false,
}) async {
  final result = await pickImageFiles(
    allowMultiple: true,
    useFileBrowser: useFileBrowser,
  );
  if (result == null || !context.mounted) return;
  final notifier = context.read<DirectorRefNotifier>();
  for (final file in result.files) {
    final bytes = await readPickedFileBytes(file);
    if (bytes == null) continue;
    if (await notifier.addReference(bytes) == null) {
      if (context.mounted) {
        showErrorSnackBar(context, context.l.refImageProcessFailed);
      }
      return;
    }
  }
}

/// Adds a library entry as a new precise reference, reporting a failure.
Future<void> addSavedReference(
  BuildContext context,
  SavedDirectorRef saved,
) async {
  final id = await context.read<DirectorRefNotifier>().addFromSaved(saved);
  if (id == null && context.mounted) {
    showErrorSnackBar(context, context.l.refImageProcessFailed);
  }
}

/// Picks one or more images and encodes each into a vibe. Stops at the first
/// failure and explains it in the user's language.
Future<void> pickAndAddVibes(BuildContext context) async {
  final result = await pickImageFiles(allowMultiple: true);
  if (result == null || !context.mounted) return;
  final notifier = context.read<VibeTransferNotifier>();
  for (final file in result.files) {
    final bytes = await readPickedFileBytes(file);
    if (bytes == null) continue;
    try {
      await notifier.addVibe(bytes);
    } catch (error) {
      if (context.mounted) {
        showErrorSnackBar(context, vibeEncodeErrorMessage(context.l, error));
      }
      return;
    }
  }
}

/// Readable reason for a failed vibe encode; never the raw exception.
///
/// The gateway answers with a JSON `detail.code` (docs/GATEWAY_CONTRACT.md),
/// but encode-vibe is requested as bytes, so the code is often unavailable
/// and the HTTP status decides. [gateway] defaults to [useBackendGateway].
String vibeEncodeErrorMessage(
  AppLocalizations l,
  Object error, {
  bool? gateway,
}) {
  final viaGateway = gateway ?? useBackendGateway;
  // Through the gateway a 401 is our own session; NovelAI's 401s are never
  // forwarded. Without it, 401 means the user's API key is missing or bad.
  final unauthorized = viaGateway ? l.refErrorSessionExpired : l.refApiKeyMissing;
  if (error is UnauthorizedException) return unauthorized;
  // NovelAIService turns every HTTP/network failure into this exception.
  if (error is! GenerationRequestException) return l.refVibeEncodeFailed;

  switch (error.code) {
    case 'points_insufficient':
    case 'free_allowance_exhausted':
      return l.refErrorPointsInsufficient;
    case 'permission_denied':
      return l.refVibeNoPermission;
    case 'not_authenticated':
      return l.refErrorSessionExpired;
    case 'queue_full':
    case 'upstream_error':
      return l.refErrorServiceUnavailable;
  }
  final status = error.statusCode;
  if (status == null) return l.refErrorNetwork;
  if (status == 401) return unauthorized;
  if (status == 403) return l.refVibeNoPermission;
  // 402: NovelAI is out of Anlas; 409: the gateway could not reserve points.
  if (status == 402 || status == 409) return l.refErrorPointsInsufficient;
  if (status == 429 || status >= 500) return l.refErrorServiceUnavailable;
  return l.refVibeEncodeFailed;
}
