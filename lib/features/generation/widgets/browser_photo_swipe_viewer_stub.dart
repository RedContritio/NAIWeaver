import 'dart:typed_data';

import 'package:flutter/material.dart';

class BrowserPhotoSwipeItem {
  const BrowserPhotoSwipeItem({
    required this.id,
    this.imageProvider,
    this.bytes,
    this.url,
    this.width,
    this.height,
  });

  final String id;
  final ImageProvider? imageProvider;
  final Uint8List? bytes;
  final String? url;
  final int? width;
  final int? height;
}

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
