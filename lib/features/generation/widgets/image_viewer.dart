import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';

class ImagePreviewViewer extends StatelessWidget {
  final Uint8List? generatedImage;
  final ImageProvider? imageProvider;
  final bool isDragging;
  final Object? imageIdentity;

  const ImagePreviewViewer({
    super.key,
    required this.generatedImage,
    this.imageProvider,
    required this.isDragging,
    this.imageIdentity,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final resolvedProvider =
        imageProvider ??
        (generatedImage == null ? null : MemoryImage(generatedImage!));
    final content = Stack(
      fit: StackFit.expand,
      children: [
        if (resolvedProvider != null)
          Positioned.fill(
            child: PhotoView(
              key: ValueKey<Object>(imageIdentity ?? resolvedProvider),
              imageProvider: resolvedProvider,
              backgroundDecoration: const BoxDecoration(
                color: Colors.transparent,
              ),
              initialScale: PhotoViewComputedScale.contained,
              minScale: PhotoViewComputedScale.contained * 0.5,
              maxScale: PhotoViewComputedScale.covered * 4.0,
              basePosition: Alignment.center,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.broken_image_outlined,
                size: VisionMetrics.iconLarge * 2,
                color: t.textMinimal,
              ),
            ),
          )
        else
          Center(
            child: Icon(
              Icons.blur_on,
              size: VisionMetrics.iconLarge * 2,
              color: t.textMinimal.withValues(
                alpha: VisionMetrics.opacityHover,
              ),
            ),
          ),
        if (isDragging)
          Container(
            color: t.background.withValues(alpha: VisionMetrics.opacityOverlay),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.file_download,
                    size: VisionMetrics.iconLarge * 2,
                    color: t.textPrimary,
                  ),
                  const SizedBox(height: VisionMetrics.space16),
                  Text(
                    context.l.generationDropToImport.toUpperCase(),
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: t.fontSize(12),
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    return RepaintBoundary(child: content);
  }
}
