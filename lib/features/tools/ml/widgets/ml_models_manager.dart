import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../../../core/ml/ml_device_capabilities.dart';
import '../../../../core/ml/ml_model_entry.dart';
import '../../../../core/ml/ml_model_registry.dart';
import '../../../../core/ml/ml_notifier.dart';
import '../../../../core/services/download_manager.dart';
import '../../../../core/ml/ml_storage_service.dart';
import '../../../../core/services/preferences_service.dart';
import '../../../../core/theme/theme_extensions.dart';
import '../../../../core/theme/vision_metrics.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/l10n/l10n_extensions.dart';
import '../../../../core/widgets/ui/app_pill.dart';
import '../../../../core/widgets/ui/app_tone.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../generation/providers/generation_notifier.dart';

bool get _hasLocalMlPlatform =>
    kIsWeb || (!Platform.isAndroid && !Platform.isIOS);

class MLModelsManager extends StatefulWidget {
  const MLModelsManager({super.key});

  @override
  State<MLModelsManager> createState() => _MLModelsManagerState();
}

class _MLModelsManagerState extends State<MLModelsManager> {
  MLStorageStats? _stats;
  List<_UnknownModel>? _unknownModels;

  @override
  void initState() {
    super.initState();
    _refreshStats();
    _scanUnknownModels();
  }

  Future<void> _refreshStats() async {
    final ml = context.read<MLNotifier>();
    final stats = await MLStorageService.getStats(ml.mlModelsDir);
    if (mounted) setState(() => _stats = stats);
  }

  Future<void> _scanUnknownModels() async {
    final ml = context.read<MLNotifier>();
    final dir = Directory(ml.mlModelsDir);
    if (!await dir.exists()) return;

    final knownFiles = MLModelRegistry.all.map((e) => e.filename).toSet();
    final unknown = <_UnknownModel>[];

    await for (final entity in dir.list()) {
      if (entity is File &&
          (entity.path.endsWith('.onnx') || entity.path.endsWith('.ort'))) {
        final filename = p.basename(entity.path);
        if (!knownFiles.contains(filename)) {
          final stat = await entity.stat();
          unknown.add(
            _UnknownModel(
              path: entity.path,
              filename: filename,
              sizeBytes: stat.size,
            ),
          );
        }
      }
    }

    if (mounted) setState(() => _unknownModels = unknown);
  }

