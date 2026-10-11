import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/ml/ml_device_capabilities.dart';
import '../../../../core/ml/ml_model_entry.dart';
import '../../../../core/ml/ml_model_registry.dart';
import '../../../../core/ml/ml_notifier.dart';
import '../../../../core/services/download_manager.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_metrics.dart';
import '../../../../core/widgets/ui/app_pill.dart';
import '../../../../core/widgets/ui/app_sheet.dart';
import '../../../../core/widgets/ui/app_tone.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/ml/ml_model_entry_l10n.dart';

/// Bottom sheet for picking an ML model of a given type.
/// Shows download status, tier badges, and device recommendations.
class MLModelPicker extends StatelessWidget {
  final MLModelType modelType;
  final String? selectedModelId;
  final ValueChanged<String?> onSelected;

  const MLModelPicker({
    super.key,
    required this.modelType,
    required this.selectedModelId,
    required this.onSelected,
  });

  /// Show the model picker as a bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required MLModelType modelType,
    required String? selectedModelId,
    required ValueChanged<String?> onSelected,
  }) {
    return showAppSheet<void>(
      context: context,
      draggable: true,
      initialSize: 0.5,
      maxSize: 0.8,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<MLNotifier>(),
        child: MLModelPicker(
          modelType: modelType,
          selectedModelId: selectedModelId,
          onSelected: onSelected,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ml = context.watch<MLNotifier>();
    final l = context.l;
    final caps = ml.deviceCapabilities;

    final models = MLModelRegistry.byType(modelType);

    final title = switch (modelType) {
      MLModelType.backgroundRemoval => l.mlBgRemoval,
      MLModelType.upscale => l.mlUpscaling,
      MLModelType.segmentation => l.mlSegmentation,
    };

    return AppPickerSheet(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (caps != null)
            Padding(
              padding: const EdgeInsets.only(bottom: VisionMetrics.space8),
              child: Align(
                alignment: Alignment.centerRight,
                child: AppPill(
                  text: caps.deviceInfoLabel(context.l),
                  tone: caps.hasGpuAcceleration
                      ? AppTone.success
                      : AppTone.warning,
                  dense: true,
                ),
              ),
            ),
          for (final entry in models) ...[_buildCard(context, ml, entry, caps)],
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    MLNotifier ml,
    MLModelEntry entry,
    MLDeviceCapabilities? caps,
  ) {
    final rec = caps?.recommendation(entry);
    final isUnavailable = rec == MLRecommendationLevel.unavailable;
    return _ModelPickerCard(
      entry: entry,
      isSelected: entry.id == selectedModelId,
      isDownloaded: ml.isModelDownloaded(entry.id),
      downloadState: ml.downloadState(entry.id),
      deviceCaps: caps,
      recommendation: rec,
      isUnavailable: isUnavailable,
      onTap: isUnavailable
          ? null
          : () {
              if (ml.isModelDownloaded(entry.id)) {
                onSelected(entry.id);
                Navigator.pop(context);
              } else {
                ml.downloadModel(entry);
              }
            },
      onDownload: isUnavailable ? null : () => ml.downloadModel(entry),
      onCancel: () => ml.cancelDownload(entry.id),
    );
  }
}

class _ModelPickerCard extends StatelessWidget {
  final MLModelEntry entry;
  final bool isSelected;
  final bool isDownloaded;
  final DownloadState downloadState;
  final MLDeviceCapabilities? deviceCaps;
  final MLRecommendationLevel? recommendation;
  final bool isUnavailable;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;
  final VoidCallback onCancel;

  const _ModelPickerCard({
    required this.entry,
    required this.isSelected,
    required this.isDownloaded,
    required this.downloadState,
    required this.deviceCaps,
    required this.recommendation,
    required this.isUnavailable,
    required this.onTap,
    required this.onDownload,
    required this.onCancel,
  });

  AppTone _tierTone(MLPerformanceTier tier) => switch (tier) {
    MLPerformanceTier.fast => AppTone.success,
    MLPerformanceTier.balanced => AppTone.info,
    MLPerformanceTier.quality => AppTone.warning,
  };

  String _tierLabel(AppLocalizations l, MLPerformanceTier tier) =>
      switch (tier) {
        MLPerformanceTier.fast => l.mlTierFast,
        MLPerformanceTier.balanced => l.mlTierBalanced,
        MLPerformanceTier.quality => l.mlTierQuality,
      };

  AppTone _recommendationTone(MLRecommendationLevel level) => switch (level) {
    MLRecommendationLevel.recommended => AppTone.success,
    MLRecommendationLevel.slow => AppTone.warning,
    MLRecommendationLevel.notRecommended => AppTone.error,
    MLRecommendationLevel.unavailable => AppTone.error,
  };

  String _recommendationLabel(
    AppLocalizations l,
    MLRecommendationLevel level,
    MLDeviceCapabilities caps,
    MLModelEntry entry,
  ) {
    if (level == MLRecommendationLevel.unavailable) {
      if (caps.isDesktopOnlyOnMobile(entry)) return l.mlDesktopOnlyMayCrash;
      return l.mlNotAvailableOnPlatform;
    }
    if (level == MLRecommendationLevel.notRecommended && caps.isLowRam(entry)) {
      return l.mlLowRamWarning;
    }
    return switch (level) {
      MLRecommendationLevel.recommended => l.mlRecommended,
      MLRecommendationLevel.slow => l.mlMayBeSlow,
      MLRecommendationLevel.notRecommended => l.mlNotRecommended,
      MLRecommendationLevel.unavailable => l.mlNotAvailableOnPlatform,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final isDownloading = downloadState.status == DownloadStatus.downloading;
    final hasError = downloadState.status == DownloadStatus.error;

    return Opacity(
      opacity: isUnavailable ? VisionMetrics.opacityDisabled : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VisionMetrics.space4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(VisionMetrics.radius8),
          child: Container(
            padding: const EdgeInsets.all(VisionMetrics.space12),
            decoration: BoxDecoration(
              color: isSelected
                  ? t.accentEdit.withValues(alpha: VisionMetrics.opacityPressed)
                  : null,
              borderRadius: BorderRadius.circular(VisionMetrics.radius8),
              border: Border.all(
                color: isSelected ? t.accentEdit : t.borderSubtle,
                width: isSelected ? 2 : VisionMetrics.borderWidth,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Selection indicator
                    if (isDownloaded)
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: VisionMetrics.iconMedium,
                        color: isSelected ? t.accentEdit : t.textMinimal,
                      )
                    else
                      const SizedBox(width: VisionMetrics.iconMedium),
                    const SizedBox(width: VisionMetrics.space8),
                    // Model name
                    Expanded(
                      child: Text(
                        entry.name,
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: t.fontSize(10),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    AppPill(
                      text: _tierLabel(l, entry.tier),
                      tone: _tierTone(entry.tier),
                      dense: true,
                    ),
                  ],
                ),
                const SizedBox(height: VisionMetrics.space4),
                // Description + size
                Padding(
                  padding: const EdgeInsets.only(left: VisionMetrics.space24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.localizedDescription(context.l),
                        style: TextStyle(
                          color: t.textTertiary,
                          fontSize: t.fontSize(9),
                        ),
                      ),
                      const SizedBox(height: VisionMetrics.space4),
                      Row(
                        children: [
                          Text(
                            entry.fileSizeLabel,
                            style: TextStyle(
                              color: t.textMinimal,
                              fontSize: t.fontSize(8),
                            ),
                          ),
                          if (recommendation != null) ...[
                            const SizedBox(width: VisionMetrics.space8),
                            Flexible(
                              child: Text(
                                _recommendationLabel(
                                  l,
                                  recommendation!,
                                  deviceCaps!,
                                  entry,
                                ),
                                style: TextStyle(
                                  color: _recommendationTone(
                                    recommendation!,
                                  ).color(t),
                                  fontSize: t.fontSize(8),
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      // Download progress
                      if (isDownloading)
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: downloadState.progress,
                                backgroundColor: t.borderSubtle,
                                valueColor: AlwaysStoppedAnimation(
                                  t.accentEdit,
                                ),
                              ),
                            ),
                            const SizedBox(width: VisionMetrics.space8),
                            Text(
                              '${(downloadState.progress * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                color: t.textMinimal,
                                fontSize: t.fontSize(8),
                              ),
                            ),
                            IconButton(
                              onPressed: onCancel,
                              tooltip: l.mlCancel,
                              icon: Icon(
                                Icons.close,
                                size: VisionMetrics.iconSmall,
                                color: t.textMinimal,
                              ),
                            ),
                          ],
                        ),
                      // Error
                      if (hasError)
                        Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: VisionMetrics.iconSmall,
                              color: t.accentDanger,
                            ),
                            const SizedBox(width: VisionMetrics.space4),
                            Expanded(
                              child: Text(
                                downloadState.issue?.label(l) ??
                                    l.mlDownloadFailed,
                                style: TextStyle(
                                  color: t.accentDanger,
                                  fontSize: t.fontSize(8),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: onDownload,
                              child: Text(l.mlRetry),
                            ),
                          ],
                        ),
                      // Download button (if not downloaded)
                      if (!isDownloaded &&
                          !isDownloading &&
                          !hasError &&
                          !isUnavailable)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: onDownload,
                            child: Text(l.mlDownload),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
