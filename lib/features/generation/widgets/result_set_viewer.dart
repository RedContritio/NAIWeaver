import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import 'browser_photo_swipe_viewer.dart';
import 'image_viewer.dart';

class ResultSetViewItem {
  const ResultSetViewItem({
    required this.id,
    required this.position,
    required this.count,
    this.previewImage,
    this.thumbnailImage,
    this.imageBytes,
    this.imageUrl,
    this.width,
    this.height,
    this.seed,
    this.infoTitle,
    this.infoSubtitle,
    this.isLoading = false,
    this.isGenerating = false,
    this.errorMessage,
  });

  final String id;
  final int position;
  final int count;
  final ImageProvider? previewImage;
  final ImageProvider? thumbnailImage;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final int? width;
  final int? height;
  final int? seed;
  final String? infoTitle;
  final String? infoSubtitle;
  final bool isLoading;
  final bool isGenerating;
  final String? errorMessage;

  bool get hasImage =>
      previewImage != null || imageBytes != null || imageUrl != null;
  bool get hasBrowserImage => imageBytes != null || imageUrl != null;
  bool get failed => errorMessage?.trim().isNotEmpty == true;
}

class ResultSetViewer extends StatelessWidget {
  const ResultSetViewer({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.mobile,
    required this.pulseAnimation,
    this.isDragging = false,
    this.previewOverlay,
    this.topLeading,
    this.selectedActionBuilder,
  });

  final List<ResultSetViewItem> items;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final bool mobile;
  final Animation<double> pulseAnimation;
  final bool isDragging;
  final Widget? previewOverlay;
  final Widget? topLeading;
  final Widget Function(BuildContext, ResultSetViewItem)? selectedActionBuilder;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _ResultSetFrame(
        isLoading: false,
        isDragging: isDragging,
        pulseAnimation: pulseAnimation,
        child: ImagePreviewViewer(generatedImage: null, isDragging: isDragging),
      );
    }
    final selected =
        items.where((item) => item.id == selectedId).firstOrNull ?? items.first;
    final fallbackViewer = ImagePreviewViewer(
      generatedImage: null,
      imageProvider: selected.previewImage,
      imageIdentity: selected.id,
      isDragging: isDragging,
    );
    final browserItems = items
        .where((item) => item.hasBrowserImage)
        .map(
          (item) => BrowserPhotoSwipeItem(
            id: item.id,
            imageProvider: item.previewImage,
            bytes: item.imageBytes,
            url: item.imageUrl,
            width: item.width,
            height: item.height,
          ),
        )
        .toList();
    final preview = Stack(
      key: const ValueKey<String>('result-set-preview'),
      fit: StackFit.expand,
      children: [
        if (selected.hasBrowserImage)
          BrowserPhotoSwipeViewer(
            key: const ValueKey<String>('result-set-photoswipe-viewer'),
            items: browserItems,
            selectedId: selected.id,
            onSelect: onSelect,
            fallback: fallbackViewer,
          )
        else
          fallbackViewer,
        if (!selected.hasImage)
          Positioned.fill(
            child: ColoredBox(
              key: const ValueKey<String>('result-set-preview-status'),
              color: context.t.background,
              child: _ResultSetStatus(item: selected),
            ),
          ),
        if (previewOverlay != null) Positioned.fill(child: previewOverlay!),
        if (topLeading != null)
          Positioned(
            top: VisionMetrics.space8,
            left: VisionMetrics.space8,
            child: topLeading!,
          ),
        if (selectedActionBuilder != null)
          Positioned(
            top: VisionMetrics.space8,
            right: VisionMetrics.space8,
            child: selectedActionBuilder!(context, selected),
          ),
      ],
    );
    if (items.length == 1) {
      return _ResultSetFrame(
        isLoading: selected.isLoading,
        isDragging: isDragging,
        pulseAnimation: pulseAnimation,
        child: preview,
      );
    }

    final strip = _ResultSetThumbnailStrip(
      items: items,
      selectedId: selected.id,
      mobile: mobile,
      onSelect: onSelect,
    );
    return _ResultSetFrame(
      isLoading: selected.isLoading,
      isDragging: isDragging,
      pulseAnimation: pulseAnimation,
      child: Column(
        children: [
          Expanded(child: preview),
          SizedBox(
            key: const ValueKey<String>('result-set-thumbnail-footer'),
            // The footer line of each thumbnail grows with the text scale.
            height:
                (mobile ? 90 : 98) +
                _ResultSetFooter.height *
                    (_ResultSetFooter.scaleOf(context) - 1),
            child: strip,
          ),
        ],
      ),
    );
  }
}

class _ResultSetFrame extends StatelessWidget {
  const _ResultSetFrame({
    required this.isLoading,
    required this.isDragging,
    required this.pulseAnimation,
    required this.child,
  });

