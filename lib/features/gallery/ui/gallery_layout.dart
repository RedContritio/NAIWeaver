import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Bottom padding for the gallery grid. A GridView given explicit padding no
/// longer adds the safe area itself, so the last row has to clear both the
/// system inset ([safeAreaBottom], e.g. the iOS home indicator) and, in
/// selection mode, the floating bulk action bar ([actionBarExtent]: the
/// bar's height plus its offset from the bottom edge).
double galleryGridBottomInset({
  required double safeAreaBottom,
  double actionBarExtent = 0,
}) => math.max(safeAreaBottom, actionBarExtent) + 8;

/// Reports its child's laid-out height whenever it changes.
class HeightReporter extends SingleChildRenderObjectWidget {
  const HeightReporter({
    super.key,
    required this.onHeight,
    required super.child,
  });

  final ValueChanged<double> onHeight;

  @override
  RenderHeightReporter createRenderObject(BuildContext context) =>
      RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHeightReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class RenderHeightReporter extends RenderProxyBox {
  RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    // Layout must not trigger rebuilds; report after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

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
