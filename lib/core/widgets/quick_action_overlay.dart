import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n_extensions.dart';
import '../gateway/backend_permissions.dart';
import '../ml/ml_notifier.dart';
import '../ml/widgets/upscale_comparison_view.dart';
import '../services/novel_ai_image_action_service.dart';
import '../services/preferences_service.dart';
import '../theme/theme_extensions.dart';
import '../theme/vision_tokens.dart';
import '../utils/app_snackbar.dart';
import '../utils/responsive.dart';
import '../utils/timestamp_utils.dart';
import '../../features/gallery/providers/gallery_notifier.dart';
import '../../features/gallery/services/tool_result_saver.dart';
import '../../features/gallery/ui/novel_ai_image_action_flow.dart';
import '../../features/generation/providers/generation_notifier.dart';
import '../../features/tools/enhance/providers/enhance_notifier.dart';
import '../../features/tools/director_tools/providers/director_tools_notifier.dart';
import '../../features/tools/img2img/providers/img2img_notifier.dart';
import '../../features/tools/tools_hub_screen.dart';

/// Quick action buttons (SAVE, EDIT, REMOVE BG, UPSCALE, ENHANCE, DIRECTOR TOOLS)
/// that float over the generated image preview on the main screen.
class QuickActionOverlay extends StatefulWidget {
  const QuickActionOverlay({super.key});

  @override
  State<QuickActionOverlay> createState() => _QuickActionOverlayState();
}

class _QuickActionOverlayState extends State<QuickActionOverlay> {
  final _naiFlow = NovelAiImageActionFlow();

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<GenerationNotifier>();
    final state = notifier.state;
    final mobile = isMobile(context);
    final t = context.t;
    final l = context.l;
    final ml = context.watch<MLNotifier>();
    final prefs = context.read<PreferencesService>();
    final upscaleBackend = prefs.upscaleBackend;
    final bgRemovalBackend = prefs.bgRemovalBackend;

    // Nothing to show when there is no image or generation is in progress.
    if (state.generatedImage == null || state.isLoading) {
      return const SizedBox.shrink();
    }

    final bool showSave = !state.autoSaveImages && !notifier.imageSaved;
    final bool showExport = prefs.showExportButton && !kIsWeb;
    final bool showCopy = prefs.showCopyButton && !kIsWeb;
    final gallery = context.watch<GalleryNotifier>();
    final bool showAlbum = gallery.albums.isNotEmpty;
    final bool paidImageFeaturesAllowed = canUsePaidImageFeatures(context);
    final bool imageAugmentAllowed = hasBackendPermission(
      context,
      BackendPermission.imageAugment,
    );
    final bool naiBgRemovalAllowed = hasNovelAiImageActionPermission(
      context,
      NovelAiImageAction.backgroundRemoval,
    );
    final bool naiUpscaleAllowed = hasNovelAiImageActionPermission(
      context,
      NovelAiImageAction.upscale,
    );

    final bool showEdit = state.showEditButton && paidImageFeaturesAllowed;
    final bool canUseBgRemovalBackend = bgRemovalBackend == 'novelai'
        ? naiBgRemovalAllowed
        : ml.hasBgRemovalModel;
    final bool showBgRemoval =
        state.showBgRemovalButton && canUseBgRemovalBackend;
    final bool canUseUpscaleBackend = upscaleBackend == 'novelai'
        ? naiUpscaleAllowed
        : ml.hasUpscaleModel;
    final bool showUpscale = state.showUpscaleButton && canUseUpscaleBackend;
    final bool showEnhance =
        state.showEnhanceButton && paidImageFeaturesAllowed;
    final bool showDirectorTools =
        state.showDirectorToolsButton && imageAugmentAllowed;
    // Tools that are charged by NovelAI say what they can cost at most.
    String withCap(String label, PaidTool tool, {bool paid = true}) {
      final cap = paid ? paidToolCapLabel(context, tool) : null;
      return cap == null ? label : '$label · $cap';
    }

    final actions = <Widget>[];
    void addAction(Widget action) {
      if (actions.isNotEmpty) actions.add(const SizedBox(height: 4));
      actions.add(action);
    }

