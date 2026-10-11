import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import '../../../core/utils/file_picker_helper.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import '../../../core/gateway/backend_permissions.dart';
import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/novel_ai_image_action_service.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/services/saf_export_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../../../core/widgets/ui/app_panel.dart';
import '../../../core/widgets/ui/app_pill.dart';
import '../../../core/widgets/ui/app_sheet.dart';
import '../../../core/widgets/ui/app_states.dart';
import '../../../core/widgets/ui/app_tone.dart';
import '../../../core/widgets/ui/overlay_action_button.dart';
import '../../../core/widgets/progress_dialog.dart';
import '../../../core/widgets/section_title.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/timestamp_utils.dart';
import '../providers/gallery_notifier.dart';
import '../services/gallery_import_service.dart';
import '../services/tool_result_saver.dart';
import '../../generation/providers/generation_notifier.dart';
import '../../tools/img2img/providers/img2img_notifier.dart';
import '../../../core/ml/ml_notifier.dart';
import '../../tools/canvas/providers/canvas_notifier.dart';
import '../../tools/canvas/widgets/canvas_editor.dart';
import '../../tools/ml/widgets/segmentation_overlay.dart';
import 'comparison_view.dart';
import 'gallery_layout.dart';
import 'image_detail_view.dart';
import 'import_metadata_dialog.dart';
import 'novel_ai_image_action_flow.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _gridKey = GlobalKey();
  final FocusNode _galleryFocusNode = FocusNode();
  bool _isSearching = false;
  int? _crossAxisCount;

  // Selection mode
  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};

  // Drag-to-select state (touch long-press-then-drag)
  final Set<int> _dragSelectedIndices = {};
  bool _isDragging = false;

  // Desktop rectangle drag state
  Offset? _dragStart;
  Offset? _dragCurrent;
  bool _isRectDragging = false;

  // Info overlay (hover/long-press)
  int? _hoveredIndex;

  // Measured height of the floating bulk action bar.
  double _bulkBarHeight = 0;

  @override
  void initState() {
    super.initState();
    // Drop entries whose files were deleted outside the app (issue #24).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<GalleryNotifier>().reconcileWithDisk();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _crossAxisCount ??=
        context.read<PreferencesService>().galleryGridColumns ??
        (windowSizeClassOf(context).isTouchSized ? 2 : 4);
  }

  @override
  void dispose() {
    _galleryFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIndices.clear();
      _dragSelectedIndices.clear();
    });
  }

  void _enterSelectionMode(int index) {
    setState(() {
      _isSelectionMode = true;
      _selectedIndices.add(index);
    });
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _selectAll(List<GalleryItem> items) {
    setState(() {
      if (_selectedIndices.length == items.length) {
        _selectedIndices.clear();
      } else {
        _selectedIndices.addAll(List.generate(items.length, (i) => i));
      }
    });
  }

  // Compute grid cell index from local position relative to grid
  int? _cellIndexFromOffset(Offset localPosition, int itemCount) {
    final cols = _crossAxisCount!;
    const padding = 8.0;
    const spacing = 8.0;

    final renderBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;

    final gridWidth = renderBox.size.width;
    final cellSize = (gridWidth - padding * 2 - spacing * (cols - 1)) / cols;
    if (cellSize <= 0) return null;

    final x = localPosition.dx;
    final y = localPosition.dy + _scrollController.offset;

    final col = ((x - padding) / (cellSize + spacing)).floor().clamp(
      0,
      cols - 1,
    );
    final row = ((y - padding) / (cellSize + spacing)).floor();
    if (row < 0) return null;

    final index = row * cols + col;
    if (index < 0 || index >= itemCount) return null;
    return index;
  }

  // Desktop rectangle selection: compute all indices within rectangle
  Set<int> _indicesInRect(Offset start, Offset end, int itemCount) {
    final cols = _crossAxisCount!;
    const padding = 8.0;
    const spacing = 8.0;

    final renderBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return {};

    final gridWidth = renderBox.size.width;
    final cellSize = (gridWidth - padding * 2 - spacing * (cols - 1)) / cols;
    if (cellSize <= 0) return {};

    final scrollOff = _scrollController.offset;

    final left = min(start.dx, end.dx);
    final right = max(start.dx, end.dx);
    final top = min(start.dy, end.dy) + scrollOff;
    final bottom = max(start.dy, end.dy) + scrollOff;

    final result = <int>{};
    for (int i = 0; i < itemCount; i++) {
      final row = i ~/ cols;
      final col = i % cols;
      final cellLeft = padding + col * (cellSize + spacing);
      final cellTop = padding + row * (cellSize + spacing);
      final cellRight = cellLeft + cellSize;
      final cellBottom = cellTop + cellSize;

      // Check overlap
      if (cellRight > left &&
          cellLeft < right &&
          cellBottom > top &&
          cellTop < bottom) {
        result.add(i);
      }
    }
    return result;
  }

  Future<Uint8List> _maybeStripMetadata(Uint8List bytes) async {
    final prefs = context.read<PreferencesService>();
    if (prefs.stripMetadataOnExport) {
      return stripMetadata(bytes);
    }
    return bytes;
  }

  Future<void> _bulkExport(List<GalleryItem> selectedItems) async {
    final t = context.tRead;
    final prefs = context.read<PreferencesService>();
    try {
      // Honor a user-chosen export folder on touch (previously ignored — the
      // bulk export always went to the device gallery, symptom #1 of #13).
      final customFolder = prefs.exportFolderPath;
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
                context.l.galleryExportFolderUnavailable,
              ),
            );
          }
          _exitSelectionMode();
          return;
        }
        int copied = 0;
        for (final item in selectedItems) {
          var bytes = await item.file.readAsBytes();
          bytes = await _maybeStripMetadata(bytes);
          final name = p.basenameWithoutExtension(item.file.path);
          if (SafExportService.isSafUri(customFolder)) {
            await SafExportService.instance.writePng(customFolder, name, bytes);
          } else {
            final dir = Directory(customFolder);
            if (!await dir.exists()) await dir.create(recursive: true);
            await File(p.join(customFolder, item.basename)).writeAsBytes(bytes);
          }
          copied++;
        }
        if (mounted) {
          showAppSnackBar(
            context,
            context.l.gallerySavedToDeviceCount(copied, selectedItems.length),
            color: t.accent,
          );
        }
      } else if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final album = prefs.exportAlbumName;
        final hasAccess = await Gal.hasAccess();
        if (!hasAccess) await Gal.requestAccess();
        int saved = 0;
        for (final item in selectedItems) {
          var bytes = await item.file.readAsBytes();
          bytes = await _maybeStripMetadata(bytes);
          final name = p.basenameWithoutExtension(item.file.path);
          await Gal.putImageBytes(bytes, name: name, album: album);
          saved++;
        }
        if (mounted) {
          showAppSnackBar(
            context,
            context.l.gallerySavedToDeviceCount(saved, selectedItems.length),
            color: t.accent,
          );
        }
      } else {
        final dirPath = await FilePicker.platform.getDirectoryPath(
          dialogTitle: context.l.galleryExportDialogTitle(selectedItems.length),
        );
        if (dirPath == null) return;

        int copied = 0;
        for (final item in selectedItems) {
          final dest = p.join(dirPath, item.basename);
          var bytes = await item.file.readAsBytes();
          bytes = await _maybeStripMetadata(bytes);
          await File(dest).writeAsBytes(bytes);
          copied++;
        }
        if (mounted) {
          showAppSnackBar(
            context,
            context.l.galleryExportedToFolder(copied, p.basename(dirPath)),
            color: t.accent,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, context.l.galleryExportFailed(e.toString()));
      }
    }
    _exitSelectionMode();
  }

  Future<void> _bulkDelete(List<GalleryItem> selectedItems) async {
    final t = context.tRead;
    final confirm = await showConfirmDialog(
      context,
      title: context.l.galleryDeleteCount(selectedItems.length),
      message: context.l.galleryCannotUndo,
      confirmLabel: context.l.commonDelete,
      confirmColor: t.accentDanger,
      messageFontSize: windowSizeClassOf(context).isTouchSized
          ? t.fontSize(12)
          : null,
    );
    if (!mounted || confirm != true) return;
    await Provider.of<GalleryNotifier>(
      context,
      listen: false,
    ).deleteItems(selectedItems);
    if (!mounted) return;
    _exitSelectionMode();
  }

  Future<void> _bulkRemoveFromAlbum(List<GalleryItem> selectedItems) async {
    final confirm = await showConfirmDialog(
      context,
      title: context.l.galleryRemoveFromAlbumCount(selectedItems.length),
      message: context.l.galleryRemoveFromAlbumMessage,
      confirmLabel: context.l.galleryRemove,
      cancelLabel: context.l.commonCancel,
    );
    if (!mounted || confirm != true) return;
    final gallery = context.read<GalleryNotifier>();
    final albumId = gallery.activeAlbumId;
    if (albumId == null) return;
    gallery.removeFromAlbum(albumId, selectedItems);
    setState(() => _selectedIndices.clear());
  }

  void _bulkFavorite(List<GalleryItem> selectedItems) {
    Provider.of<GalleryNotifier>(
      context,
      listen: false,
    ).addToFavorites(selectedItems);
    _exitSelectionMode();
  }

  Future<void> _openSegmentation(GalleryItem item) async {
    _exitSelectionMode();
    final saver = ToolResultSaver.of(context);
    final imageBytes = await item.file.readAsBytes();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ChangeNotifierProvider.value(
          value: context.read<MLNotifier>(),
          child: Scaffold(
            backgroundColor: ctx.tRead.background,
            body: SafeArea(
              child: SegmentationOverlay(
                sourceImage: imageBytes,
                onSave: (resultBytes) async {
                  final baseName = p.basenameWithoutExtension(item.file.path);
                  final ts = DateTime.now().millisecondsSinceEpoch;
                  final outcome = await saveToolResult(
                    ctx,
                    bytes: resultBytes,
                    fileName: 'SEG_${baseName}_$ts.png',
                    sourceBytes: imageBytes,
                    saver: saver,
                  );
                  if (outcome.succeeded && ctx.mounted) Navigator.pop(ctx);
                },
                onDiscard: () => Navigator.pop(ctx),
                onSendToCanvas: (resultBytes) {
                  Navigator.pop(ctx);
                  final canvasNotifier = context.read<CanvasNotifier>();
                  canvasNotifier.addImageLayer(resultBytes, name: 'Segmented');
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openInCanvas(GalleryItem item) async {
    _exitSelectionMode();
    final img2imgNotifier = context.read<Img2ImgNotifier>();
    final imageBytes = await item.file.readAsBytes();
    if (!mounted) return;

    // Load into img2img which decodes dimensions in isolate
    await img2imgNotifier.loadSourceImage(imageBytes, filePath: item.file.path);
    final session = img2imgNotifier.session;
    if (session == null || !mounted) return;

    // Start canvas from the loaded session
    final canvasNotifier = context.read<CanvasNotifier>();
    canvasNotifier.startSession(
      session.sourceImageBytes,
      session.sourceWidth,
      session.sourceHeight,
    );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CanvasEditor()),
    );
  }

  /// Runs a local ML model over [selectedItems] and saves each result with
  /// its source metadata. Only images that were processed and saved count.
  Future<void> _bulkLocalMl(
    List<GalleryItem> selectedItems, {
    required String title,
    required String filePrefix,
    required Future<Uint8List?> Function(Uint8List bytes) process,
    required String Function(int succeeded, int total) summary,
  }) async {
    final saver = ToolResultSaver.of(context);
    final total = selectedItems.length;
    var succeeded = 0;

    final progress = showProgressDialog(context, title: title);

    for (var i = 0; i < total; i++) {
      final item = selectedItems[i];
      try {
        final bytes = await item.file.readAsBytes();
        final result = await process(bytes);
        if (result != null) {
          final baseName = p.basenameWithoutExtension(item.file.path);
          final outcome = await saver.save(
            result,
            '${filePrefix}_${baseName}_${generateTimestamp()}.png',
            sourceBytes: bytes,
          );
          if (outcome.succeeded) succeeded++;
        }
      } catch (e) {
        debugPrint('_GalleryScreenState._bulkLocalMl: $e');
      }
      progress.update(i + 1, total);
    }

    progress.close();
    _showBatchSummary(
      summary(succeeded, total),
      allSucceeded: succeeded == total,
    );
    _exitSelectionMode();
  }

  void _showBatchSummary(String message, {required bool allSucceeded}) {
    if (!mounted) return;
    if (allSucceeded) {
      showAppSnackBar(context, message);
    } else {
      showErrorSnackBar(context, message);
    }
  }

  Future<void> _bulkRemoveBg(List<GalleryItem> selectedItems) => _bulkLocalMl(
    selectedItems,
    title: context.l.galleryRemovingBackgrounds,
    filePrefix: 'BG',
    process: context.read<MLNotifier>().removeBackground,
    summary: context.l.mlBgRemovedCount,
  );

  Future<void> _bulkUpscale(List<GalleryItem> selectedItems) => _bulkLocalMl(
    selectedItems,
    title: context.l.mlUpscalingImages,
    filePrefix: 'UP',
    process: context.read<MLNotifier>().upscaleImage,
    summary: context.l.mlUpscaledCount,
  );

  Future<void> _bulkNaiUpscale(
    List<GalleryItem> selectedItems, {
    required bool permissionGranted,
  }) async {
    final gen = context.read<GenerationNotifier>();
    final service = NovelAiImageActionService(
      gen.service,
      saver: ToolResultSaver.of(context),
    );
    final blocker = service.blocker(
      apiKey: gen.state.apiKey,
      permissionGranted: permissionGranted,
    );
    if (blocker != null) {
      showErrorSnackBar(
        context,
        novelAiImageActionBlockerMessage(context.l, blocker),
      );
      return;
    }

    final progress = showProgressDialog(
      context,
      title: context.l.naiUpscaling,
      progressColor: context.tRead.accentEdit,
    );
    final result = await service.upscaleAll([
      for (final item in selectedItems)
        NovelAiImageActionSource(
          baseName: p.basenameWithoutExtension(item.file.path),
          readBytes: item.file.readAsBytes,
        ),
    ], onProgress: progress.update);
    progress.close();

    if (mounted) {
      _showBatchSummary(
        context.l.naiUpscaledCount(result.succeeded, result.total),
        allSucceeded: result.succeeded == result.total,
      );
    }
    _exitSelectionMode();
  }

  Future<void> _importImages() async {
    final t = context.tRead;
    final gallery = context.read<GalleryNotifier>();

    final result = await pickImageFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final sources = result.files.map(GalleryImportSource.picked).toList();
    final showProgress = sources.length >= 3;
    int currentProgress = 0;
    int totalProgress = sources.length;
    StateSetter? dialogSetState;

    if (showProgress && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) {
            dialogSetState = setState;
            final t = ctx.tRead;
            return AlertDialog(
              backgroundColor: t.surfaceHigh,
              title: Text(
                context.l.galleryImporting.toUpperCase(),
                style: TextStyle(
                  fontSize: t.fontSize(10),
                  letterSpacing: 2,
                  color: t.textSecondary,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: totalProgress > 0
                        ? currentProgress / totalProgress
                        : 0,
                    backgroundColor: t.borderSubtle,
                    color: t.accent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    currentProgress > 0
                        ? context.l.galleryImportProgress(
                            currentProgress,
                            totalProgress,
                          )
                        : context.l.galleryImportPreparing,
                    style: TextStyle(
                      color: t.textDisabled,
                      fontSize: t.fontSize(10),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    try {
      final importResult = await gallery.importFiles(
        sources,
        onProgress: (current, total) {
          currentProgress = current;
          totalProgress = total;
          dialogSetState?.call(() {});
        },
      );

      if (showProgress && mounted) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;

      String message;
      if (importResult.converted > 0) {
        message = context.l.galleryImportConverted(
          importResult.succeeded,
          importResult.converted,
        );
      } else {
        message = context.l.galleryImportSuccess(
          importResult.succeeded,
          importResult.withMetadata,
        );
      }

      if (importResult.filesWithMetadata.isNotEmpty) {
        showAppSnackBar(
          context,
          message,
          color: t.accent,
          action: SnackBarAction(
            label: context.l.galleryImportToEditor.toUpperCase(),
            textColor: t.accent,
            onPressed: () {
              if (!mounted) return;
              _importMetadataToEditor(importResult.filesWithMetadata.first);
            },
          ),
        );
      } else {
        showAppSnackBar(context, message, color: t.accent);
      }
    } catch (e) {
      if (showProgress && mounted) {
        Navigator.of(context).pop();
      }
      if (!mounted) return;
      showErrorSnackBar(context, context.l.galleryImportFailed(e.toString()));
    }
  }

  Future<void> _importMetadataToEditor(File file) async {
    try {
      final notifier = context.read<GenerationNotifier>();
      final result = await notifier.parseImageMetadata(file);
      if (!mounted) return;
      final categories = await showImportMetadataDialog(
        context,
        result: result,
      );
      if (categories == null || !mounted) return;
      notifier.applyImportedMetadata(result, categories);
      showAppSnackBar(context, context.l.galleryMetadataImported);
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, context.l.galleryMetadataNotFound);
      }
    }
  }

  String _sortModeLabel(BuildContext context, GallerySortMode mode) {
    switch (mode) {
      case GallerySortMode.dateDesc:
        return context.l.gallerySortDateNewest.toUpperCase();
      case GallerySortMode.dateAsc:
        return context.l.gallerySortDateOldest.toUpperCase();
      case GallerySortMode.nameAsc:
        return context.l.gallerySortNameAZ.toUpperCase();
      case GallerySortMode.nameDesc:
        return context.l.gallerySortNameZA.toUpperCase();
      case GallerySortMode.sizeDesc:
        return context.l.gallerySortSizeLargest.toUpperCase();
      case GallerySortMode.sizeAsc:
        return context.l.gallerySortSizeSmallest.toUpperCase();
      case GallerySortMode.dateAddedDesc:
        return context.l.gallerySortDateAddedNewest.toUpperCase();
      case GallerySortMode.dateAddedAsc:
        return context.l.gallerySortDateAddedOldest.toUpperCase();
    }
  }

  Widget _buildAlbumStrip(GalleryNotifier gallery, bool touch) {
    final t = context.t;
    if (gallery.albums.isEmpty && !_isSelectionMode && !gallery.hasClipboard) {
      return const SizedBox.shrink();
    }

    return Container(
      height: context.hitSize + VisionMetrics.space4,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.borderSubtle)),
      ),
      child: Row(
        children: [
          // Fixed "All" chip + reorderable albums
          Expanded(
            child: ReorderableListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                elevation: 4,
                child: child,
              ),
              // Haptic marks the moment move mode engages, so a long-press
              // is distinguishable from a plain swipe (issue #20).
              onReorderStart: (_) => HapticFeedback.mediumImpact(),
              onReorder: (oldIndex, newIndex) {
                // Index 0 is "All" (not reorderable), albums start at index 1
                if (oldIndex == 0 || newIndex == 0) return;
                gallery.reorderAlbum(oldIndex - 1, newIndex - 1);
              },
              children: [
                _AlbumChip(
                  key: const ValueKey('__all__'),
                  label: context.l.galleryAll.toUpperCase(),
                  count: gallery.items.length,
                  isActive: gallery.activeAlbumId == null,
                  touch: touch,
                  onTap: () => gallery.setActiveAlbum(null),
                ),
                for (int i = 0; i < gallery.albums.length; i++)
                  _buildAlbumChip(gallery, i, touch),
              ],
            ),
          ),
          IconButton(
            tooltip: context.l.galleryNewAlbum,
            onPressed: () => _showCreateAlbumDialog(gallery),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: context.hitSize,
              height: context.hitSize,
            ),
            iconSize: VisionMetrics.iconMedium,
            color: t.textDisabled,
            icon: const Icon(Icons.add),
          ),
          if (gallery.hasClipboard)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VisionMetrics.space4,
              ),
              child: AppPill(
                text: context.l.galleryCopiedCount(gallery.clipboard.length),
                tone: AppTone.success,
                onTap: () => _showClipboardMenu(gallery),
              ),
            ),
        ],
      ),
    );
  }

  /// Album chip wired for issue #20's interaction model: tap selects, a tap
  /// on the already-selected album opens rename/delete, and reordering only
  /// starts from a long-press on touch layouts so a plain horizontal swipe
  /// scrolls the strip. Desktop keeps the immediate mouse drag.
  Widget _buildAlbumChip(GalleryNotifier gallery, int i, bool touch) {
    final album = gallery.albums[i];
    final chip = _AlbumChip(
      label: album.name,
      count: gallery.albumItemCount(album.id),
      isActive: gallery.activeAlbumId == album.id,
      touch: touch,
      onTap: () {
        if (gallery.activeAlbumId == album.id) {
          _showAlbumOptionsDialog(gallery, album.id, album.name);
        } else {
          gallery.setActiveAlbum(album.id);
        }
      },
    );
    return touch
        ? ReorderableDelayedDragStartListener(
            key: ValueKey(album.id),
            index: i + 1,
            child: chip,
          )
        : ReorderableDragStartListener(
            key: ValueKey(album.id),
            index: i + 1,
            child: chip,
          );
  }

  void _showClipboardMenu(GalleryNotifier gallery) {
    showAppSheet<void>(
      context: context,
      builder: (ctx) {
        final t = ctx.t;
        final l = ctx.l;
        final touch = windowSizeClassOf(ctx).isTouchSized;
        return AppPickerSheet(
          title: l.galleryImagesCopiedCount(gallery.clipboard.length),
          child: Column(
            children: [
              for (final album in gallery.albums)
                ListTile(
                  leading: Icon(
                    Icons.paste,
                    size: VisionMetrics.iconMedium,
                    color: t.accentSuccess,
                  ),
                  title: Text(
                    l.galleryPasteInto(album.name).toUpperCase(),
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: t.fontSize(touch ? 13 : 11),
                    ),
                  ),
                  onTap: () {
                    final pasteCount = gallery.clipboard.length;
                    gallery.pasteToAlbum(album.id);
                    Navigator.pop(ctx);
                    showAppSnackBar(
                      context,
                      l.galleryPastedIntoAlbum(pasteCount, album.name),
                    );
                  },
                ),
              ListTile(
                leading: Icon(
                  Icons.clear,
                  size: VisionMetrics.iconMedium,
                  color: t.accentDanger,
                ),
                title: Text(
                  l.galleryClearClipboard.toUpperCase(),
                  style: TextStyle(
                    color: t.accentDanger,
                    fontSize: t.fontSize(touch ? 13 : 11),
                  ),
                ),
                onTap: () {
                  gallery.clearClipboard();
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCreateAlbumDialog(GalleryNotifier gallery) async {
    final name = await showTextInputDialog(
      context,
      title: context.l.galleryNewAlbum.toUpperCase(),
      confirmLabel: context.l.commonCreate,
      hintText: context.l.galleryAlbumName.toUpperCase(),
    );
    if (name != null) gallery.createAlbum(name);
  }

  void _showAlbumOptionsDialog(
    GalleryNotifier gallery,
    String albumId,
    String currentName,
  ) {
    showAppSheet<void>(
      context: context,
      builder: (ctx) {
        final t = ctx.t;
        final l = ctx.l;
        return AppPickerSheet(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  Icons.edit,
                  size: VisionMetrics.iconMedium,
                  color: t.textSecondary,
                ),
                title: Text(
                  l.commonRename.toUpperCase(),
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: t.fontSize(11),
                    letterSpacing: 1,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRenameAlbumDialog(gallery, albumId, currentName);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  size: VisionMetrics.iconMedium,
                  color: t.accentDanger,
                ),
                title: Text(
                  l.commonDelete.toUpperCase(),
                  style: TextStyle(
                    color: t.accentDanger,
                    fontSize: t.fontSize(11),
                    letterSpacing: 1,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteAlbum(gallery, albumId, currentName);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteAlbum(
    GalleryNotifier gallery,
    String albumId,
    String name,
  ) async {
    final confirm = await showConfirmDialog(
      context,
      title: context.l.galleryDeleteAlbumTitle(name),
      message: context.l.galleryDeleteAlbumMessage,
      confirmLabel: context.l.commonDelete,
      cancelLabel: context.l.commonCancel,
    );
    if (confirm == true) gallery.deleteAlbum(albumId);
  }

  Future<void> _showRenameAlbumDialog(
    GalleryNotifier gallery,
    String albumId,
    String currentName,
  ) async {
    final name = await showTextInputDialog(
      context,
      title: context.l.galleryRenameAlbum.toUpperCase(),
      confirmLabel: context.l.commonRename,
      initialValue: currentName,
    );
    if (name != null) gallery.renameAlbum(albumId, name);
  }

  void _showAddToAlbumDialog(List<GalleryItem> selectedItems) {
    final gallery = context.read<GalleryNotifier>();
    final currentAlbumId = gallery.activeAlbumId;

    if (gallery.albums.isEmpty) {
      // Offer to create one
      _showCreateAlbumDialog(gallery);
      return;
    }

    showAppSheet<void>(
      context: context,
      builder: (ctx) => AppPickerSheet(
        child: _AddToAlbumSheet(
          gallery: gallery,
          selectedItems: selectedItems,
          currentAlbumId: currentAlbumId,
          onDone: () {
            Navigator.pop(ctx);
            _exitSelectionMode();
          },
          onCreateAlbum: () {
            Navigator.pop(ctx);
            _showCreateAlbumDialog(gallery);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final gallery = context.watch<GalleryNotifier>();
    final touch = windowSizeClassOf(context).isTouchSized;
    final maxCols = touch ? 4 : 8;
    final minCols = touch ? 2 : 3;
    final activeItems = gallery.activeItems;

    return Focus(
      focusNode: _galleryFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          if (_isSearching) {
            setState(() {
              _isSearching = false;
              _searchController.clear();
              context.read<GalleryNotifier>().setSearchQuery("");
            });
            return KeyEventResult.handled;
          }
          if (_isSelectionMode) {
            _exitSelectionMode();
            return KeyEventResult.handled;
          }
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.delete &&
            _isSelectionMode &&
            _selectedIndices.isNotEmpty) {
          final selectedItems = _selectedIndices
              .where((i) => i < activeItems.length)
              .map((i) => activeItems[i])
              .toList();
          if (selectedItems.isNotEmpty) _bulkDelete(selectedItems);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: t.background,
        appBar: _buildAppBar(gallery, activeItems, touch, maxCols, minCols),
        body: Column(
          children: [
            // Album strip
            _buildAlbumStrip(gallery, touch),
            // Grid content
            Expanded(
              child: gallery.isLoading
                  ? const LoadingState()
                  : activeItems.isEmpty
                  ? EmptyState(
                      icon: Icons.photo_library_outlined,
                      message: gallery.demoMode
                          ? context.l.galleryNoDemoImages
                          : gallery.showFavoritesOnly
                          ? context.l.galleryNoFavorites
                          : gallery.activeAlbumId != null
                          ? context.l.galleryNoImagesInAlbum
                          : context.l.galleryNoImagesFound,
                    )
                  : Stack(
                      children: [
                        _buildGrid(activeItems, touch),
                        // Desktop drag rectangle overlay
                        if (_isRectDragging &&
                            _dragStart != null &&
                            _dragCurrent != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _DragRectPainter(
                                  start: _dragStart!,
                                  end: _dragCurrent!,
                                  color: t.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        // Bulk action bar
                        if (_isSelectionMode) _buildBulkActionBar(activeItems),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    GalleryNotifier gallery,
    List<GalleryItem> items,
    bool touch,
    int maxCols,
    int minCols,
  ) {
    final t = context.t;
    if (_isSelectionMode) {
      return AppBar(
        backgroundColor: t.background,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: touch ? 56 : 40,
        leading: IconButton(
          icon: Icon(
            Icons.close,
            size: touch ? 22 : 16,
            color: t.textSecondary,
          ),
          onPressed: _exitSelectionMode,
        ),
        title: Text(
          context.l.gallerySelectedCount(_selectedIndices.length).toUpperCase(),
          style: TextStyle(
            letterSpacing: 2,
            fontSize: touch ? t.fontSize(14) : t.fontSize(10),
            fontWeight: FontWeight.w900,
            color: t.textSecondary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _selectedIndices.length == items.length
                  ? Icons.deselect
                  : Icons.select_all,
              size: touch ? 22 : 16,
              color: t.textDisabled,
            ),
            tooltip: _selectedIndices.length == items.length
                ? context.l.galleryDeselectAll
                : context.l.gallerySelectAll,
            onPressed: () => _selectAll(items),
          ),
        ],
      );
    }

    return AppBar(
      title: _isSearching
          ? (touch
                ? null
                : TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: TextStyle(color: t.accent, fontSize: t.fontSize(12)),
                    decoration: InputDecoration(
                      hintText: context.l.gallerySearchTags.toUpperCase(),
                      hintStyle: TextStyle(
                        color: t.textDisabled,
                        fontSize: t.fontSize(10),
                        letterSpacing: 2,
                      ),
                      border: InputBorder.none,
                    ),
                    onChanged: (value) => gallery.setSearchQuery(value),
                  ))
          : (touch
                ? null
                : Text(
                    (gallery.demoMode
                            ? context.l.galleryDemoTitle
                            : context.l.galleryTitle)
                        .toUpperCase(),
                    style: TextStyle(
                      letterSpacing: 4,
                      fontSize: t.fontSize(10),
                      fontWeight: FontWeight.w900,
                      color: t.textSecondary,
                    ),
                  )),
      bottom: (touch && _isSearching)
          ? PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(color: t.accent, fontSize: t.fontSize(14)),
                  decoration: InputDecoration(
                    hintText: context.l.gallerySearchTags.toUpperCase(),
                    hintStyle: TextStyle(
                      color: t.textDisabled,
                      fontSize: t.fontSize(12),
                      letterSpacing: 2,
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: (value) => gallery.setSearchQuery(value),
                ),
              ),
            )
          : null,
      backgroundColor: t.background,
      elevation: 0,
      centerTitle: true,
      toolbarHeight: touch ? 56 : 40,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios,
          size: touch ? 20 : 14,
          color: t.textDisabled,
        ),
        onPressed: () {
          if (_isSearching) {
            setState(() {
              _isSearching = false;
              _searchController.clear();
              gallery.setSearchQuery("");
            });
          } else {
            Navigator.pop(context);
          }
        },
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.add_photo_alternate,
            size: touch ? 22 : 16,
            color: t.secondaryText,
          ),
          tooltip: context.l.galleryImport,
          onPressed: _importImages,
        ),
        IconButton(
          icon: Icon(
            gallery.showFavoritesOnly ? Icons.star : Icons.star_outline,
            size: touch ? 22 : 16,
            color: gallery.showFavoritesOnly
                ? t.accentFavorite
                : t.secondaryText,
          ),
          tooltip: context.l.galleryFavoritesFilter,
          onPressed: () {
            gallery.showFavoritesOnly = !gallery.showFavoritesOnly;
          },
        ),
        PopupMenuButton<GallerySortMode>(
          icon: Icon(Icons.sort, size: touch ? 20 : 16, color: t.secondaryText),
          tooltip: context.l.gallerySort,
          color: t.surfaceHigh,
          onSelected: (mode) => gallery.setSortMode(mode),
          itemBuilder: (context) => [
            for (final mode in GallerySortMode.values)
              PopupMenuItem(
                value: mode,
                child: Row(
                  children: [
                    if (gallery.sortMode == mode)
                      Icon(Icons.check, size: 14, color: t.accent)
                    else
                      const SizedBox(width: 14),
                    const SizedBox(width: 8),
                    Text(
                      _sortModeLabel(context, mode),
                      style: TextStyle(
                        color: gallery.sortMode == mode
                            ? t.accent
                            : t.textSecondary,
                        fontSize: t.fontSize(touch ? 12 : 10),
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        IconButton(
          icon: Icon(
            Icons.checklist,
            size: touch ? 20 : 16,
            color: t.secondaryText,
          ),
          tooltip: context.l.gallerySelectMode,
          onPressed: () {
            setState(() {
              _isSelectionMode = true;
            });
          },
        ),
        IconButton(
          icon: Icon(
            Icons.grid_view,
            size: touch ? 20 : 16,
            color: t.secondaryText,
          ),
          tooltip: context.l.galleryColumnsCount(_crossAxisCount!),
          onPressed: () {
            setState(() {
              _crossAxisCount = _crossAxisCount! >= maxCols
                  ? minCols
                  : _crossAxisCount! + 1;
            });
            context.read<PreferencesService>().setGalleryGridColumns(
              _crossAxisCount!,
            );
          },
        ),
        IconButton(
          icon: Icon(
            _isSearching ? Icons.close : Icons.search,
            size: touch ? 20 : 16,
            color: t.secondaryText,
          ),
          onPressed: () {
            setState(() {
              if (_isSearching) {
                _searchController.clear();
                gallery.setSearchQuery("");
              }
              _isSearching = !_isSearching;
            });
          },
        ),
      ],
    );
  }

  /// Gap between the floating bulk action bar and the bottom edge.
  double _bulkBarBottom(bool touch) =>
      touch ? MediaQuery.paddingOf(context).bottom + 16 : 16;

  Widget _buildGrid(List<GalleryItem> items, bool touch) {
    final bottomInset = galleryGridBottomInset(
      safeAreaBottom: MediaQuery.paddingOf(context).bottom,
      actionBarExtent: _isSelectionMode
          ? _bulkBarBottom(touch) + _bulkBarHeight
          : 0,
    );
    final grid = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: bottomInset),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (context, bottomInset, _) => GridView.builder(
        key: _gridKey,
        controller: _scrollController,
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          top: 8,
          bottom: bottomInset,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _crossAxisCount!,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => _buildGridItem(items, index, touch),
      ),
    );

    late final Widget content;
    if (touch) {
      content = GestureDetector(
        onLongPressStart: (details) {
          final idx = _cellIndexFromOffset(details.localPosition, items.length);
          if (idx != null) {
            setState(() {
              _isDragging = true;
              if (!_isSelectionMode) {
                _isSelectionMode = true;
                _selectedIndices.clear();
              }
              _dragSelectedIndices.clear();
              _dragSelectedIndices.add(idx);
              _selectedIndices.add(idx);
            });
          }
        },
        onLongPressMoveUpdate: (details) {
          if (!_isDragging) return;
          final idx = _cellIndexFromOffset(details.localPosition, items.length);
          if (idx != null && !_dragSelectedIndices.contains(idx)) {
            setState(() {
              _dragSelectedIndices.add(idx);
              _selectedIndices.add(idx);
            });
          }
        },
        onLongPressEnd: (_) {
          setState(() {
            _isDragging = false;
            _dragSelectedIndices.clear();
          });
        },
        child: grid,
      );
    } else {
      // Desktop: rectangle drag selection
      content = GestureDetector(
        onPanStart: _isSelectionMode
            ? (details) {
                setState(() {
                  _isRectDragging = true;
                  _dragStart = details.localPosition;
                  _dragCurrent = details.localPosition;
                });
              }
            : null,
        onPanUpdate: _isSelectionMode
            ? (details) {
                if (!_isRectDragging) return;
                setState(() {
                  _dragCurrent = details.localPosition;
                });
                // Live selection feedback
                final indices = _indicesInRect(
                  _dragStart!,
                  _dragCurrent!,
                  items.length,
                );
                setState(() {
                  _dragSelectedIndices
                    ..clear()
                    ..addAll(indices);
                });
              }
            : null,
        onPanEnd: _isSelectionMode
            ? (_) {
                setState(() {
                  _selectedIndices.addAll(_dragSelectedIndices);
                  _dragSelectedIndices.clear();
                  _isRectDragging = false;
                  _dragStart = null;
                  _dragCurrent = null;
                });
              }
            : null,
        child: grid,
      );
    }

    // Draggable scrollbar: at thousands of images, flinging is the only way
    // to travel without one (issue #19). Persistent so the thumb is already
    // there when the user reaches for it, and thick enough to grab on touch.
    return RawScrollbar(
      controller: _scrollController,
      interactive: true,
      thumbVisibility: true,
      thickness: touch ? 12 : 8,
      radius: const Radius.circular(6),
      minThumbLength: 48,
      crossAxisMargin: 2,
      mainAxisMargin: 4,
      thumbColor: context.t.accent.withValues(alpha: 0.55),
      child: content,
    );
  }

  Widget _buildGridItem(List<GalleryItem> items, int index, bool touch) {
    final t = context.t;
    final item = items[index];
    final isSelected =
        _selectedIndices.contains(index) ||
        _dragSelectedIndices.contains(index);
    final showInfo = _hoveredIndex == index && !_isSelectionMode;

    Widget tile = Container(
      decoration: BoxDecoration(
        color: t.borderSubtle,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected ? t.accent : t.borderSubtle,
          width: isSelected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            item.file,
            fit: BoxFit.cover,
            // Cap thumbnail decode size — grid tiles never need full
            // resolution, and full-res decodes of large PNGs are what made
            // scrolling big galleries heavy.
            cacheWidth: 512,
            // A corrupted file (failed generation, interrupted write) must
            // degrade to a placeholder, not error the whole grid (issue #24).
            errorBuilder: (context, error, stackTrace) => Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: 24,
                color: t.textMinimal,
              ),
            ),
          ),
          // Dim overlay when selected
          if (isSelected) Container(color: t.background.withValues(alpha: 0.3)),
          // Info overlay on hover / long-press
          if (showInfo)
            Positioned.fill(
              child: Container(
                color: t.background.withValues(alpha: 0.75),
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (item.prompt != null && item.prompt!.isNotEmpty)
                      Text(
                        item.prompt!.length > 60
                            ? '${item.prompt!.substring(0, 60)}...'
                            : item.prompt!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: t.fontSize(touch ? 10 : 8),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      item.basename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textDisabled,
                        fontSize: t.fontSize(touch ? 8 : 7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Favorite star badge (top-left)
          if (item.isFavorite)
            Positioned(
              top: 4,
              left: 4,
              child: Icon(
                Icons.star,
                size: touch ? 18 : 14,
                color: t.accentFavorite,
              ),
            ),
          // Canvas layers badge (bottom-left)
          if (item.hasCanvasState)
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: t.accentEdit.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.palette,
                  size: touch ? 16 : 13,
                  color: t.textPrimary,
                ),
              ),
            ),
          // Selection checkmark (top-right)
          if (_isSelectionMode)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: touch ? 24 : 20,
                height: touch ? 24 : 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? t.accent
                      : t.background.withValues(alpha: 0.5),
                  border: Border.all(
                    color: isSelected
                        ? t.accent
                        : t.accent.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: touch ? 14 : 12,
                        color: t.background,
                      )
                    : null,
              ),
            ),
        ],
      ),
    );

    // Wrap with hover detection on desktop
    if (!touch) {
      tile = MouseRegion(
        onEnter: (_) => setState(() => _hoveredIndex = index),
        onExit: (_) => setState(() => _hoveredIndex = null),
        child: tile,
      );
    }

    return GestureDetector(
      onTap: () {
        if (_isSelectionMode || HardwareKeyboard.instance.isShiftPressed) {
          if (!_isSelectionMode) {
            setState(() => _isSelectionMode = true);
          }
          _toggleSelection(index);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ImageDetailView(initialIndex: index),
            ),
          );
        }
      },
      onLongPress: touch
          ? null // Handled by parent GestureDetector for drag support
          : () {
              if (!_isSelectionMode) {
                _enterSelectionMode(index);
              }
            },
      child: tile,
    );
  }

  /// The label of a tool NovelAI charges for, with the most it can cost for
  /// [count] images.
  String _withCap(String label, PaidTool tool, int count) {
    final cap = paidToolCapLabel(context, tool, count: max(1, count));
    return (cap == null ? label : '$label · $cap').toUpperCase();
  }

  Widget _buildBulkActionBar(List<GalleryItem> items) {
    final t = context.t;
    final touch = windowSizeClassOf(context).isTouchSized;
    final gallery = context.watch<GalleryNotifier>();
    final selectedItems = _selectedIndices
        .where((i) => i < items.length)
        .map((i) => items[i])
        .toList();
    final count = _selectedIndices.length;
    final l = context.l;
    final ml = context.read<MLNotifier>();
    final naiUpscaleOffered = isNovelAiImageActionOffered(
      context,
      NovelAiImageAction.upscale,
    );
    Widget action(
      IconData icon,
      String label,
      Color color,
      VoidCallback? onTap,
    ) => OverlayActionButton(
      icon: icon,
      tooltip: label,
      color: color,
      onPressed: onTap,
    );

    return Positioned(
      left: VisionMetrics.space16,
      right: VisionMetrics.space16,
      bottom: _bulkBarBottom(touch),
      child: HeightReporter(
        onHeight: (height) {
          if (mounted && height != _bulkBarHeight) {
            setState(() => _bulkBarHeight = height);
          }
        },
        child: AnimatedSlide(
          offset: count > 0 ? Offset.zero : const Offset(0, 2),
          duration: const Duration(milliseconds: 200),
          child: AnimatedOpacity(
            opacity: count > 0 ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(VisionMetrics.radius4),
                boxShadow: [
                  BoxShadow(
                    color: t.background.withValues(
                      alpha: VisionMetrics.opacityOverlay,
                    ),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AppPanel(
                variant: AppPanelVariant.raised,
                padding: const EdgeInsets.symmetric(
                  horizontal: VisionMetrics.space8,
                  vertical: VisionMetrics.space4,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: VisionMetrics.space4,
                    children: [
                      if (count == 2)
                        action(Icons.compare, l.galleryCompare, t.accent, () {
                          final sorted = _selectedIndices.toList()..sort();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ComparisonView(
                                itemA: items[sorted[0]],
                                itemB: items[sorted[1]],
                              ),
                            ),
                          );
                        }),
                      action(
                        Icons.copy,
                        l.galleryCopy,
                        t.accent,
                        count > 0
                            ? () {
                                gallery.copyToClipboard(selectedItems);
                                showAppSnackBar(
                                  context,
                                  l.galleryImagesCopied(selectedItems.length),
                                  color: t.accent,
                                );
                                _exitSelectionMode();
                              }
                            : null,
                      ),
                      if (gallery.hasClipboard && gallery.activeAlbumId != null)
                        action(
                          Icons.paste,
                          l.galleryPaste,
                          t.accentSuccess,
                          () {
                            final pasteCount = gallery.clipboard.length;
                            gallery.pasteToAlbum(gallery.activeAlbumId!);
                            showAppSnackBar(
                              context,
                              l.galleryImagesPasted(pasteCount),
                            );
                          },
                        ),
                      action(
                        Icons.photo_album,
                        l.galleryAlbum,
                        t.accent,
                        count > 0
                            ? () => _showAddToAlbumDialog(selectedItems)
                            : null,
                      ),
                      action(
                        Icons.save_alt,
                        l.commonExport,
                        t.accent,
                        count > 0 ? () => _bulkExport(selectedItems) : null,
                      ),
                      if (ml.hasBgRemovalModel)
                        action(
                          Icons.content_cut,
                          l.mlRemoveBg,
                          t.accent,
                          count > 0 ? () => _bulkRemoveBg(selectedItems) : null,
                        ),
                      if (ml.hasUpscaleModel)
                        action(
                          Icons.zoom_out_map,
                          l.mlUpscale,
                          t.accent,
                          count > 0 ? () => _bulkUpscale(selectedItems) : null,
                        ),
                      if (naiUpscaleOffered)
                        action(
                          Icons.cloud_upload_outlined,
                          _withCap(l.naiUpscale, PaidTool.upscale, count),
                          t.accentEdit,
                          count > 0
                              ? () => _bulkNaiUpscale(
                                  selectedItems,
                                  permissionGranted:
                                      hasNovelAiImageActionPermission(
                                        context,
                                        NovelAiImageAction.upscale,
                                      ),
                                )
                              : null,
                        ),
                      if (ml.selectedSegmentationModelId != null && count == 1)
                        action(
                          Icons.auto_awesome,
                          l.mlSegment,
                          t.accent,
                          () => _openSegmentation(selectedItems.first),
                        ),
                      // Send to Canvas (single image)
                      if (count == 1)
                        action(
                          Icons.brush,
                          l.mlCanvas,
                          t.accentEdit,
                          () => _openInCanvas(selectedItems.first),
                        ),
                      action(
                        Icons.star,
                        l.galleryFavorite,
                        t.accentFavorite,
                        count > 0 ? () => _bulkFavorite(selectedItems) : null,
                      ),
                      // Remove from album (only when viewing an album)
                      if (gallery.activeAlbumId != null)
                        action(
                          Icons.playlist_remove,
                          l.galleryRemove,
                          t.secondaryText,
                          count > 0
                              ? () => _bulkRemoveFromAlbum(selectedItems)
                              : null,
                        ),
                      action(
                        Icons.delete_outline,
                        l.commonDelete,
                        t.accentDanger,
                        count > 0 ? () => _bulkDelete(selectedItems) : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isActive;
  final bool touch;
  final VoidCallback onTap;

  const _AlbumChip({
    super.key,
    required this.label,
    required this.count,
    required this.isActive,
    required this.touch,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ActionChip(
        label: Text(
          '$label ($count)',
          style: TextStyle(
            color: isActive ? t.background : t.textSecondary,
            fontSize: t.fontSize(touch ? 10 : 8),
            letterSpacing: 1,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        backgroundColor: isActive ? t.accent : t.borderSubtle,
        side: BorderSide(color: isActive ? t.accent : t.borderMedium),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: EdgeInsets.symmetric(horizontal: touch ? 8 : 4),
        onPressed: onTap,
      ),
    );
  }
}

class _DragRectPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;

  _DragRectPainter({
    required this.start,
    required this.end,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    final fillPaint = Paint()
      ..color = color.withValues(alpha: VisionMetrics.opacityHover)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = color.withValues(alpha: VisionMetrics.opacityDisabled)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(rect, fillPaint);
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(_DragRectPainter oldDelegate) =>
      start != oldDelegate.start ||
      end != oldDelegate.end ||
      color != oldDelegate.color;
}

class _AddToAlbumSheet extends StatefulWidget {
  final GalleryNotifier gallery;
  final List<GalleryItem> selectedItems;
  final String? currentAlbumId;
  final VoidCallback onDone;
  final VoidCallback onCreateAlbum;

  const _AddToAlbumSheet({
    required this.gallery,
    required this.selectedItems,
    required this.currentAlbumId,
    required this.onDone,
    required this.onCreateAlbum,
  });

  @override
  State<_AddToAlbumSheet> createState() => _AddToAlbumSheetState();
}

class _AddToAlbumSheetState extends State<_AddToAlbumSheet> {
  bool _moveMode = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final touch = windowSizeClassOf(context).isTouchSized;
    final showMoveToggle = widget.currentAlbumId != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          (_moveMode ? l.galleryMoveToAlbum : l.galleryAddToAlbum)
              .toUpperCase(),
          t: t,
          trailing: showMoveToggle
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: VisionMetrics.space4,
                  children: [
                    Text(
                      l.galleryMove.toUpperCase(),
                      style: TextStyle(
                        color: _moveMode ? t.accent : t.textDisabled,
                        fontSize: t.fontSize(touch ? 10 : 8),
                        letterSpacing: 1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Switch(
                      value: _moveMode,
                      onChanged: (v) => setState(() => _moveMode = v),
                      activeTrackColor: t.accent,
                    ),
                  ],
                )
              : null,
        ),
        for (final album in widget.gallery.albums)
          if (album.id != widget.currentAlbumId)
            ListTile(
              leading: Icon(
                Icons.photo_album,
                size: VisionMetrics.iconMedium,
                color: t.textDisabled,
              ),
              title: Text(
                album.name,
                style: TextStyle(
                  color: t.textSecondary,
                  fontSize: t.fontSize(touch ? 13 : 11),
                ),
              ),
              trailing: Text(
                '${widget.gallery.albumItemCount(album.id)}',
                style: TextStyle(
                  color: t.textDisabled,
                  fontSize: t.fontSize(touch ? 11 : 9),
                ),
              ),
              onTap: () {
                widget.gallery.addToAlbum(album.id, widget.selectedItems);
                if (_moveMode && widget.currentAlbumId != null) {
                  widget.gallery.removeFromAlbum(
                    widget.currentAlbumId!,
                    widget.selectedItems,
                  );
                }
                widget.onDone();
              },
            ),
        ListTile(
          leading: Icon(
            Icons.add,
            size: VisionMetrics.iconMedium,
            color: t.accent,
          ),
          title: Text(
            l.galleryNewAlbum.toUpperCase(),
            style: TextStyle(
              color: t.accent,
              fontSize: t.fontSize(touch ? 13 : 11),
            ),
          ),
          onTap: widget.onCreateAlbum,
        ),
      ],
    );
  }
}
