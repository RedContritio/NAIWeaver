import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/services/saf_export_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/ui/overlay_action_button.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/timestamp_utils.dart';
import '../providers/gallery_notifier.dart';
import '../../generation/providers/generation_notifier.dart';
import '../../director_ref/providers/director_ref_notifier.dart';
import '../../vibe_transfer/providers/vibe_transfer_notifier.dart';
import '../../director_ref/widgets/reference_add_actions.dart'
    show vibeEncodeErrorMessage;
import '../../tools/img2img/providers/img2img_notifier.dart';
import '../../tools/slideshow/models/slideshow_config.dart';
import '../../tools/slideshow/providers/slideshow_notifier.dart';
import '../../tools/slideshow/widgets/slideshow_player.dart';
import '../../tools/tools_hub_screen.dart';
import '../../tools/widgets/tool_source_picker.dart';
import 'import_metadata_dialog.dart';
import '../../../core/ml/ml_notifier.dart';
import '../../../core/ml/widgets/ml_processing_overlay.dart';
import '../../../core/ml/widgets/bg_removal_overlay.dart';
import '../../../core/ml/widgets/upscale_comparison_view.dart';
import '../../tools/enhance/providers/enhance_notifier.dart';
import '../../tools/director_tools/providers/director_tools_notifier.dart';
import '../../../core/services/novel_ai_image_action_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';
import '../services/tool_result_saver.dart';
import 'gallery_layout.dart';
import 'novel_ai_image_action_flow.dart';

class ImageDetailView extends StatefulWidget {
  final int initialIndex;

  const ImageDetailView({super.key, required this.initialIndex});

  @override
  State<ImageDetailView> createState() => _ImageDetailViewState();
}