    if (showSave) {
      addAction(
        _SaveButton(
          onTap: () => notifier.saveCurrentImage(),
          icon: Icons.save_alt,
          label: l.mainSave.toUpperCase(),
          color: t.accentSuccess,
          mobile: mobile,
        ),
      );
    }
    if (showExport) {
      addAction(
        _ActionButton(
          onTap: () => notifier.exportToDevice(context),
          icon: Icons.download,
          label: l.mainExport,
          color: t.accent,
          mobile: mobile,
        ),
      );
    }
    if (showCopy) {
      addAction(
        _ActionButton(
          onTap: () => notifier.copyToClipboard(context),
          icon: mobile ? Icons.share : Icons.copy,
          label: mobile ? 'SHARE' : 'COPY',
          color: t.accent,
          mobile: mobile,
        ),
      );
    }
    if (showAlbum) {
      addAction(
        _ActionButton(
          onTap: () => _showAlbumPicker(context, notifier, gallery, t),
          icon: Icons.photo_album_outlined,
          label: 'ALBUM',
          color: t.accent,
          mobile: mobile,
        ),
      );
    }
    if (showEdit) {
      addAction(
        _ActionButton(
          onTap: () {
            context.read<Img2ImgNotifier>().loadSourceImage(
              state.generatedImage!,
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    const ToolsHubScreen(initialToolId: 'img2img'),
              ),
            );
          },
          icon: Icons.brush,
          label: l.mainEdit,
          color: t.accentEdit,
          mobile: mobile,
        ),
      );
    }
    if (showBgRemoval) {
      addAction(
        _ActionButton(
          onTap: ml.isProcessing
              ? null
              : () {
                  final sourceBytes = state.generatedImage!;
                  if (bgRemovalBackend == 'novelai') {
                    _novelAiBgRemoval(
                      sourceBytes,
                      permissionGranted: naiBgRemovalAllowed,
                    );
                  } else {
                    _localBgRemoval(ml, sourceBytes);
                  }
                },
          icon: Icons.content_cut,
          label: withCap(
            l.mlRemoveBg,
            PaidTool.augment,
            paid: bgRemovalBackend == 'novelai',
          ),
          color: t.accentBgRemoval,
          isProcessing: ml.isProcessing,
          mobile: mobile,
        ),
      );
    }
    if (showUpscale) {
      addAction(
        _ActionButton(
          onTap: ml.isProcessing
              ? null
              : () {
                  final sourceBytes = state.generatedImage!;
                  if (upscaleBackend == 'novelai') {
                    _novelAiUpscale(
                      sourceBytes,
                      state.autoSaveImages,
                      permissionGranted: naiUpscaleAllowed,
                    );
                  } else {
                    _localUpscale(ml, sourceBytes, state.autoSaveImages);
                  }
                },
          icon: Icons.zoom_out_map,
          label: withCap(
            l.mlUpscale,
            PaidTool.upscale,
            paid: upscaleBackend == 'novelai',
          ),
          color: t.accentUpscale,
          isProcessing: ml.isProcessing,
          mobile: mobile,
        ),
      );
    }
    if (showEnhance) {
      addAction(
        _ActionButton(
          onTap: () {
            context.read<EnhanceNotifier>().setSourceImage(
              state.generatedImage!,
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ToolsHubScreen(initialToolId: 'enhance'),
              ),
            );
          },
          icon: Icons.hd,
          label: l.quickActionEnhance,
          color: t.accent,
          mobile: mobile,
        ),
      );
    }
    if (showDirectorTools) {
      addAction(
        _ActionButton(
          onTap: () {
            context.read<DirectorToolsNotifier>().setSourceImage(
              state.generatedImage!,
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ToolsHubScreen(initialToolId: 'director_tools'),
              ),
            );
          },
          icon: Icons.auto_fix_high,
          label: withCap(l.quickActionDirectorTools, PaidTool.augment),
          color: t.accent,
          mobile: mobile,
        ),
      );
    }
    if (actions.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (constraints.maxHeight - 24)
                  .clamp(0.0, double.infinity)
                  .toDouble(),
            ),
            child: DecoratedBox(
              key: const ValueKey<String>('quick-action-rail'),
              decoration: BoxDecoration(
                color: t.background.withValues(alpha: 0.78),
                border: Border.all(color: t.borderSubtle),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: actions,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  NovelAiImageActionService _naiActions() => NovelAiImageActionService(
    context.read<GenerationNotifier>().service,
    saver: ToolResultSaver.of(context),
  );

  Future<void> _localBgRemoval(MLNotifier ml, Uint8List sourceBytes) async {
    final result = await ml.removeBackground(sourceBytes);
    if (result == null || !mounted) return;
    await saveToolResult(
      context,
      bytes: result,
      fileName: 'BG_gen_${generateTimestamp()}.png',
      sourceBytes: sourceBytes,
      savedMessage: context.l.mlBgRemovedAndSaved,
    );
  }

  Future<void> _novelAiBgRemoval(
    Uint8List sourceBytes, {
    required bool permissionGranted,
  }) {
    final service = _naiActions();
    return _naiFlow.run(
      context,
      service: service,
      action: NovelAiImageAction.backgroundRemoval,
      permissionGranted: permissionGranted,
      apiKey: context.read<GenerationNotifier>().state.apiKey,
      readSource: () async => sourceBytes,
      onResult: (source, result) async {
        final outcome = await service.save(
          result,
          service.outputFileName(NovelAiImageAction.backgroundRemoval, 'gen'),
          sourceBytes: source,
        );
        if (!mounted) return;
        showToolResultSaveFeedback(
          context,
          outcome,
          savedMessage: context.l.mlBgRemovedAndSaved,
        );
      },
    );
  }

  Future<void> _localUpscale(
    MLNotifier ml,
    Uint8List sourceBytes,
    bool autoSave,
  ) async {
    final result = await ml.upscaleImage(sourceBytes);
    if (result == null || !mounted) return;
    final saver = ToolResultSaver.of(context);
    final outputName = 'UP_gen_${generateTimestamp()}.png';
    await _showUpscaleComparison(
      sourceBytes,
      result,
      outputName,
      autoSave,
      () => saver.save(result, outputName, sourceBytes: sourceBytes),
    );
  }

  Future<void> _novelAiUpscale(
    Uint8List sourceBytes,
    bool autoSave, {
    required bool permissionGranted,
  }) {
    final service = _naiActions();
    return _naiFlow.run(
      context,
      service: service,
      action: NovelAiImageAction.upscale,
      permissionGranted: permissionGranted,
      apiKey: context.read<GenerationNotifier>().state.apiKey,
      readSource: () async => sourceBytes,
      onResult: (source, result) {
        final outputName = service.outputFileName(
          NovelAiImageAction.upscale,
          'gen',
        );
        return _showUpscaleComparison(
          source,
          result,
          outputName,
          autoSave,
          () => service.save(result, outputName, sourceBytes: source),
        );
      },
    );
  }

  Future<void> _showUpscaleComparison(
    Uint8List sourceBytes,
    Uint8List result,
    String outputName,
    bool autoSave,
    Future<ToolResultSaveOutcome> Function() save,
  ) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => UpscaleComparisonView(
          originalBytes: sourceBytes,
          upscaledBytes: result,
          outputName: outputName,
          autoSave: autoSave,
          onSave: () async {
            final outcome = await save();
            if (!outcome.succeeded && mounted) {
              showToolResultSaveFeedback(context, outcome);
            }
            return outcome.succeeded;
          },
        ),
      ),
    );
  }
}

