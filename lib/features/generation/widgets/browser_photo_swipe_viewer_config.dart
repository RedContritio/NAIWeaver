import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// One image shown by `BrowserPhotoSwipeViewer`.
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

/// One image as the PhotoSwipe bridge receives it.
typedef PhotoSwipeSlide = ({String id, String src, int width, int height});

/// Serialises the gallery for `naiweaverPhotoSwipe.mount/update`.
///
/// PhotoSwipe needs every slide's pixel size up front. When a slide arrives
/// with a size the bridge uses it directly instead of decoding the image a
/// second time just to read its dimensions.
String encodePhotoSwipeConfig(List<PhotoSwipeSlide> slides, String selectedId) {
  final selectedIndex = slides.indexWhere((slide) => slide.id == selectedId);
  return jsonEncode({
    'items': [
      for (final slide in slides)
        {
          'id': slide.id,
          'src': slide.src,
          'width': slide.width,
          'height': slide.height,
        },
    ],
    'index': selectedIndex < 0 ? 0 : selectedIndex,
  });
}

/// Reads the pixel size from a PNG header without decoding the image.
/// Returns null for anything that is not a well-formed PNG.
({int width, int height})? pngDimensions(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  // Signature (8) + IHDR length (4) + "IHDR" (4) + width (4) + height (4).
  if (bytes.length < 24) return null;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return null;
  }
  final header = ByteData.sublistView(bytes, 12, 24);
  if (header.getUint32(0) != 0x49484452) return null; // "IHDR"
  final width = header.getUint32(4);
  final height = header.getUint32(8);
  if (width == 0 || height == 0) return null;
  return (width: width, height: height);
}
