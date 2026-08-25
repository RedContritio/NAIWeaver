import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/widgets/quick_action_overlay.dart';
import '../providers/generation_notifier.dart';
import 'result_set_viewer.dart';

enum _ResultsMode { grid, viewer }

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
  _ResultsMode _mode = _ResultsMode.grid;

  @override
  void didUpdateWidget(GenerationResultsWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCount = oldWidget.state.generatedImages.length;
    final newCount = widget.state.generatedImages.length;
    final oldSetId = oldWidget.state.generatedImages.firstOrNull?.id;
    final newSetId = widget.state.generatedImages.firstOrNull?.id;
    if (newCount > 1 && (oldCount <= 1 || oldSetId != newSetId)) {
      _mode = _ResultsMode.grid;
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.state.generatedImages;
    final onSelect =
        widget.onSelectImage ?? widget.notifier.selectGeneratedImage;
    final hasResultSet = images.length > 1;
    final showGrid = hasResultSet && _mode == _ResultsMode.grid;

    return Column(
      children: [
        if (hasResultSet)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ResultsToolbar(
                mode: _mode,
                images: images,
                selectedId: widget.state.selectedGeneratedImageId,
                onModeChanged: (mode) => setState(() => _mode = mode),
              ),
            ),
          ),
        Expanded(
          child: showGrid
              ? _ResultsGrid(
                  images: images,
                  selectedId: widget.state.selectedGeneratedImageId,
                  onSelect: onSelect,
                  onOpen: (id) {
                    onSelect(id);
                    setState(() => _mode = _ResultsMode.viewer);
                  },
                )
              : _ResultsViewer(
                  images: images,
                  state: widget.state,
                  onSelect: onSelect,
                  mobile: widget.mobile,
                  pulseAnimation: widget.pulseAnimation,
                  showQuickActions: widget.showQuickActions,
                ),
        ),
      ],
    );
  }
}

class _ResultsToolbar extends StatelessWidget {
  final _ResultsMode mode;
  final List<GeneratedImageItem> images;
  final String? selectedId;
  final ValueChanged<_ResultsMode> onModeChanged;

  const _ResultsToolbar({
    required this.mode,
    required this.images,
    required this.selectedId,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final l = context.l;
    final selectedIndex = images.indexWhere((item) => item.id == selectedId);
    final completeCount = images.where((item) => item.isComplete).length;
    final countLabel = selectedIndex >= 0
        ? '${selectedIndex + 1}/${images.length}'
        : '$completeCount/${images.length}';

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
            selected: mode == _ResultsMode.grid,
            icon: Icons.grid_view_rounded,
            tooltip: l.mainResultsGrid,
            onTap: () => onModeChanged(_ResultsMode.grid),
          ),
          _ModeButton(
            selected: mode == _ResultsMode.viewer,
            icon: Icons.image_outlined,
            tooltip: l.mainResultsViewer,
            onTap: () => onModeChanged(_ResultsMode.viewer),
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
  final List<GeneratedImageItem> images;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onOpen;

  const _ResultsGrid({
    required this.images,
    required this.selectedId,
    required this.onSelect,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellMin = constraints.maxWidth < 700 ? 132.0 : 188.0;
        final count = (constraints.maxWidth / cellMin)
            .floor()
            .clamp(1, 6)
            .toInt();
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.78,
          ),
          itemCount: images.length,
          itemBuilder: (context, index) {
            final item = images[index];
            return ResultSetThumbnail(
              item: _viewItemFor(item),
              selected: item.id == selectedId,
              onTap: () => onSelect(item.id),
              onDoubleTap: item.isComplete ? () => onOpen(item.id) : null,
            );
          },
        );
      },
    );
  }
}

class _ResultsViewer extends StatelessWidget {
  final List<GeneratedImageItem> images;
  final GenerationState state;
  final ValueChanged<String> onSelect;
  final bool mobile;
  final Animation<double> pulseAnimation;
  final bool showQuickActions;

  const _ResultsViewer({
    required this.images,
    required this.state,
    required this.onSelect,
    required this.mobile,
    required this.pulseAnimation,
    required this.showQuickActions,
  });

  @override
  Widget build(BuildContext context) {
    final viewItems = images.map(_viewItemFor).toList();
    if (viewItems.isEmpty && state.generatedImage != null) {
      viewItems.add(
        ResultSetViewItem(
          id: state.selectedGeneratedImageId ?? 'single-result',
          position: 1,
          count: 1,
          previewImage: MemoryImage(state.generatedImage!),
          thumbnailImage: MemoryImage(state.generatedImage!),
          imageBytes: state.generatedImage!,
          isLoading: state.isLoading,
        ),
      );
    }
    return ResultSetViewer(
      items: viewItems,
      selectedId: state.selectedGeneratedImageId,
      onSelect: onSelect,
      mobile: mobile,
      pulseAnimation: pulseAnimation,
      isDragging: state.isDragging,
      previewOverlay: showQuickActions && state.generatedImage != null
          ? const QuickActionOverlay()
          : null,
    );
  }
}
