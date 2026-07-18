import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../l10n/l10n_extensions.dart';
import '../l10n/locale_notifier.dart';
import '../services/update_download_service.dart';
import '../services/update_service.dart';
import '../theme/theme_extensions.dart';
import '../theme/vision_tokens.dart';

/// Non-intrusive launch-time prompt: a SnackBar offering to update now or skip.
/// Falls back to the manual flow (download dialog) which itself falls back to
/// opening the release page if the platform can't auto-apply.
void showUpdatePrompt(BuildContext context, UpdateCheckResult result) {
  final l = context.l;
  final t = context.tRead;
  final version = result.latestVersion;
  if (version == null) return;

  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(
      l.settingsUpdateAvailableDesc(version),
      style: TextStyle(color: t.accent, fontSize: t.fontSize(11)),
    ),
    backgroundColor: const Color(0xFF0A1A0A),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(color: t.accent.withValues(alpha: 0.3)),
    ),
    action: SnackBarAction(
      label: (UpdateDownloadService.isSupported
              ? l.settingsUpdateDownload
              : l.settingsUpdateOpenInBrowser)
          .toUpperCase(),
      textColor: t.accent,
      onPressed: () => startUpdate(context, result),
    ),
  ));
}

/// Entry point shared by the launch prompt and the settings button. Picks the
/// right asset for this platform + locale and shows the download dialog; if the
/// platform can't auto-apply or no asset matches, opens the release page.
Future<void> startUpdate(BuildContext context, UpdateCheckResult result) async {
  final suffix = UpdateDownloadService.platformAssetSuffix;
  final locale = context.read<LocaleNotifier>().locale.languageCode;
  final asset = suffix == null
      ? null
      : UpdateService.selectAsset(result.assets,
          platformSuffix: suffix, localeCode: locale);

  if (asset == null) {
    // Unsupported platform or no matching asset — open the release page.
    final url = result.releaseUrl;
    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDownloadDialog(asset: asset, result: result),
  );
}

class _UpdateDownloadDialog extends StatefulWidget {
  final UpdateAsset asset;
  final UpdateCheckResult result;
  const _UpdateDownloadDialog({required this.asset, required this.result});

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  final _service = UpdateDownloadService();
  final _cancelToken = CancelToken();

  UpdatePhase _phase = UpdatePhase.downloading;
  double? _fraction;
  int _received = 0;
  int _total = 0;
  String? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_started) return;
    _started = true;
    final l = context.l;
    try {
      final file = await _service.downloadAsset(
        widget.asset,
        cancelToken: _cancelToken,
        onProgress: (phase, frac, received, total) {
          if (!mounted) return;
          setState(() {
            _phase = phase;
            _fraction = frac;
            _received = received;
            _total = total;
          });
        },
      );
      if (!mounted) return;

      if (Platform.isAndroid) {
        setState(() => _phase = UpdatePhase.installing);
        await _service.installAndroidApk(file);
        // The OS installer is now in front; close the dialog.
        if (mounted) Navigator.of(context).pop();
      } else if (Platform.isWindows) {
        setState(() => _phase = UpdatePhase.installing);
        await _service.launchWindowsUpdater(file);
        // Close the app so the detached helper can swap files and relaunch.
        // window_manager intercepts close → persists state → destroy().
        await windowManager.close();
      } else {
        if (mounted) Navigator.of(context).pop();
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (CancelToken.isCancel(e)) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _phase = UpdatePhase.error;
        _error = l.settingsUpdateDownloadFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = UpdatePhase.error;
        _error = Platform.isAndroid
            ? l.settingsUpdateInstallFailed
            : l.settingsUpdateDownloadFailed;
      });
    }
  }

  void _cancel() {
    if (!_cancelToken.isCancelled) _cancelToken.cancel('user');
  }

  String _fmtBytes(int b) {
    if (b <= 0) return '0 MB';
    final mb = b / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  String _phaseLabel(AppLocalizations l) {
    switch (_phase) {
      case UpdatePhase.downloading:
        return l.settingsUpdateDownloading;
      case UpdatePhase.extracting:
      case UpdatePhase.installing:
      case UpdatePhase.done:
        return l.settingsUpdateInstalling;
      case UpdatePhase.error:
        return _error ?? l.settingsUpdateDownloadFailed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tRead;
    final l = context.l;
    final isError = _phase == UpdatePhase.error;
    final indeterminate = _fraction == null || _phase != UpdatePhase.downloading;

    return PopScope(
      canPop: isError,
      child: AlertDialog(
        backgroundColor: t.surfaceHigh,
        title: Text(
          l.settingsUpdateAvailable.toUpperCase(),
          style: TextStyle(
            fontSize: t.fontSize(10),
            letterSpacing: 2,
            color: t.textSecondary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _phaseLabel(l),
              style: TextStyle(
                color: isError ? t.accentDanger : t.textPrimary,
                fontSize: t.fontSize(11),
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: indeterminate ? null : _fraction,
              backgroundColor: t.borderMedium,
              valueColor: AlwaysStoppedAnimation<Color>(
                  isError ? t.accentDanger : t.accent),
            ),
            if (_phase == UpdatePhase.downloading && _total > 0) ...[
              const SizedBox(height: 8),
              Text(
                l.settingsUpdateProgress(_fmtBytes(_received), _fmtBytes(_total)),
                style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(10)),
              ),
            ],
            if (Platform.isWindows && !isError) ...[
              const SizedBox(height: 12),
              Text(
                l.settingsUpdateRestartPrompt,
                style: TextStyle(color: t.textSecondary, fontSize: t.fontSize(10)),
              ),
            ],
          ],
        ),
        actions: _buildActions(t, l, isError),
      ),
    );
  }

  List<Widget> _buildActions(VisionTokens t, AppLocalizations l, bool isError) {
    if (isError) {
      return [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            final url = widget.result.releaseUrl;
            if (url != null) {
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            }
          },
          child: Text(
            l.settingsUpdateOpenInBrowser.toUpperCase(),
            style: TextStyle(color: t.accent, fontSize: t.fontSize(9)),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            l.commonClose.toUpperCase(),
            style: TextStyle(color: t.textDisabled, fontSize: t.fontSize(9)),
          ),
        ),
      ];
    }
    // Downloading: allow Cancel. Once we hand off to the OS installer / Windows
    // helper there's nothing left to cancel, so disable it.
    final canCancel = _phase == UpdatePhase.downloading;
    return [
      TextButton(
        onPressed: canCancel
            ? () {
                _cancel();
                Navigator.of(context).pop();
              }
            : null,
        child: Text(
          l.commonCancel.toUpperCase(),
          style: TextStyle(
            color: canCancel ? t.textDisabled : t.borderMedium,
            fontSize: t.fontSize(9),
          ),
        ),
      ),
    ];
  }
}
