import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/quick_action_overlay.dart';
import '../providers/generation_notifier.dart';
import 'result_set_viewer.dart';

enum ResultSetWorkspaceMode { grid, viewer }

class ResultSetGridSpec {
  static const padding = 12.0;
  static const spacing = 10.0;
  static const maxCardExtent = 240.0;
  static const cardAspectRatio = 1.0;

  static const delegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: maxCardExtent,
    crossAxisSpacing: spacing,
    mainAxisSpacing: spacing,
    childAspectRatio: cardAspectRatio,
  );

  static int columnCount(double viewportWidth) {
    final contentWidth = math.max(0.0, viewportWidth - padding * 2);
    return math.max(1, (contentWidth / (maxCardExtent + spacing)).ceil());
  }

  static double rowExtent(double viewportWidth) {
    final contentWidth = math.max(0.0, viewportWidth - padding * 2);
    final columns = columnCount(viewportWidth);
    final cardWidth =
        (contentWidth - spacing * math.max(0, columns - 1)) / columns;
    return cardWidth / cardAspectRatio + spacing;
  }
}

ResultSetViewItem _viewItemFor(GeneratedImageItem item) {
  final bytes = item.bytes;
  final failed =
      item.progress == GenerationTaskProgress.failed ||
      item.progress == GenerationTaskProgress.rejected ||
      item.progress == GenerationTaskProgress.cancelled;
  return ResultSetViewItem(
    id: item.id,
    position: item.batchIndex,
    count: item.batchCount,
    previewImage: bytes == null ? null : MemoryImage(bytes),
    thumbnailImage: bytes == null ? null : MemoryImage(bytes),
    imageBytes: bytes,
    seed: item.seed,
    isLoading: item.isLoading,
    isGenerating: item.progress == GenerationTaskProgress.generating,
    errorMessage: failed ? item.errorMessage ?? 'Generation failed' : null,
  );
}

class GenerationResultsWorkspace extends StatefulWidget {
  final GenerationNotifier notifier;
  final GenerationState state;
  final bool mobile;
  final Animation<double> pulseAnimation;
  final bool showQuickActions;
  final ValueChanged<String>? onSelectImage;

  const GenerationResultsWorkspace({
    super.key,
    required this.notifier,
    required this.state,
    required this.mobile,
    required this.pulseAnimation,
    this.showQuickActions = true,
    this.onSelectImage,
  });

  @override
  State<GenerationResultsWorkspace> createState() =>
      _GenerationResultsWorkspaceState();
}

class _GenerationResultsWorkspaceState
    extends State<GenerationResultsWorkspace> {
  @override
  Widget build(BuildContext context) {
    final images = widget.state.generatedImages;
    final onSelect =
        widget.onSelectImage ?? widget.notifier.selectGeneratedImage;
    final viewItems = images.map(_viewItemFor).toList();
    if (viewItems.isEmpty && widget.state.generatedImage != null) {
      viewItems.add(
        ResultSetViewItem(
          id: widget.state.selectedGeneratedImageId ?? 'single-result',
          position: 1,
          count: 1,
          previewImage: MemoryImage(widget.state.generatedImage!),
          thumbnailImage: MemoryImage(widget.state.generatedImage!),
          imageBytes: widget.state.generatedImage!,
          isLoading: widget.state.isLoading,
        ),
      );
    }
    return ResultSetWorkspace(
      items: viewItems,
      selectedId: widget.state.selectedGeneratedImageId,
      onSelect: onSelect,
      mobile: widget.mobile,
      pulseAnimation: widget.pulseAnimation,
      isDragging: widget.state.isDragging,
      previewOverlay:
          widget.showQuickActions && widget.state.generatedImage != null
          ? const QuickActionOverlay()
          : null,
    );
  }
}

/// Shared batch presentation used by both the generation page and history.
///
/// It owns the grid/viewer mode, selection affordance and mode toolbar so a
/// batch behaves identically regardless of where it was opened.
class ResultSetWorkspace extends StatefulWidget {
  const ResultSetWorkspace({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.mobile,
    required this.pulseAnimation,
    this.isDragging = false,
    this.previewOverlay,
    this.headerLeading,
    this.headerTrailingBuilder,
    this.gridItemTrailingBuilder,
    this.initialMode = ResultSetWorkspaceMode.grid,
  });

  final List<ResultSetViewItem> items;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final bool mobile;
  final Animation<double> pulseAnimation;
  final bool isDragging;
  final Widget? previewOverlay;
  final Widget? headerLeading;
  final Widget Function(BuildContext, ResultSetWorkspaceMode)?
  headerTrailingBuilder;
  final Widget Function(BuildContext, ResultSetViewItem)?
  gridItemTrailingBuilder;
  final ResultSetWorkspaceMode initialMode;

  @override
  State<ResultSetWorkspace> createState() => _ResultSetWorkspaceState();
}

class _ResultSetWorkspaceState extends State<ResultSetWorkspace> {
  late ResultSetWorkspaceMode _mode = widget.initialMode;

