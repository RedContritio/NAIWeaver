import 'dart:math' as math;

import 'package:flutter/material.dart';

double galleryGridBottomInset(bool isSelectionMode) => isSelectionMode ? 80 : 8;

class GalleryDetailPanelViewport extends StatelessWidget {
  const GalleryDetailPanelViewport({
    super.key,
    required this.mobile,
    required this.background,
    required this.padding,
    required this.child,
  });

  static const scrollViewKey = ValueKey<String>(
    'gallery-detail-panel-scroll-view',
  );

  final bool mobile;
  final Decoration background;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = math.min(
      mobile ? 440.0 : 380.0,
      viewportHeight * (mobile ? 0.62 : 0.52),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: background,
        child: SingleChildScrollView(
          key: scrollViewKey,
          primary: false,
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