  Future<void> _deleteUnknown(_UnknownModel model) async {
    final l = context.l;
    final confirm = await showConfirmDialog(
      context,
      title: l.mlDeleteModelTitle(model.filename),
      message: l.mlDeleteModelMessage(model.sizeLabel),
      confirmLabel: l.mlDelete,
      cancelLabel: l.commonCancel,
    );
    if (confirm != true) return;
    try {
      await File(model.path).delete();
      _unknownModels?.remove(model);
      if (mounted) setState(() {});
      _refreshStats();
    } catch (e) {
      debugPrint('Failed to delete unknown model: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final touch = isTouchSized(context);
    final ml = context.watch<MLNotifier>();
    final prefs = context.watch<PreferencesService>();
    final hasApiKey = context
        .watch<GenerationNotifier>()
        .state
        .apiKey
        .isNotEmpty;
    final caps = ml.deviceCapabilities;
    final noteSize = t.fontSize(touch ? 10 : 8);

    Widget gap(double h) => SizedBox(height: h);

    Widget modelCard(
      MLModelEntry entry, {
      required bool isSelected,
      required VoidCallback onSelect,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: VisionMetrics.space8),
        child: _MLModelCard(
          entry: entry,
          ml: ml,
          caps: caps,
          isSelected: isSelected,
          onSelect: onSelect,
          onDownload: () async {
            await ml.downloadModel(entry);
            _refreshStats();
          },
          onCancel: () => ml.cancelDownload(entry.id),
          onDelete: () => _confirmDelete(entry, ml),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(
        touch ? VisionMetrics.space16 : VisionMetrics.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            l.mlModels.toUpperCase(),
            style: TextStyle(
              color: t.headerText,
              fontSize: t.fontSize(touch ? 14 : 12),
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
            ),
          ),
          gap(VisionMetrics.space4),
          Text(
            l.mlManagerSubtitle,
            style: TextStyle(
              color: t.textDisabled,
              fontSize: t.fontSize(touch ? 11 : 9),
              letterSpacing: 0.5,
            ),
          ),
          gap(VisionMetrics.space16),

          // Device info + stats row
          if (caps != null)
            _InfoRow(
              icon: caps.hasGpuAcceleration ? Icons.memory : Icons.computer,
              iconColor: caps.hasGpuAcceleration
                  ? t.accentSuccess
                  : t.accentEdit,
              text: caps.deviceInfoLabel,
            ),
          if (caps != null && _stats != null) gap(VisionMetrics.space8),
          if (_stats != null)
            _InfoRow(
              icon: Icons.storage,
              iconColor: t.textDisabled,
              text: _stats!.downloadedCount == 0
                  ? l.mlNoModelsDownloaded
                  : l.mlModelsDownloaded(
                      _stats!.downloadedCount,
                      _stats!.diskUsageLabel,
                    ),
            ),
          gap(VisionMetrics.space24),

          // Mobile-only banner: local ML not available
          if (!_hasLocalMlPlatform) ...[
            _InfoRow(
              icon: Icons.phone_android,
              iconColor: t.accentEdit,
              text: l.mlMobileApiNote,
              tone: AppTone.info,
            ),
            gap(VisionMetrics.space16),
          ],

          // Background Removal section
          _SectionHeader(title: l.mlBgRemoval, icon: Icons.content_cut),
          gap(VisionMetrics.space8),
          _NaiBackendCard(
            title: l.mlNaiApiBgRemoval,
            description: l.mlNaiApiBgRemovalDesc,
            isSelected: prefs.bgRemovalBackend == 'novelai',
            hasApiKey: hasApiKey,
            onSelect: () async {
              await prefs.setBgRemovalBackend('novelai');
              if (mounted) setState(() {});
            },
          ),
          if (_hasLocalMlPlatform) ...[
            gap(VisionMetrics.space8),
            ...MLModelRegistry.backgroundRemovalModels.map(
              (entry) => modelCard(
                entry,
                isSelected:
                    ml.selectedBgRemovalModelId == entry.id &&
                    prefs.bgRemovalBackend == 'ml',
                onSelect: () async {
                  ml.selectBgRemovalModel(entry.id);
                  await prefs.setBgRemovalBackend('ml');
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],

          gap(VisionMetrics.space24),

          // Upscaling section
          _SectionHeader(title: l.mlUpscaling, icon: Icons.zoom_out_map),
          gap(VisionMetrics.space8),
          _NaiBackendCard(
            title: l.mlNaiApiUpscale,
            description: l.mlNaiApiUpscaleDesc,
            isSelected: prefs.upscaleBackend == 'novelai',
            hasApiKey: hasApiKey,
            onSelect: () async {
              await prefs.setUpscaleBackend('novelai');
              if (mounted) setState(() {});
            },
          ),
          if (_hasLocalMlPlatform) ...[
            gap(VisionMetrics.space8),
            ...MLModelRegistry.upscaleModels.map(
              (entry) => modelCard(
                entry,
                isSelected:
                    ml.selectedUpscaleModelId == entry.id &&
                    prefs.upscaleBackend == 'ml',
                onSelect: () async {
                  ml.selectUpscaleModel(entry.id);
                  await prefs.setUpscaleBackend('ml');
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],

          gap(VisionMetrics.space24),

          // Segmentation section (desktop only)
          if (_hasLocalMlPlatform) ...[
            _SectionHeader(title: l.mlSegmentation, icon: Icons.auto_awesome),
            gap(VisionMetrics.space4),
            Text(
              l.mlSegmentationNote,
              style: TextStyle(
                color: t.textMinimal,
                fontSize: noteSize,
                letterSpacing: 0.5,
              ),
            ),
            gap(VisionMetrics.space8),
            ...MLModelRegistry.segmentationModels.map(
              (entry) => modelCard(
                entry,
                isSelected: entry.id.contains('encoder')
                    ? ml.selectedSegmentationModelId == entry.id
                    : ml.selectedSegmentationModelId != null,
                onSelect: entry.id.contains('encoder')
                    ? () => ml.selectSegmentationModel(entry.id)
                    : () {}, // decoder follows encoder
              ),
            ),
          ],

          // Unknown models section
          if (_unknownModels != null && _unknownModels!.isNotEmpty) ...[
            gap(VisionMetrics.space24),
            _SectionHeader(title: l.mlUnknownModels, icon: Icons.help_outline),
            gap(VisionMetrics.space4),
            Text(
              l.mlUnknownModelsNote,
              style: TextStyle(
                color: t.textMinimal,
                fontSize: noteSize,
                letterSpacing: 0.5,
              ),
            ),
            gap(VisionMetrics.space8),
            ..._unknownModels!.map(
              (model) => Padding(
                padding: const EdgeInsets.only(bottom: VisionMetrics.space8),
                child: Container(
                  padding: EdgeInsets.all(
                    touch ? VisionMetrics.space12 : VisionMetrics.space8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                    border: Border.all(color: t.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              model.filename.toUpperCase(),
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: t.fontSize(touch ? 11 : 9),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            gap(VisionMetrics.radius2),
                            Text(
                              model.sizeLabel,
                              style: TextStyle(
                                color: t.textDisabled,
                                fontSize: noteSize,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _deleteUnknown(model),
                        child: Text(
                          l.mlDelete,
                          style: TextStyle(
                            color: t.accentDanger,
                            fontSize: noteSize,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          gap(VisionMetrics.space24 + VisionMetrics.space16),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(MLModelEntry entry, MLNotifier ml) async {
    final l = context.l;
    final confirm = await showConfirmDialog(
      context,
      title: l.mlDeleteModelTitle(entry.name),
      message: l.mlDeleteModelMessage(entry.fileSizeLabel),
      confirmLabel: l.mlDelete,
      cancelLabel: l.commonCancel,
    );
    if (confirm == true) {
      await ml.deleteModel(entry);
      _refreshStats();
      _scanUnknownModels();
    }
  }
}

class _UnknownModel {
  final String path;
  final String filename;
  final int sizeBytes;

  _UnknownModel({
    required this.path,
    required this.filename,
    required this.sizeBytes,
  });

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$sizeBytes B';
  }
}

/// A one-line info strip: icon plus text on a tinted block.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final AppTone tone;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.text,
    this.tone = AppTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final touch = isTouchSized(context);
    final accent = tone == AppTone.neutral ? null : tone.color(t);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: touch ? VisionMetrics.space12 : VisionMetrics.space8,
        vertical: touch ? VisionMetrics.space8 : VisionMetrics.space4,
      ),
      decoration: BoxDecoration(
        color: accent == null
            ? t.borderSubtle
            : accent.withValues(alpha: VisionMetrics.opacityHover),
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        border: accent == null
            ? null
            : Border.all(
                color: accent.withValues(alpha: VisionMetrics.opacityScrim),
              ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: touch ? VisionMetrics.iconMedium : VisionMetrics.iconSmall,
            color: iconColor,
          ),
          const SizedBox(width: VisionMetrics.space8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: accent ?? t.textSecondary,
                fontSize: t.fontSize(touch ? 11 : 9),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final touch = isTouchSized(context);
    return Row(
      children: [
        Icon(
          icon,
          size: touch ? VisionMetrics.iconMedium : VisionMetrics.iconSmall,
          color: t.accent,
        ),
        const SizedBox(width: VisionMetrics.space8),
        Text(
          title,
          style: TextStyle(
            color: t.accent,
            fontSize: t.fontSize(touch ? 11 : 9),
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

/// Round selection indicator shared by every backend/model card.
class _RadioDot extends StatelessWidget {
  final bool isSelected;

  const _RadioDot({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final size = isTouchSized(context)
        ? VisionMetrics.iconMedium
        : VisionMetrics.iconSmall;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? t.accent : t.borderMedium,
          width: 2,
        ),
        color: isSelected ? t.accent : null,
      ),
      child: isSelected
          ? Icon(Icons.check, size: size - 8, color: t.background)
          : null,
    );
  }
}

class _MLModelCard extends StatelessWidget {
  final MLModelEntry entry;
  final MLNotifier ml;
  final MLDeviceCapabilities? caps;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  const _MLModelCard({
    required this.entry,
    required this.ml,
    required this.caps,
    required this.isSelected,
    required this.onSelect,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
  });

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

  /// The device-fit hint and whether it is a warning; null when not relevant.
  (String, bool)? _tierMatch(AppLocalizations l, MLDeviceCapabilities? caps) {
    if (caps == null) return null;
    final recommended = caps.recommendedTier;
    if (entry.deviceTier == MLDeviceTier.both) return null;
    if (entry.deviceTier == recommended) {
      return (l.mlRecommendedForDevice, false);
    }
    if (entry.deviceTier == MLDeviceTier.desktop &&
        recommended == MLDeviceTier.mobile) {
      return (l.mlSlowOnDevice, true);
    }
    return null;
  }

  AppTone _tierTone() => switch (entry.tier) {
    MLPerformanceTier.fast => AppTone.success,
    MLPerformanceTier.balanced => AppTone.info,
    MLPerformanceTier.quality => AppTone.warning,
  };

  String _tierLabel(AppLocalizations l) => switch (entry.tier) {
    MLPerformanceTier.fast => l.mlTierFast,
    MLPerformanceTier.balanced => l.mlTierBalancedShort,
    MLPerformanceTier.quality => l.mlTierQualityShort,
  };

  AppTone _deviceTone() => switch (entry.deviceTier) {
    MLDeviceTier.mobile => AppTone.success,
    MLDeviceTier.desktop => AppTone.warning,
    MLDeviceTier.both => AppTone.info,
  };

  String _deviceLabel(AppLocalizations l) => switch (entry.deviceTier) {
    MLDeviceTier.mobile => l.mlDeviceMobile,
    MLDeviceTier.desktop => l.mlDeviceDesktop,
    MLDeviceTier.both => l.mlDeviceBoth,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final touch = isTouchSized(context);
    final state = ml.downloadState(entry.id);
    final isDownloaded = ml.isModelDownloaded(entry.id);
    final isDownloading = state.status == DownloadStatus.downloading;
    final hasError = state.status == DownloadStatus.error;

    final rec = caps?.recommendation(entry);
    final isUnavailable = rec == MLRecommendationLevel.unavailable;
    final tierMatch = _tierMatch(l, caps);
    final smallText = t.fontSize(touch ? 10 : 8);
    final actionStyle = TextStyle(
      fontSize: smallText,
      fontWeight: FontWeight.bold,
      letterSpacing: 1,
    );

    Widget deleteButton() => IconButton(
      onPressed: onDelete,
      tooltip: l.mlDelete,
      icon: Icon(
        Icons.delete_outline,
        size: touch ? VisionMetrics.iconMedium : VisionMetrics.iconSmall,
        color: t.textDisabled,
      ),
    );

    return Opacity(
      opacity: isUnavailable ? VisionMetrics.opacityDisabled : 1.0,
      child: InkWell(
        onTap: isUnavailable ? null : (isDownloaded ? onSelect : null),
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        child: Container(
          padding: EdgeInsets.all(
            touch ? VisionMetrics.space12 : VisionMetrics.space8,
          ),
          decoration: BoxDecoration(
            color: isDownloaded ? t.borderSubtle : null,
            borderRadius: BorderRadius.circular(VisionMetrics.radius4),
            border: Border.all(
              color: isSelected
                  ? t.accent
                  : (isDownloaded ? t.borderMedium : t.borderSubtle),
              width: isSelected ? 2 : VisionMetrics.borderWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isDownloaded) ...[
                    _RadioDot(isSelected: isSelected),
                    const SizedBox(width: VisionMetrics.space8),
                  ],

                  // Model info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: VisionMetrics.space4,
                          runSpacing: VisionMetrics.space4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              entry.name.toUpperCase(),
                              style: TextStyle(
                                color: isDownloaded
                                    ? t.textPrimary
                                    : t.textSecondary,
                                fontSize: t.fontSize(touch ? 12 : 10),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                            AppPill(
                              text: _tierLabel(l),
                              tone: _tierTone(),
                              dense: true,
                            ),
                            AppPill(
                              text: _deviceLabel(l),
                              tone: _deviceTone(),
                              dense: true,
                            ),
                            if (rec != null)
                              AppPill(
                                text: _recommendationLabel(
                                  l,
                                  rec,
                                  caps!,
                                  entry,
                                ),
                                tone: _recommendationTone(rec),
                                dense: true,
                              ),
                          ],
                        ),
                        const SizedBox(height: VisionMetrics.radius2),
                        Text(
                          '${entry.description} · ${entry.fileSizeLabel}',
                          style: TextStyle(
                            color: t.textDisabled,
                            fontSize: smallText,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (tierMatch != null) ...[
                          const SizedBox(height: VisionMetrics.radius2),
                          Text(
                            tierMatch.$1,
                            style: TextStyle(
                              color: tierMatch.$2
                                  ? t.accentFavorite
                                  : t.accentSuccess,
                              fontSize: t.fontSize(touch ? 9 : 8),
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Action buttons
                  if (isUnavailable)
                    if (isDownloaded)
                      deleteButton()
                    else
                      const SizedBox.shrink()
                  else if (isDownloading)
                    TextButton(
                      onPressed: onCancel,
                      child: Text(
                        l.mlCancel,
                        style: actionStyle.copyWith(color: t.accentDanger),
                      ),
                    )
                  else if (isDownloaded)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check,
                          size: VisionMetrics.iconSmall,
                          color: t.accentSuccess,
                        ),
                        const SizedBox(width: VisionMetrics.space4),
                        Text(
                          l.mlDownloaded,
                          style: actionStyle.copyWith(
                            color: t.accentSuccess,
                            fontSize: t.fontSize(touch ? 9 : 8),
                          ),
                        ),
                        deleteButton(),
                      ],
                    )
                  else
                    TextButton(
                      onPressed: onDownload,
                      child: Text(
                        hasError ? l.mlRetry : l.mlDownload,
                        style: actionStyle.copyWith(color: t.accent),
                      ),
                    ),
                ],
              ),

              // Download progress bar
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
                          value: state.progress,
                          backgroundColor: t.borderSubtle,
                          color: t.accent,
                          minHeight: 3,
                        ),
                      ),
                    ),
                    const SizedBox(width: VisionMetrics.space8),
                    Text(
                      '${(state.progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: t.textDisabled,
                        fontSize: smallText,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],

              // Error message
              if (hasError && state.errorMessage != null) ...[
                const SizedBox(height: VisionMetrics.space8),
                Text(
                  state.errorMessage!.toUpperCase(),
                  style: TextStyle(
                    color: t.accentDanger,
                    fontSize: t.fontSize(touch ? 9 : 8),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A NovelAI cloud backend (upscale or background removal) shown beside the
/// local models.
class _NaiBackendCard extends StatelessWidget {
  final String title;
  final String description;
  final bool isSelected;
  final bool hasApiKey;
  final VoidCallback onSelect;

  const _NaiBackendCard({
    required this.title,
    required this.description,
    required this.isSelected,
    required this.hasApiKey,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final touch = isTouchSized(context);
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(VisionMetrics.radius4),
      child: Container(
        padding: EdgeInsets.all(
          touch ? VisionMetrics.space12 : VisionMetrics.space8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? t.borderSubtle : null,
          borderRadius: BorderRadius.circular(VisionMetrics.radius4),
          border: Border.all(
            color: isSelected ? t.accent : t.borderSubtle,
            width: isSelected ? 2 : VisionMetrics.borderWidth,
          ),
        ),
        child: Row(
          children: [
            _RadioDot(isSelected: isSelected),
            const SizedBox(width: VisionMetrics.space8),
            Icon(
              Icons.cloud_outlined,
              size: touch ? VisionMetrics.iconMedium : VisionMetrics.iconSmall,
              color: t.accentEdit,
            ),
            const SizedBox(width: VisionMetrics.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: VisionMetrics.space4,
                    runSpacing: VisionMetrics.space4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isSelected ? t.textPrimary : t.textSecondary,
                          fontSize: t.fontSize(touch ? 12 : 10),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      AppPill(
                        text: l.mlCloud,
                        tone: AppTone.warning,
                        dense: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: VisionMetrics.radius2),
                  Text(
                    description,
                    style: TextStyle(
                      color: t.textDisabled,
                      fontSize: t.fontSize(touch ? 10 : 8),
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (!hasApiKey) ...[
                    const SizedBox(height: VisionMetrics.radius2),
                    Text(
                      l.mlNoApiKey,
                      style: TextStyle(
                        color: t.accentDanger,
                        fontSize: t.fontSize(touch ? 9 : 8),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