  final bool isLoading;
  final bool isDragging;
  final Animation<double> pulseAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: pulseAnimation,
        builder: (context, child) => Container(
          key: const ValueKey<String>('result-set-frame'),
          margin: const EdgeInsets.fromLTRB(
            VisionMetrics.space12,
            VisionMetrics.space4,
            VisionMetrics.space12,
            0,
          ),
          decoration: BoxDecoration(
            color: t.background,
            borderRadius: BorderRadius.circular(VisionMetrics.radius4),
            border: Border.all(
              color: isLoading
                  ? t.textPrimary.withValues(alpha: pulseAnimation.value)
                  : (isDragging ? t.accent : t.borderSubtle),
              width: isLoading || isDragging ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
        child: child,
      ),
    );
  }
}

class _ResultSetThumbnailStrip extends StatelessWidget {
  const _ResultSetThumbnailStrip({
    required this.items,
    required this.selectedId,
    required this.mobile,
    required this.onSelect,
  });

  final List<ResultSetViewItem> items;
  final String selectedId;
  final bool mobile;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return DecoratedBox(
      key: const ValueKey<String>('result-set-thumbnail-strip'),
      decoration: BoxDecoration(
        color: t.surfaceMid,
        border: Border(top: BorderSide(color: t.borderSubtle)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(
          VisionMetrics.space8,
          mobile ? VisionMetrics.space4 : VisionMetrics.space8,
          VisionMetrics.space8,
          mobile ? VisionMetrics.space8 : VisionMetrics.space12,
        ),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: VisionMetrics.space8),
        itemBuilder: (context, index) {
          final item = items[index];
          return SizedBox(
            width: mobile ? 72 : 80,
            child: ResultSetThumbnail(
              item: item,
              selected: item.id == selectedId,
              onTap: () => onSelect(item.id),
            ),
          );
        },
      ),
    );
  }
}

/// Metrics of the one-line caption under a thumbnail.
abstract final class _ResultSetFooter {
  static const double height = 26;

  /// How much the caption text is enlarged by the user's text scale (>= 1).
  static double scaleOf(BuildContext context) {
    final scaled = MediaQuery.textScalerOf(context).scale(10) / 10;
    return scaled < 1 ? 1 : (scaled > 2 ? 2 : scaled);
  }
}

class ResultSetThumbnail extends StatelessWidget {
  const ResultSetThumbnail({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    this.showFooter = true,
  });

  final ResultSetViewItem item;
  final bool selected;
  final VoidCallback onTap;
  final bool showFooter;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      key: ValueKey<String>('result-set-thumbnail-${item.id}'),
      color: t.surfaceHigh.withValues(
        alpha: selected
            ? VisionMetrics.opacityOverlay
            : VisionMetrics.opacityScrim,
      ),
      borderRadius: BorderRadius.circular(VisionMetrics.radius4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VisionMetrics.radius4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VisionMetrics.radius4),
            border: Border.all(
              color: selected ? t.accent : t.borderSubtle,
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(VisionMetrics.radius4),
            child: Column(
              children: [
                Expanded(
                  child: ColoredBox(
                    color: t.background,
                    child: SizedBox.expand(child: _thumbnailBody(context)),
                  ),
                ),
                if (showFooter)
                  Container(
                    constraints: const BoxConstraints(
                      minHeight: _ResultSetFooter.height,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: VisionMetrics.space8,
                    ),
                    alignment: Alignment.centerLeft,
                    color: t.surfaceHigh,
                    child: Text(
                      item.seed == null
                          ? '${item.position}/${item.count}'
                          : '${item.position}/${item.count}  seed ${item.seed}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.textTertiary,
                        fontSize: t.fontSize(9),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbnailBody(BuildContext context) {
    final provider = item.thumbnailImage ?? item.previewImage;
    if (provider != null) {
      return Image(
        image: provider,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            _ResultSetStatus(item: item, forceFailed: true, compact: true),
      );
    }
    return _ResultSetStatus(item: item, compact: true);
  }
}

class _ResultSetStatus extends StatelessWidget {
  const _ResultSetStatus({
    required this.item,
    this.forceFailed = false,
    this.compact = false,
  });

  final ResultSetViewItem item;
  final bool forceFailed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final failed = forceFailed || item.failed;
    final statusIcon = item.isGenerating && !failed
        ? SizedBox(
            width: VisionMetrics.iconLarge,
            height: VisionMetrics.iconLarge,
            child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
          )
        : Icon(
            failed ? Icons.error_outline_rounded : Icons.schedule_rounded,
            color: failed ? t.accentDanger : t.textDisabled,
          );
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: compact && constraints.maxHeight < 64
            ? statusIcon
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  statusIcon,
                  const SizedBox(height: VisionMetrics.space8),
                  Text(
                    failed
                        ? (item.errorMessage ??
                              context.l.generationFailedFallback)
                        : (item.isGenerating
                              ? context.l.mainResultGenerating
                              : context.l.mainResultPending),
                    maxLines: compact ? 2 : 5,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.textTertiary,
                      fontSize: t.fontSize(compact ? 9 : 11),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
