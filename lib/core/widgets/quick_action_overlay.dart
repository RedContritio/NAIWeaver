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
import '../theme/vision_metrics.dart';
import '../utils/app_snackbar.dart';
import '../utils/responsive.dart';
import '../utils/timestamp_utils.dart';
import 'ui/app_sheet.dart';
import 'ui/overlay_action_button.dart';
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
    final touch = windowSizeClassOf(context).isTouchSized;
    final l = context.l;
    final ml = context.watch<MLNotifier>();
    final prefs = context.read<PreferencesService>();
    final upscaleBackend = prefs.upscaleBackend;
    final bgRemovalBackend = prefs.bgRemovalBackend;

    // Nothing to show when there is no image or generation is in progress.
    if (state.generatedImage == null || state.isLoading) {
      return const SizedBox.shrink();
    }

    final t = context.t;
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
        ? isNovelAiImageActionOffered(
            context,
            NovelAiImageAction.backgroundRemoval,
          )
        : ml.hasBgRemovalModel;
    final bool showBgRemoval =
        state.showBgRemovalButton && canUseBgRemovalBackend;
    final bool canUseUpscaleBackend = upscaleBackend == 'novelai'
        ? isNovelAiImageActionOffered(context, NovelAiImageAction.upscale)
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
    void addAction({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
      Color? color,
    }) {
      actions.add(
        OverlayActionButton(
          icon: icon,
          tooltip: tooltip,
          onPressed: onPressed,
          color: color,
        ),
      );
    }

    void openTool(String toolId) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ToolsHubScreen(initialToolId: toolId)),
    );

    if (showSave) {
      addAction(
        icon: Icons.save_alt,
        tooltip: l.mainSave,
        color: t.accentSuccess,
        onPressed: () => notifier.saveCurrentImage(),
      );
    }
    if (showExport) {
      addAction(
        icon: Icons.download,
        tooltip: l.mainExport,
        color: t.accent,
        onPressed: () => notifier.exportToDevice(context),
      );
    }
    if (showCopy) {
      addAction(
        icon: touch ? Icons.share : Icons.copy,
        tooltip: touch ? l.galleryShare : l.galleryCopy,
        color: t.accent,
        onPressed: () => notifier.copyToClipboard(context),
      );
    }
    if (showAlbum) {
      addAction(
        icon: Icons.photo_album_outlined,
        tooltip: l.galleryAlbum,
        color: t.accent,
        onPressed: () => _showAlbumPicker(context, notifier, gallery),
      );
    }
    if (showEdit) {
      addAction(
        icon: Icons.brush,
        tooltip: l.mainEdit,
        color: t.accentEdit,
        onPressed: () {
          context.read<Img2ImgNotifier>().loadSourceImage(
            state.generatedImage!,
          );
          openTool('img2img');
        },
      );
    }
    if (showBgRemoval) {
      addAction(
        icon: ml.isProcessing ? Icons.hourglass_top : Icons.content_cut,
        tooltip: withCap(
          l.mlRemoveBg,
          PaidTool.augment,
          paid: bgRemovalBackend == 'novelai',
        ),
        color: t.accentBgRemoval,
        onPressed: ml.isProcessing
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
      );
    }
    if (showUpscale) {
      addAction(
        icon: ml.isProcessing ? Icons.hourglass_top : Icons.zoom_out_map,
        tooltip: withCap(
          l.mlUpscale,
          PaidTool.upscale,
          paid: upscaleBackend == 'novelai',
        ),
        color: t.accentUpscale,
        onPressed: ml.isProcessing
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
      );
    }
    if (showEnhance) {
      addAction(
        icon: Icons.hd,
        tooltip: l.quickActionEnhance,
        color: t.accent,
        onPressed: () {
          context.read<EnhanceNotifier>().setSourceImage(state.generatedImage!);
          openTool('enhance');
        },
      );
    }
    if (showDirectorTools) {
      addAction(
        icon: Icons.auto_fix_high,
        tooltip: withCap(l.quickActionDirectorTools, PaidTool.augment),
        color: t.accent,
        onPressed: () {
          context.read<DirectorToolsNotifier>().setSourceImage(
            state.generatedImage!,
          );
          openTool('director_tools');
        },
      );
    }
    if (actions.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VisionMetrics.space12,
            VisionMetrics.space12,
            VisionMetrics.space16,
            VisionMetrics.space12,
          ),
          child: ConstrainedBox(
            key: const ValueKey<String>('quick-action-rail'),
            constraints: BoxConstraints(
              maxHeight: (constraints.maxHeight - 2 * VisionMetrics.space12)
                  .clamp(0.0, double.infinity)
                  .toDouble(),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                spacing: VisionMetrics.space4,
                children: actions,
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
) async {
  final basename = await notifier.ensureSavedAndGetBasename();
  if (basename == null || !context.mounted) return;

  showAppSheet<void>(
    context: context,
    builder: (sheetContext) {
      final t = sheetContext.t;
      return AppPickerSheet(
        title: sheetContext.l.galleryAddToAlbum,
        child: Column(
          children: [
            for (final album in gallery.albums)
              ListTile(
                leading: Icon(
                  Icons.photo_album,
                  size: VisionMetrics.iconMedium,
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
                    ? Icon(
                        Icons.check,
                        size: VisionMetrics.iconMedium,
                        color: t.accentSuccess,
                      )
                    : null,
                onTap: () {
                  gallery.addToAlbumByBasename(album.id, basename);
                  Navigator.pop(sheetContext);
                  showAppSnackBar(
                    context,
                    sheetContext.l.galleryAddedToAlbum(album.name),
                  );
                },
              ),
          ],
        ),
      );
    },
  );
}
