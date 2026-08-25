import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import '../../../core/theme/theme_extensions.dart';

class ImagePreviewViewer extends StatelessWidget {
  final Uint8List? generatedImage;
  final ImageProvider? imageProvider;
  final bool isLoading;
  final bool isDragging;
  final Animation<double> pulseAnimation;
  final Object? imageIdentity;
  final bool framed;

  const ImagePreviewViewer({
    super.key,
    required this.generatedImage,
    this.imageProvider,
    required this.isLoading,
    required this.isDragging,
    required this.pulseAnimation,
    this.imageIdentity,
    this.framed = true,
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
                size: 48,
                color: t.textPrimary.withValues(alpha: 0.2),
              ),
            ),
          )
        else
          Center(
            child: Icon(
              Icons.blur_on,
              size: 40,
              color: t.textPrimary.withValues(alpha: 0.03),
            ),
          ),
        if (isDragging)
          Container(
            color: t.background.withValues(alpha: 0.7),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.file_download, size: 48, color: t.textPrimary),
                  const SizedBox(height: 16),
                  Text(
                    "DROP TO IMPORT SETTINGS",
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
    if (!framed) return RepaintBoundary(child: content);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: pulseAnimation,
        builder: (context, child) {
          return Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            decoration: BoxDecoration(
              color: t.textPrimary.withValues(alpha: 0.01),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isLoading
                    ? t.textPrimary.withValues(alpha: pulseAnimation.value)
                    : (isDragging ? t.accent : t.borderSubtle),
                width: (isLoading || isDragging) ? 2 : 1,
              ),
            ),
            child: child,
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: content,
        ),
      ),
    );
  }
}
