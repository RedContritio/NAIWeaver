import 'package:flutter/material.dart';
import '../../../../core/jukebox/models/jukebox_soundfont.dart';
import '../../../../core/jukebox/jukebox_registry.dart';
import '../../../../core/jukebox/providers/jukebox_notifier.dart';
import '../../../../core/services/download_manager.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_metrics.dart';
import '../../../../core/theme/vision_tokens.dart';
import '../../../../core/widgets/ui/app_pill.dart';
import '../../../../core/widgets/confirm_dialog.dart';

/// SoundFont selection list with download / delete / progress UI.
class JukeboxSoundFontPicker extends StatelessWidget {
  final JukeboxNotifier jukebox;
  final VisionTokens t;

  const JukeboxSoundFontPicker({
    super.key,
    required this.jukebox,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: JukeboxRegistry.allSoundFonts.map((sf) {
        final selected = jukebox.activeSoundFont.id == sf.id;
        final available = jukebox.isSoundFontAvailable(sf);
        final dlState = jukebox.sfDownloadState(sf.id);
        final isDownloading = dlState.status == DownloadStatus.downloading;
        final isError = dlState.status == DownloadStatus.error;
        final isDownloaded = jukebox.isSoundFontAvailable(sf) && !sf.isBundled;

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: VisionMetrics.space12,
            vertical: VisionMetrics.space8,
          ),
          margin: const EdgeInsets.only(bottom: VisionMetrics.space4),
          decoration: BoxDecoration(
            color: selected
                ? t.accent.withValues(alpha: VisionMetrics.opacityHover)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(VisionMetrics.radius4),
            border: Border.all(
              color: selected ? t.accent : t.borderSubtle,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: available ? () => jukebox.setSoundFont(sf) : null,
                child: Row(
                  children: [
                    if (sf.isGag)
                      Padding(
                        padding: const EdgeInsets.only(
                          right: VisionMetrics.space8,
                        ),
                        child: Icon(
                          Icons.sentiment_very_satisfied,
                          size: 14,
                          color: t.accent,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sf.name.toUpperCase(),
                            style: TextStyle(
                              color: available
                                  ? (selected ? t.accent : t.textSecondary)
                                  : t.textDisabled,
                              fontSize: t.fontSize(9),
                              letterSpacing: 1,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          Text(
                            sf.description,
                            style: TextStyle(
                              color: t.textMinimal,
                              fontSize: t.fontSize(7),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status badges & actions
                    ..._buildTrailingActions(
                      context,
                      sf,
                      selected: selected,
                      isDownloading: isDownloading,
                      isError: isError,
                      isDownloaded: isDownloaded,
                    ),
                  ],
                ),
              ),
              // Progress bar during download
              if (isDownloading) ...[
                const SizedBox(height: VisionMetrics.space8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          VisionMetrics.radius2,
                        ),
                        child: LinearProgressIndicator(
                          value: dlState.progress,
                          backgroundColor: t.borderSubtle,
                          valueColor: AlwaysStoppedAnimation<Color>(t.accent),
                          minHeight: 3,
                        ),
                      ),
                    ),
                    const SizedBox(width: VisionMetrics.space8),
                    Text(
                      '${(dlState.progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: t.textMinimal,
                        fontSize: t.fontSize(7),
                      ),
                    ),
                  ],
                ),
              ],
              // Error message
              if (isError && dlState.errorMessage != null) ...[
                const SizedBox(height: VisionMetrics.space4),
                Text(
                  dlState.errorMessage!,
                  style: TextStyle(
                    color: t.accentDanger,
                    fontSize: t.fontSize(7),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  List<Widget> _buildTrailingActions(
    BuildContext context,
    JukeboxSoundFont sf, {
    required bool selected,
    required bool isDownloading,
    required bool isError,
    required bool isDownloaded,
  }) {
    if (sf.isBundled && !sf.isDownloadable) {
      return [
        AppPill(text: context.l.jukeboxBundled, dense: true),
        if (selected)
          Padding(
            padding: const EdgeInsets.only(left: VisionMetrics.space8),
            child: Icon(Icons.check, size: 14, color: t.accent),
          ),
      ];
    }

    if (isDownloading) {
      return [
        _actionButton(
          context,
          context.l.commonCancel.toUpperCase(),
          () => jukebox.cancelSoundFontDownload(sf.id),
        ),
      ];
    }

    if (isError) {
      return [
        _actionButton(
          context,
          context.l.commonRetry.toUpperCase(),
          () => jukebox.downloadSoundFont(sf),
        ),
      ];
    }

    if (isDownloaded) {
      return [
        if (selected)
          Padding(
            padding: const EdgeInsets.only(left: VisionMetrics.space4),
            child: Icon(Icons.check, size: 14, color: t.accent),
          ),
        IconButton(
          icon: Icon(Icons.delete_outline, size: 14, color: t.textMinimal),
          onPressed: () => _confirmDeleteSoundFont(context, sf),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(VisionMetrics.space4),
          tooltip: context.l.jukeboxSoundfontDelete,
        ),
      ];
    }

    // Not downloaded -- show download button
    return [
      Text(
        sf.fileSizeLabel,
        style: TextStyle(color: t.textMinimal, fontSize: t.fontSize(7)),
      ),
      const SizedBox(width: VisionMetrics.space8),
      _actionButton(
        context,
        context.l.jukeboxSoundfontDownload,
        () => jukebox.downloadSoundFont(sf),
      ),
      if (selected && sf.isBundled)
        Padding(
          padding: const EdgeInsets.only(left: VisionMetrics.space8),
          child: Icon(Icons.check, size: 14, color: t.accent),
        ),
    ];
  }

  /// A text action with a full-size hit area.
  Widget _actionButton(BuildContext context, String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: Size(0, context.hitSize),
        padding: const EdgeInsets.symmetric(horizontal: VisionMetrics.space8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: t.accent,
          fontSize: t.fontSize(8),
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSoundFont(
    BuildContext context,
    JukeboxSoundFont sf,
  ) async {
    final confirm = await showConfirmDialog(
      context,
      title: context.l.jukeboxSoundfontDeleteTitle,
      message: context.l.jukeboxSoundfontDeleteMessage(sf.name),
      confirmLabel: context.l.commonDelete.toUpperCase(),
      cancelLabel: context.l.commonCancel,
      confirmColor: t.accentDanger,
    );
    if (confirm == true) {
      jukebox.deleteSoundFont(sf);
    }
  }
}