void _showAlbumPicker(
  BuildContext context,
  GenerationNotifier notifier,
  GalleryNotifier gallery,
  VisionTokens t,
) async {
  final basename = await notifier.ensureSavedAndGetBasename();
  if (basename == null || !context.mounted) return;

  showModalBottomSheet(
    context: context,
    backgroundColor: t.surfaceHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: t.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'ADD TO ALBUM',
              style: TextStyle(
                fontSize: t.fontSize(10),
                letterSpacing: 2,
                fontWeight: FontWeight.w900,
                color: t.textSecondary,
              ),
            ),
          ),
          for (final album in gallery.albums)
            ListTile(
              leading: Icon(
                Icons.photo_album,
                size: 18,
                color: album.imageBasenames.contains(basename)
                    ? t.accentSuccess
                    : t.textDisabled,
              ),
              title: Text(
                album.name,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: t.fontSize(12),
                ),
              ),
              trailing: album.imageBasenames.contains(basename)
                  ? Icon(Icons.check, size: 16, color: t.accentSuccess)
                  : null,
              onTap: () {
                gallery.addToAlbumByBasename(album.id, basename);
                Navigator.pop(context);
                showAppSnackBar(
                  context,
                  'ADDED TO ${album.name.toUpperCase()}',
                );
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// SAVE button — keeps text+icon style (different category from tool launchers).
class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.color,
    required this.mobile,
  });

  final VoidCallback? onTap;
  final IconData icon;
  final String label;
  final Color color;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: mobile ? 14 : 10,
            vertical: mobile ? 10 : 6,
          ),
          decoration: BoxDecoration(
            color: t.background.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: mobile ? 16 : 12, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: t.fontSize(mobile ? 12 : 9),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact icon-only quick-action button with tooltip.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.color,
    required this.mobile,
    this.isProcessing = false,
  });

  final VoidCallback? onTap;
  final IconData icon;
  final String label;
  final Color color;
  final bool mobile;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final size = mobile ? 36.0 : 28.0;
    final iconSize = mobile ? 18.0 : 14.0;
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: isProcessing
                  ? SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    )
                  : Icon(icon, size: iconSize, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