  @override
  void didUpdateWidget(ResultSetWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSetId = oldWidget.items.firstOrNull?.id;
    final newSetId = widget.items.firstOrNull?.id;
    if (widget.items.length > 1 &&
        (oldWidget.items.length <= 1 || oldSetId != newSetId)) {
      _mode = widget.initialMode;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResultSet = widget.items.length > 1;
    final showGrid = hasResultSet && _mode == ResultSetWorkspaceMode.grid;
    final displayedMode = showGrid
        ? ResultSetWorkspaceMode.grid
        : ResultSetWorkspaceMode.viewer;
    final headerTrailing = widget.headerTrailingBuilder?.call(
      context,
      displayedMode,
    );
    final showHeader =
        hasResultSet || widget.headerLeading != null || headerTrailing != null;

    return Column(
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                if (widget.headerLeading != null) ...[
                  widget.headerLeading!,
                  const SizedBox(width: 8),
                ],
                if (hasResultSet)
                  _ResultsToolbar(
                    mode: _mode,
                    items: widget.items,
                    selectedId: widget.selectedId,
                    onModeChanged: (mode) => setState(() => _mode = mode),
                  ),
                const Spacer(),
                if (headerTrailing != null) headerTrailing,
              ],
            ),
          ),
        Expanded(
          child: showGrid
              ? _ResultsGrid(
                  items: widget.items,
                  selectedId: widget.selectedId,
                  onSelect: widget.onSelect,
                  trailingBuilder: widget.gridItemTrailingBuilder,
                  onOpen: (id) {
                    widget.onSelect(id);
                    setState(() => _mode = ResultSetWorkspaceMode.viewer);
                  },
                )
              : ResultSetViewer(
                  items: widget.items,
                  selectedId: widget.selectedId,
                  onSelect: widget.onSelect,
                  mobile: widget.mobile,
                  pulseAnimation: widget.pulseAnimation,
                  isDragging: widget.isDragging,
                  previewOverlay: widget.previewOverlay,
                ),
        ),
      ],
    );
  }
}

class _ResultsToolbar extends StatelessWidget {
  final ResultSetWorkspaceMode mode;
  final List<ResultSetViewItem> items;
  final String? selectedId;
  final ValueChanged<ResultSetWorkspaceMode> onModeChanged;

  const _ResultsToolbar({
    required this.mode,
    required this.items,
    required this.selectedId,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final selectedIndex = items.indexWhere((item) => item.id == selectedId);
    final completeCount = items.where((item) => item.hasImage).length;
    final countLabel = selectedIndex >= 0
        ? '${selectedIndex + 1}/${items.length}'
        : '$completeCount/${items.length}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surfaceHigh.withValues(alpha: 0.92),
        border: Border.all(color: t.borderMedium),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            selected: mode == ResultSetWorkspaceMode.grid,
            icon: Icons.grid_view_rounded,
            tooltip: l.mainResultsGrid,
            onTap: () => onModeChanged(ResultSetWorkspaceMode.grid),
          ),
          _ModeButton(
            selected: mode == ResultSetWorkspaceMode.viewer,
            icon: Icons.image_outlined,
            tooltip: l.mainResultsViewer,
            onTap: () => onModeChanged(ResultSetWorkspaceMode.viewer),
          ),
          Container(width: 1, height: 18, color: t.borderMedium),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              countLabel,
              style: TextStyle(
                color: t.textSecondary,
                fontSize: t.fontSize(10),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ModeButton({
    required this.selected,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = selected ? t.background : t.textTertiary;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? t.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}

class _ResultsGrid extends StatelessWidget {
  final List<ResultSetViewItem> items;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onOpen;
  final Widget Function(BuildContext, ResultSetViewItem)? trailingBuilder;

  const _ResultsGrid({
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.onOpen,
    this.trailingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          padding: const EdgeInsets.all(ResultSetGridSpec.padding),
          gridDelegate: ResultSetGridSpec.delegate,
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _ResultSetGridTile(
              item: item,
              selected: item.id == selectedId,
              onSelect: () => onSelect(item.id),
              onOpen: item.hasImage ? () => onOpen(item.id) : null,
              trailing: trailingBuilder?.call(context, item),
            );
          },
        );
      },
    );
  }
}

class _ResultSetGridTile extends StatefulWidget {
  const _ResultSetGridTile({
    required this.item,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.trailing,
  });

  final ResultSetViewItem item;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onOpen;
  final Widget? trailing;

  @override
  State<_ResultSetGridTile> createState() => _ResultSetGridTileState();
}

class _ResultSetGridTileState extends State<_ResultSetGridTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final title = widget.item.infoTitle?.trim() ?? '';
    final subtitle = widget.item.infoSubtitle?.trim() ?? '';
    final showInfo = _hovered && (title.isNotEmpty || subtitle.isNotEmpty);
    Widget tile = Stack(
      children: [
        Positioned.fill(
          child: ResultSetThumbnail(
            item: widget.item,
            selected: widget.selected,
            onTap: widget.onOpen ?? widget.onSelect,
            showFooter: false,
          ),
        ),
        if (showInfo)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: t.background.withValues(alpha: 0.75),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title.isNotEmpty)
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textSecondary,
                            fontSize: t.fontSize(9),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (title.isNotEmpty && subtitle.isNotEmpty)
                        const SizedBox(height: 4),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textDisabled,
                            fontSize: t.fontSize(8),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (widget.trailing != null)
          Positioned(top: 5, right: 5, child: widget.trailing!),
      ],
    );
    if (!isMobile(context)) {
      tile = MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: tile,
      );
    }
    return tile;
  }
}
