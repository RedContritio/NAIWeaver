import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/novel_ai_image_action_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../l10n/app_localizations.dart';

String novelAiImageActionBlockerMessage(
  AppLocalizations l,
  NovelAiImageActionBlocker blocker,
) => switch (blocker) {
  NovelAiImageActionBlocker.permissionDenied => l.naiActionNotPermitted,
  NovelAiImageActionBlocker.missingApiKey => l.naiApiKeyRequired,
};

/// Runs paid NAI image actions on behalf of one widget.
///
/// Taps are ignored while an action is in flight: the source is read and
/// decoded before the loading dialog appears, so a quick double tap would
/// otherwise send two paid requests. The loading dialog cannot be dismissed
/// with the back button and is removed by this flow only, exactly once, so
/// no other route is ever popped in its place. Request failures are reported
/// here; whatever [run]'s `onResult` does next (review, save) reports its own
/// outcome.
class NovelAiImageActionFlow {
  bool _inFlight = false;

  bool get inFlight => _inFlight;

  Future<void> run(
    BuildContext context, {
    required NovelAiImageActionService service,
    required NovelAiImageAction action,
    required bool permissionGranted,
    required String apiKey,
    required Future<Uint8List> Function() readSource,
    required Future<void> Function(Uint8List source, Uint8List result) onResult,
  }) async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final l = context.l;
      final blocker = service.blocker(
        apiKey: apiKey,
        permissionGranted: permissionGranted,
      );
      if (blocker != null) {
        showErrorSnackBar(
          context,
          novelAiImageActionBlockerMessage(l, blocker),
        );
        return;
      }

      final Uint8List source;
      final Uint8List result;
      try {
        source = await readSource();
        if (!context.mounted) return;
        result = await _whileShowingProgress(context, switch (action) {
          NovelAiImageAction.upscale => l.naiUpscaling,
          NovelAiImageAction.backgroundRemoval => l.naiRemovingBackground,
        }, () => service.perform(action, source));
      } on NovelAiImageActionException catch (e) {
        if (context.mounted) {
          showErrorSnackBar(
            context,
            e.isTooLarge
                ? l.naiUpscaleTooLarge(e.width, e.height)
                : l.naiImageUnreadable,
          );
        }
        return;
      } catch (e) {
        debugPrint('NovelAiImageActionFlow: ${action.name} failed: $e');
        if (context.mounted) {
          showErrorSnackBar(context, switch (action) {
            NovelAiImageAction.upscale => l.naiUpscaleFailed,
            NovelAiImageAction.backgroundRemoval => l.naiBgRemovalFailed,
          });
        }
        return;
      }

      if (!context.mounted) return;
      await onResult(source, result);
    } finally {
      _inFlight = false;
    }
  }
}

Future<T> _whileShowingProgress<T>(
  BuildContext context,
  String label,
  Future<T> Function() task,
) async {
  final navigator = Navigator.of(context);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    builder: (_) =>
        PopScope(canPop: false, child: _ProgressDialog(label: label)),
  );
  unawaited(navigator.push(route));
  try {
    return await task();
  } finally {
    if (route.isActive) navigator.removeRoute(route);
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AlertDialog(
      backgroundColor: t.surfaceHigh,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            label,
            style: TextStyle(
              fontSize: t.fontSize(10),
              letterSpacing: 2,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