class _ImageDetailViewState extends State<ImageDetailView>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  Map<String, dynamic>? _settings;
  bool _isLoadingMetadata = true;
  bool _isExporting = false;
  bool _showControls = true;
  bool _promptExpanded = false;
  Timer? _hideControlsTimer;
  final FocusNode _focusNode = FocusNode();

  // Per-page zoom controllers
  final Map<int, TransformationController> _zoomControllers = {};
  bool _isZoomed = false;

  // Action buttons scroll indicator
  final ScrollController _actionScrollController = ScrollController();
  bool _showScrollIndicator = true;
  bool _closing = false;

  // Paid NAI actions: one at a time, each with its own loading dialog.
  final _naiFlow = NovelAiImageActionFlow();

  // Double-tap zoom animation
  late final AnimationController _zoomAnimController;
  Animation<Matrix4>? _zoomAnimation;
  Offset? _lastDoubleTapLocal;

  GalleryItem? get _currentItemOrNull {
    final items = context.read<GalleryNotifier>().activeItems;
    return _currentIndex < items.length ? items[_currentIndex] : null;
  }

  GalleryItem get _currentItem {
    final gallery = Provider.of<GalleryNotifier>(context, listen: false);
    final items = gallery.activeItems;
    if (_currentIndex < items.length) return items[_currentIndex];
    return items.last;
  }

  TransformationController _getZoomController(int index) {
    return _zoomControllers.putIfAbsent(
      index,
      () => TransformationController(),
    );
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _zoomAnimController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 250),
        )..addListener(() {
          if (_zoomAnimation != null) {
            final controller = _zoomControllers[_currentIndex];
            if (controller != null) {
              controller.value = _zoomAnimation!.value;
            }
          }
        });
    _actionScrollController.addListener(_checkActionOverflow);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkActionOverflow());
    _loadMetadata();
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _zoomAnimController.dispose();
    _hideControlsTimer?.cancel();
    _pageController.dispose();
    _actionScrollController.dispose();
    _focusNode.dispose();
    for (final c in _zoomControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _showControlsAndReset() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _scheduleHideControls();
  }

  Future<void> _loadMetadata() async {
    final gallery = Provider.of<GalleryNotifier>(context, listen: false);
    final items = gallery.activeItems;
    if (_currentIndex >= items.length) {
      setState(() => _isLoadingMetadata = false);
      return;
    }
    final item = items[_currentIndex];
    final metadata = await gallery.getMetadata(item);

    // A later page change owns the panel now; never show stale metadata.
    if (!mounted || _currentItemOrNull != item) return;
    if (metadata != null && metadata.containsKey('Comment')) {
      final settings = parseCommentJson(metadata['Comment']!);
      setState(() {
        _settings = settings;
        _isLoadingMetadata = false;
      });
    } else {
      setState(() {
        _settings = null;
        _isLoadingMetadata = false;
      });
    }
  }

  void _onPageChanged(int index) {
    // Stop any in-flight zoom animation before resetting
    _zoomAnimController.stop();

    // Reset previous page zoom
    final prevController = _zoomControllers[_currentIndex];
    if (prevController != null) {
      prevController.value = Matrix4.identity();
    }

    setState(() {
      _currentIndex = index;
      _isLoadingMetadata = true;
      _promptExpanded = false;
      _isZoomed = false;
      _showScrollIndicator = true;
    });
    _loadMetadata();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkActionOverflow());

    // Preload adjacent images
    final gallery = Provider.of<GalleryNotifier>(context, listen: false);
    final items = gallery.activeItems;
    if (index + 1 < items.length) {
      precacheImage(
        FileImage(items[index + 1].file),
        context,
      ).catchError((_) {});
    }
    if (index - 1 >= 0) {
      precacheImage(
        FileImage(items[index - 1].file),
        context,
      ).catchError((_) {});
    }
  }

  void _checkActionOverflow() {
    if (!_actionScrollController.hasClients) return;
    final pos = _actionScrollController.position;
    final shouldShow =
        pos.maxScrollExtent > 0 && pos.pixels < pos.maxScrollExtent - 2;
    if (shouldShow != _showScrollIndicator) {
      setState(() => _showScrollIndicator = shouldShow);
    }
  }

  /// Shows a freshly saved result. It lands wherever the current sort puts
  /// it, and an album, favorites, search or demo filter may hide it.
  void _jumpToNewImage(String basename) {
    final index = context.read<GalleryNotifier>().activeIndexOf(basename);
    if (index == null) {
      showAppSnackBar(context, context.l.galleryNewImageHidden);
      return;
    }
    setState(() {
      _currentIndex = index;
      _isLoadingMetadata = true;
      _promptExpanded = false;
      _isZoomed = false;
      _showScrollIndicator = true;
    });
    _pageController.jumpToPage(index);
    _loadMetadata();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkActionOverflow());
  }

  /// The current image just left the active list (deleted, removed from the
  /// album, or unfavorited while only favorites show). The same index now
  /// holds the next image, so reload its metadata. When none is left, the
  /// empty-list guard in [build] closes the view.
  void _onCurrentItemRemoved() {
    final items = context.read<GalleryNotifier>().activeItems;
    if (items.isEmpty) return;
    setState(() {
      if (_currentIndex >= items.length) _currentIndex = items.length - 1;
      _isLoadingMetadata = true;
      _promptExpanded = false;
    });
    _loadMetadata();
  }

  /// Loads [item] into a tool and opens that tool in place of the gallery.
  Future<void> _sendToTool(
    GalleryItem item,
    String toolId,
    Future<void> Function(Uint8List bytes) loadSource,
  ) async {
    final bytes = await item.file.readAsBytes();
    if (!mounted) return;
    await loadSource(bytes);
    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.pop(); // detail view
    navigator.pop(); // gallery
    navigator.push(
      MaterialPageRoute(builder: (_) => ToolsHubScreen(initialToolId: toolId)),
    );
  }

  /// Returns (label, color) for post-processed images based on filename prefix.
  (String, Color)? _getPostProcessingBadge(GalleryItem item) {
    final name = p.basename(item.file.path);
    final t = context.tRead;
    final l = context.l;
    if (name.startsWith('NAI_UP_')) {
      return (l.galleryBadgeNaiUpscale, t.accentEdit);
    }
    if (name.startsWith('DT_')) {
      // Parse tool name from DT_{tool}_ prefix
      final parts = name.split('_');
      final toolName = parts.length >= 3 ? parts[1].toUpperCase() : 'TOOL';
      return (l.galleryBadgeDirectorTool(toolName), t.accent);
    }
    if (name.startsWith('ENH_')) {
      return (l.galleryBadgeEnhanced, t.accentSuccess);
    }
    if (name.startsWith('BG_')) return (l.galleryBadgeBgRemoved, t.accentEdit);
    if (name.startsWith('UP_')) return (l.galleryBadgeUpscaled, t.accent);
    return null;
  }

  void _onInteractionEnd(TransformationController controller) {
    final scale = controller.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.01;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
    }
  }

  void _onInteractionStart(ScaleStartDetails details) {
    if (details.pointerCount >= 2) {
      // Pinch detected — disable PageView scrolling immediately
      if (!_isZoomed) {
        setState(() => _isZoomed = true);
      }
    }
  }

  void _handleDoubleTap(TransformationController controller) {
    final current = controller.value.clone();
    final scale = current.getMaxScaleOnAxis();

    Matrix4 target;
    if (scale > 1.05) {
      target = Matrix4.identity();
      setState(() => _isZoomed = false);
    } else {
      const zoomScale = 2.5;
      final pos = _lastDoubleTapLocal ?? Offset.zero;
      final dx = pos.dx * (1 - zoomScale);
      final dy = pos.dy * (1 - zoomScale);
      target = Matrix4.identity()
        // ignore: deprecated_member_use
        ..translate(dx, dy, 0.0)
        // ignore: deprecated_member_use
        ..scale(zoomScale, zoomScale, 1.0);
      setState(() => _isZoomed = true);
    }

    _zoomAnimation = Matrix4Tween(begin: current, end: target).animate(
      CurvedAnimation(parent: _zoomAnimController, curve: Curves.easeOutCubic),
    );
    _zoomAnimController.forward(from: 0);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final gallery = Provider.of<GalleryNotifier>(context, listen: false);
    final items = gallery.activeItems;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        if (_currentIndex < items.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        if (_currentIndex > 0) {
          _pageController.previousPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.pop(context);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  Future<void> _exportImage() async {
    final t = context.tRead;
    final prefs = context.read<PreferencesService>();
    final item = _currentItem;
    setState(() => _isExporting = true);
    try {
      final sourceFile = item.file;
      final fileName = p.basename(sourceFile.path);
      final customFolder = prefs.exportFolderPath;

      // Honor a user-chosen export folder on touch (previously ignored — the
      // detail-view export always went to the device gallery, symptom #1 of #13).
      if (!kIsWeb &&
          (Platform.isAndroid || Platform.isIOS) &&
          customFolder.isNotEmpty) {
        // A SAF target may have lost its grant (card removed / permission
        // revoked); a legacy plain filesystem path is unreachable under Android
        // scoped storage. Either way, guide the user to re-pick it (issue #13).
        final unreachable =
            SafExportService.isStalePlainPath(customFolder) ||
            (SafExportService.isSafUri(customFolder) &&
                !await SafExportService.instance.hasWriteAccess(customFolder));
        if (unreachable) {
          if (mounted) {
            showErrorSnackBar(
              context,
              context.l.galleryExportFailed(
                'Export folder unavailable — re-pick it in Settings',
              ),
            );
          }
          return;
        }
        var bytes = await sourceFile.readAsBytes();
        if (prefs.stripMetadataOnExport) {
          bytes = stripMetadata(bytes);
        }
        final name = p.basenameWithoutExtension(sourceFile.path);
        if (SafExportService.isSafUri(customFolder)) {
          await SafExportService.instance.writePng(customFolder, name, bytes);
        } else {
          final dir = Directory(customFolder);
          if (!await dir.exists()) await dir.create(recursive: true);
          await File(p.join(customFolder, fileName)).writeAsBytes(bytes);
        }
        if (mounted) {
          showAppSnackBar(
            context,
            context.l.gallerySavedToDevice,
            color: t.accent,
          );
        }
      } else if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final hasAccess = await Gal.hasAccess();
        if (!hasAccess) await Gal.requestAccess();
        var bytes = await sourceFile.readAsBytes();
        if (prefs.stripMetadataOnExport) {
          bytes = stripMetadata(bytes);
        }
        final name = p.basenameWithoutExtension(sourceFile.path);
        final album = prefs.exportAlbumName;
        await Gal.putImageBytes(bytes, name: name, album: album);

        if (mounted) {
          showAppSnackBar(
            context,
            context.l.gallerySavedToDevice,
            color: t.accent,
          );
        }
      } else {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: context.l.galleryExportImageDialog,
          fileName: fileName,
          type: FileType.image,
        );
        if (result == null) return;

        if (prefs.stripMetadataOnExport) {
          var bytes = await sourceFile.readAsBytes();
          bytes = stripMetadata(bytes);
          await File(result).writeAsBytes(bytes);
        } else {
          await sourceFile.copy(result);
        }

        if (mounted) {
          showAppSnackBar(
            context,
            context.l.gallerySavedTo(p.basename(result)),
            color: t.accent,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, context.l.galleryExportFailed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  NovelAiImageActionService _naiActions() => NovelAiImageActionService(
    context.read<GenerationNotifier>().service,
    saver: ToolResultSaver.of(context),
  );

  String _outputName(String prefix, GalleryItem item) =>
      '${prefix}_${p.basenameWithoutExtension(item.file.path)}_'
      '${generateTimestamp()}.png';

  /// Shows an upscale next to its source; the user (or auto-save) keeps it.
  Future<void> _reviewUpscale(
    Uint8List source,
    Uint8List result,
    String outputName,
    Future<ToolResultSaveOutcome> Function() save,
  ) async {
    final autoSave = context.read<GenerationNotifier>().state.autoSaveImages;
    ToolResultSaveOutcome? outcome;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => UpscaleComparisonView(
          originalBytes: source,
          upscaledBytes: result,
          outputName: outputName,
          autoSave: autoSave,
          onSave: () async {
            final saved = await save();
            outcome = saved;
            if (!saved.succeeded && mounted) {
              showToolResultSaveFeedback(context, saved);
            }
            return saved.succeeded;
          },
        ),
      ),
    );
    if (outcome?.destination == ToolResultDestination.gallery && mounted) {
      _jumpToNewImage(outputName);
    }
  }

  /// Lets the user refine a background removal, then saves what they keep.
  Future<void> _reviewBgRemoval(
    Uint8List result,
    String outputName,
    Future<ToolResultSaveOutcome> Function(Uint8List kept) save,
  ) async {
    final t = context.tRead;
    final autoSave = context.read<GenerationNotifier>().state.autoSaveImages;
    final kept = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: t.background,
        child: BGRemovalOverlay(
          resultImage: result,
          onSave: (img) => Navigator.pop(ctx, img),
          onDiscard: () => Navigator.pop(ctx),
          autoSave: autoSave,
        ),
      ),
    );
    if (kept == null || !mounted) return;
    final outcome = await save(kept);
    if (!mounted) return;
    showToolResultSaveFeedback(
      context,
      outcome,
      savedMessage: context.l.mlBgRemovedSavedAs(outputName),
    );
    if (outcome.destination == ToolResultDestination.gallery) {
      _jumpToNewImage(outputName);
    }
  }

  Future<void> _handleRemoveBg(GalleryItem item) async {
    final ml = context.read<MLNotifier>();
    final saver = ToolResultSaver.of(context);

    final bytes = await item.file.readAsBytes();
    if (!mounted) return;

    final result = await ml.removeBackground(bytes);
    if (!mounted) return;

    if (result == null) {
      showErrorSnackBar(context, context.l.galleryBgRemovalFailed);
      return;
    }

    final outputName = _outputName('BG', item);
    await _reviewBgRemoval(
      result,
      outputName,
      (kept) => saver.save(kept, outputName, sourceBytes: bytes),
    );
  }

  Future<void> _handleUpscale(GalleryItem item) async {
    final ml = context.read<MLNotifier>();
    final saver = ToolResultSaver.of(context);

    final bytes = await item.file.readAsBytes();
    if (!mounted) return;

    final result = await ml.upscaleImage(bytes);
    if (!mounted) return;

    if (result == null) {
      showErrorSnackBar(context, context.l.mlUpscaleFailed);
      return;
    }

    final outputName = _outputName('UP', item);
    await _reviewUpscale(
      bytes,
      result,
      outputName,
      () => saver.save(result, outputName, sourceBytes: bytes),
    );
  }

  Future<void> _handleNaiUpscale(
    GalleryItem item, {
    required bool permissionGranted,
  }) {
    final service = _naiActions();
    return _naiFlow.run(
      context,
      service: service,
      action: NovelAiImageAction.upscale,
      permissionGranted: permissionGranted,
      apiKey: context.read<GenerationNotifier>().state.apiKey,
      readSource: item.file.readAsBytes,
      onResult: (source, result) {
        final outputName = _outputName(
          NovelAiImageAction.upscale.filePrefix,
          item,
        );
        return _reviewUpscale(
          source,
          result,
          outputName,
          () => service.save(result, outputName, sourceBytes: source),
        );
      },
    );
  }

  Future<void> _handleNaiBgRemoval(
    GalleryItem item, {
    required bool permissionGranted,
  }) {
    final service = _naiActions();
    return _naiFlow.run(
      context,
      service: service,
      action: NovelAiImageAction.backgroundRemoval,
      permissionGranted: permissionGranted,
      apiKey: context.read<GenerationNotifier>().state.apiKey,
      readSource: item.file.readAsBytes,
      onResult: (source, result) {
        final outputName = _outputName(
          NovelAiImageAction.backgroundRemoval.filePrefix,
          item,
        );
        return _reviewBgRemoval(
          result,
          outputName,
          (kept) => service.save(kept, outputName, sourceBytes: source),
        );
      },
    );
  }

  void _launchSlideshow() {
    final gallery = context.read<GalleryNotifier>();
    final slideshowNotifier = context.read<SlideshowNotifier>();
    final item = _currentItem;
    final config =
        slideshowNotifier.defaultConfig ??
        const SlideshowConfig(id: '_quick_play', name: 'Quick Play');
    var playlist = slideshowNotifier.buildPlaylist(config, gallery);
    // Rotate playlist to start at current image
    final idx = playlist.indexWhere((i) => i.basename == item.basename);
    if (idx > 0) {
      playlist = [...playlist.sublist(idx), ...playlist.sublist(0, idx)];
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SlideshowPlayer(config: config, playlist: playlist),
      ),
    );
  }

  Future<void> _copyImageToClipboard(GalleryItem item) async {
    try {
      final bytes = await item.file.readAsBytes();

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final name = p.basenameWithoutExtension(item.file.path);
        await Share.shareXFiles([
          XFile.fromData(bytes, mimeType: 'image/png', name: '$name.png'),
        ]);
        return;
      }

      final clipItem = DataWriterItem();
      clipItem.add(Formats.png(bytes));
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        await clipboard.write([clipItem]);
        if (mounted) {
          showAppSnackBar(
            context,
            context.l.galleryCopiedToClipboard,
            color: context.tRead.accentSuccess,
          );
        }
        return;
      }
    } catch (_) {}
    if (mounted) {
      showErrorSnackBar(context, context.l.galleryClipboardUnavailable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final gallery = context.watch<GalleryNotifier>();
    final touch = windowSizeClassOf(context).isTouchSized;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final items = gallery.activeItems;
    final ml = context.watch<MLNotifier>();
    final prefs = context.read<PreferencesService>();
    final naiBgRemovalAllowed = hasNovelAiImageActionPermission(
      context,
      NovelAiImageAction.backgroundRemoval,
    );
    final naiUpscaleAllowed = hasNovelAiImageActionPermission(
      context,
      NovelAiImageAction.upscale,
    );
    final canRemoveBackground = prefs.bgRemovalBackend == 'novelai'
        ? isNovelAiImageActionOffered(
            context,
            NovelAiImageAction.backgroundRemoval,
          )
        : ml.hasBgRemovalModel;
    final canUpscale = prefs.upscaleBackend == 'novelai'
        ? isNovelAiImageActionOffered(context, NovelAiImageAction.upscale)
        : ml.hasUpscaleModel;
    // Tools that are charged by NovelAI say what they can cost at most.
    String withCap(String label, PaidTool tool, {required bool paid}) {
      final cap = paid ? paidToolCapLabel(context, tool) : null;
      return (cap == null ? label : '$label · $cap').toUpperCase();
    }

    // Guard: if all images are gone, pop once (later rebuilds during the exit
    // transition must not pop the gallery underneath as well).
    if (items.isEmpty) {
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
      return Scaffold(backgroundColor: t.background);
    }

    // Clamp index if items were deleted
    if (_currentIndex >= items.length) {
      _currentIndex = items.length - 1;
    }

    final item = items[_currentIndex];

    Widget viewerAction({
      required IconData icon,
      required String label,
      required Color color,
      required VoidCallback? onTap,
    }) => OverlayActionButton(
      icon: icon,
      tooltip: label,
      label: label,
      color: color,
      onPressed: onTap,
    );

    return Scaffold(
      backgroundColor: t.background,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: GestureDetector(
          onTap: _showControlsAndReset,
          child: MouseRegion(
            onHover: (_) => _showControlsAndReset(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Layer 1: PageView with per-page InteractiveViewer
                PageView.builder(
                  controller: _pageController,
                  itemCount: items.length,
                  onPageChanged: _onPageChanged,
                  physics: _isZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  itemBuilder: (context, index) {
                    final pageItem = items[index];
                    final zoomController = _getZoomController(index);
                    return GestureDetector(
                      onDoubleTapDown: (details) =>
                          _lastDoubleTapLocal = details.localPosition,
                      onDoubleTap: () => _handleDoubleTap(zoomController),
                      child: InteractiveViewer(
                        transformationController: zoomController,
                        onInteractionStart: _onInteractionStart,
                        onInteractionEnd: (_) =>
                            _onInteractionEnd(zoomController),
                        child: Center(
                          child: Image.file(
                            pageItem.file,
                            fit: BoxFit.contain,
                            // Corrupted files must show a placeholder rather
                            // than surface a decode error (issue #24).
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.broken_image_outlined,
                              size: 64,
                              color: context.t.textMinimal,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Layer 2: Top overlay
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.only(
                          top: topPadding + 8,
                          left: 8,
                          right: 8,
                          bottom: 16,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              t.background.withValues(alpha: 0.9),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Listener(
                          onPointerDown: (_) => _showControlsAndReset(),
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.arrow_back_ios,
                                  size: touch ? 20 : 14,
                                  color: t.textSecondary,
                                ),
                                tooltip: MaterialLocalizations.of(
                                  context,
                                ).backButtonTooltip,
                                onPressed: () => Navigator.pop(context),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    '${_currentIndex + 1} / ${items.length}',
                                    style: TextStyle(
                                      color: t.textDisabled,
                                      fontSize: t.fontSize(touch ? 11 : 9),
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      item.isFavorite
                                          ? Icons.star
                                          : Icons.star_outline,
                                      size: touch ? 22 : 18,
                                      color: item.isFavorite
                                          ? t.accentFavorite
                                          : t.textSecondary,
                                    ),
                                    tooltip: context.l.galleryToggleFavorite,
                                    onPressed: () {
                                      gallery.toggleFavorite(item);
                                      if (gallery.showFavoritesOnly &&
                                          !item.isFavorite) {
                                        _onCurrentItemRemoved();
                                      } else {
                                        setState(() {});
                                      }
                                    },
                                  ),
                                  _isExporting
                                      ? Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: touch ? 22 : 18,
                                            height: touch ? 22 : 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: t.textSecondary,
                                            ),
                                          ),
                                        )
                                      : IconButton(
                                          icon: Icon(
                                            Icons.save_alt,
                                            size: touch ? 22 : 18,
                                            color: t.textSecondary,
                                          ),
                                          tooltip: context.l.galleryExportImage,
                                          onPressed: _exportImage,
                                        ),
                                  // Remove from album (only when viewing an album)
                                  if (gallery.activeAlbumId != null)
                                    IconButton(
                                      icon: Icon(
                                        Icons.playlist_remove,
                                        size: touch ? 22 : 18,
                                        color: t.textSecondary,
                                      ),
                                      tooltip: context.l.galleryRemoveFromAlbum,
                                      onPressed: () async {
                                        final albumId = gallery.activeAlbumId!;
                                        final confirm = await showConfirmDialog(
                                          context,
                                          title: context
                                              .l
                                              .galleryRemoveFromAlbumTitle,
                                          message: context
                                              .l
                                              .galleryRemoveFromAlbumMessage,
                                          confirmLabel: context.l.galleryRemove,
                                          cancelLabel: context.l.commonCancel,
                                        );
                                        if (!context.mounted ||
                                            confirm != true) {
                                          return;
                                        }
                                        gallery.removeFromAlbum(albumId, [
                                          item,
                                        ]);
                                        _onCurrentItemRemoved();
                                      },
                                    ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: touch ? 22 : 18,
                                      color: t.accentDanger,
                                    ),
                                    tooltip:
                                        context.l.galleryDeleteImageTooltip,
                                    onPressed: () async {
                                      final confirm = await showConfirmDialog(
                                        context,
                                        title: context.l.galleryDeleteImage,
                                        confirmLabel: context.l.commonDelete,
                                        confirmColor: t.accentDanger,
                                      );
                                      if (!context.mounted || confirm != true) {
                                        return;
                                      }
                                      await Provider.of<GalleryNotifier>(
                                        context,
                                        listen: false,
                                      ).deleteItem(item);
                                      if (!context.mounted) return;
                                      _onCurrentItemRemoved();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Layer 3: Bottom overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: GalleryDetailPanelViewport(
                        mobile: touch,
                        padding: EdgeInsets.only(
                          bottom: bottomPadding + 12,
                          left: 16,
                          right: 16,
                          top: 32,
                        ),
                        background: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              t.background.withValues(alpha: 0.9),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Listener(
                          onPointerDown: (_) => _showControlsAndReset(),
                          onPointerMove: (_) => _showControlsAndReset(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Post-processing badge
                              if (_getPostProcessingBadge(item) case (
                                final label,
                                final color,
                              ))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(2),
                                      border: Border.all(
                                        color: color.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: color,
                                        fontSize: t.fontSize(touch ? 9 : 7),
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              // Prompt text (expandable)
                              if (_isLoadingMetadata)
                                LinearProgressIndicator(
                                  minHeight: 1,
                                  backgroundColor: Colors.transparent,
                                  color: t.textMinimal,
                                )
                              else if (_settings != null) ...[
                                GestureDetector(
                                  onTap: () => setState(
                                    () => _promptExpanded = !_promptExpanded,
                                  ),
                                  child: Text(
                                    (_settings!['prompt'] ??
                                            context.l.galleryNoPrompt
                                                .toUpperCase())
                                        .toString()
                                        .toUpperCase(),
                                    maxLines: _promptExpanded ? 20 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: t.textSecondary,
                                      fontSize: touch
                                          ? t.fontSize(12)
                                          : t.fontSize(9),
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                      shadows: [
                                        Shadow(
                                          color: t.background,
                                          blurRadius: 4,
                                        ),
                                        Shadow(
                                          color: t.background,
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Info chips row
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      if (_settings!['width'] != null &&
                                          _settings!['height'] != null)
                                        _InfoChip(
                                          label: context.l.galleryResolution
                                              .toUpperCase(),
                                          value:
                                              '${_settings!['width']}x${_settings!['height']}',
                                        ),
                                      _InfoChip(
                                        label: context.l.galleryScale
                                            .toUpperCase(),
                                        value:
                                            _settings!['scale']?.toString() ??
                                            "N/A",
                                      ),
                                      _InfoChip(
                                        label: context.l.gallerySteps
                                            .toUpperCase(),
                                        value:
                                            _settings!['steps']?.toString() ??
                                            "N/A",
                                      ),
                                      _InfoChip(
                                        label: context.l.gallerySampler
                                            .toUpperCase(),
                                        value:
                                            _settings!['sampler']?.toString() ??
                                            "N/A",
                                      ),
                                      _InfoChip(
                                        label: context.l.gallerySeed
                                            .toUpperCase(),
                                        value:
                                            _settings!['seed']?.toString() ??
                                            "N/A",
                                      ),
                                    ],
                                  ),
                                ),
                              ] else
                                Text(
                                  context.l.galleryNoMetadata.toUpperCase(),
                                  style: TextStyle(
                                    color: t.textDisabled,
                                    fontSize: t.fontSize(9),
                                    letterSpacing: 1,
                                    shadows: [
                                      Shadow(
                                        color: t.background,
                                        blurRadius: 4,
                                      ),
                                      Shadow(
                                        color: t.background,
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 12),
                              // Action buttons row
                              Stack(
                                children: [
                                  SingleChildScrollView(
                                    controller: _actionScrollController,
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      spacing: VisionMetrics.space8,
                                      children: [
                                        viewerAction(
                                          icon: Icons.upload_outlined,
                                          label: context.l.galleryPrompt
                                              .toUpperCase(),
                                          color: t.accent,
                                          onTap: () async {
                                            final notifier = context
                                                .read<GenerationNotifier>();
                                            final result = await notifier
                                                .parseImageMetadata(item.file);
                                            if (!context.mounted) return;
                                            final categories =
                                                await showImportMetadataDialog(
                                                  context,
                                                  result: result,
                                                );
                                            if (categories == null ||
                                                !context.mounted) {
                                              return;
                                            }
                                            notifier.applyImportedMetadata(
                                              result,
                                              categories,
                                            );
                                            Navigator.pop(context);
                                            Navigator.pop(context);
                                          },
                                        ),
                                        viewerAction(
                                          icon: Icons.brush_outlined,
                                          label: context.l.galleryImg2img
                                              .toUpperCase(),
                                          color: t.accentEdit,
                                          onTap: () => _sendToTool(
                                            item,
                                            'img2img',
                                            (bytes) {
                                              final imported =
                                                  prefs.img2imgImportPrompt
                                                  ? promptFromImageMetadata(
                                                      bytes,
                                                    )
                                                  : null;
                                              return context
                                                  .read<Img2ImgNotifier>()
                                                  .loadSourceImage(
                                                    bytes,
                                                    prompt: imported?.prompt,
                                                    negativePrompt: imported
                                                        ?.negativePrompt,
                                                    filePath: item.file.path,
                                                  );
                                            },
                                          ),
                                        ),
                                        viewerAction(
                                          icon: Icons.hd,
                                          label: context.l.galleryEnhance
                                              .toUpperCase(),
                                          color: t.accent,
                                          onTap: () => _sendToTool(
                                            item,
                                            'enhance',
                                            context
                                                .read<EnhanceNotifier>()
                                                .setSourceImage,
                                          ),
                                        ),
                                        viewerAction(
                                          icon: Icons.auto_fix_high,
                                          label: context.l.galleryDirectorTools
                                              .toUpperCase(),
                                          color: t.accent,
                                          onTap: () => _sendToTool(
                                            item,
                                            'director_tools',
                                            context
                                                .read<DirectorToolsNotifier>()
                                                .setSourceImage,
                                          ),
                                        ),
                                        if (canRemoveBackground)
                                          viewerAction(
                                            icon: ml.isProcessing
                                                ? Icons.hourglass_top
                                                : Icons.content_cut,
                                            label: withCap(
                                              context.l.mlRemoveBg,
                                              PaidTool.augment,
                                              paid:
                                                  prefs.bgRemovalBackend ==
                                                  'novelai',
                                            ),
                                            color: t.accent,
                                            onTap: ml.isProcessing
                                                ? null
                                                : () {
                                                    if (prefs
                                                            .bgRemovalBackend ==
                                                        'novelai') {
                                                      _handleNaiBgRemoval(
                                                        item,
                                                        permissionGranted:
                                                            naiBgRemovalAllowed,
                                                      );
                                                    } else {
                                                      _handleRemoveBg(item);
                                                    }
                                                  },
                                          ),
                                        if (canUpscale)
                                          viewerAction(
                                            icon: ml.isProcessing
                                                ? Icons.hourglass_top
                                                : Icons.zoom_out_map,
                                            label: withCap(
                                              context.l.mlUpscale,
                                              PaidTool.upscale,
                                              paid:
                                                  prefs.upscaleBackend ==
                                                  'novelai',
                                            ),
                                            color: t.accent,
                                            onTap: ml.isProcessing
                                                ? null
                                                : () {
                                                    if (prefs.upscaleBackend ==
                                                        'novelai') {
                                                      _handleNaiUpscale(
                                                        item,
                                                        permissionGranted:
                                                            naiUpscaleAllowed,
                                                      );
                                                    } else {
                                                      _handleUpscale(item);
                                                    }
                                                  },
                                          ),
                                        viewerAction(
                                          icon: Icons.person_outline,
                                          label: context.l.galleryCharRef
                                              .toUpperCase(),
                                          color: t.accentRefCharacter,
                                          onTap: () async {
                                            final bytes = await item.file
                                                .readAsBytes();
                                            if (!context.mounted) return;
                                            final id = await context
                                                .read<DirectorRefNotifier>()
                                                .addReference(bytes);
                                            if (!context.mounted) return;
                                            if (id == null) {
                                              showErrorSnackBar(
                                                context,
                                                context.l.refImageProcessFailed,
                                              );
                                              return;
                                            }
                                            showAppSnackBar(
                                              context,
                                              context.l.galleryAddedAsCharRef,
                                              color: t.accentRefCharacter,
                                            );
                                          },
                                        ),
                                        viewerAction(
                                          icon: Icons.palette_outlined,
                                          label: context.l.galleryVibe
                                              .toUpperCase(),
                                          color: t.accentVibeTransfer,
                                          onTap: () async {
                                            try {
                                              final bytes = await item.file
                                                  .readAsBytes();
                                              if (!context.mounted) return;
                                              await context
                                                  .read<VibeTransferNotifier>()
                                                  .addVibe(bytes);
                                              if (!context.mounted) return;
                                              showAppSnackBar(
                                                context,
                                                context.l.galleryAddedAsVibe,
                                                color: t.accentVibeTransfer,
                                              );
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              showErrorSnackBar(
                                                context,
                                                context.l
                                                    .galleryVibeTransferFailed(
                                                      vibeEncodeErrorMessage(
                                                        context.l,
                                                        e,
                                                      ),
                                                    ),
                                              );
                                            }
                                          },
                                        ),
                                        viewerAction(
                                          icon: Icons.slideshow_outlined,
                                          label: context.l.gallerySlideshow
                                              .toUpperCase(),
                                          color: t.textSecondary,
                                          onTap: _launchSlideshow,
                                        ),
                                        viewerAction(
                                          icon: touch
                                              ? Icons.share
                                              : Icons.copy,
                                          label: touch
                                              ? context.l.galleryShare
                                                    .toUpperCase()
                                              : context.l.galleryCopy
                                                    .toUpperCase(),
                                          color: t.textSecondary,
                                          onTap: () =>
                                              _copyImageToClipboard(item),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_showScrollIndicator)
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      bottom: 0,
                                      child: IgnorePointer(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 32,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.centerRight,
                                                  end: Alignment.centerLeft,
                                                  colors: [
                                                    t.background.withValues(
                                                      alpha: 0.9,
                                                    ),
                                                    Colors.transparent,
                                                  ],
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right,
                                              size: 16,
                                              color: t.textDisabled,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // ML Processing overlay
                const MLProcessingOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final touch = windowSizeClassOf(context).isTouchSized;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: EdgeInsets.symmetric(
        horizontal: touch ? 12 : 8,
        vertical: touch ? 6 : 4,
      ),
      decoration: BoxDecoration(
        color: t.borderSubtle,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: t.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: t.textDisabled,
              fontSize: touch ? t.fontSize(9) : t.fontSize(7),
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: t.textSecondary,
              fontSize: touch ? t.fontSize(11) : t.fontSize(9),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
