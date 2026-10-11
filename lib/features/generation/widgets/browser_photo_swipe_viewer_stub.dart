import 'package:flutter/material.dart';

import 'browser_photo_swipe_viewer_config.dart';

export 'browser_photo_swipe_viewer_config.dart' show BrowserPhotoSwipeItem;

class BrowserPhotoSwipeViewer extends StatelessWidget {
  const BrowserPhotoSwipeViewer({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.fallback,
  });

  final List<BrowserPhotoSwipeItem> items;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => fallback;
}
