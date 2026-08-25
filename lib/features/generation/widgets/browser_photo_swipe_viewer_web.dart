import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('naiweaverPhotoSwipe.mount')
external void _mountPhotoSwipe(
  web.HTMLElement host,
  JSString configJson,
  JSFunction onChange,
);

@JS('naiweaverPhotoSwipe.update')
external void _updatePhotoSwipe(web.HTMLElement host, JSString configJson);

@JS('naiweaverPhotoSwipe.dispose')
external void _disposePhotoSwipe(web.HTMLElement host);

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

class BrowserPhotoSwipeViewer extends StatefulWidget {
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
  State<BrowserPhotoSwipeViewer> createState() =>
      _BrowserPhotoSwipeViewerState();
}

class _ObjectUrlEntry {
  const _ObjectUrlEntry(this.bytes, this.url);

  final Uint8List bytes;
  final String url;
}

class _BrowserPhotoSwipeViewerState extends State<BrowserPhotoSwipeViewer> {
  static int _nextViewId = 0;

  late final String _viewType;
  late final JSFunction _onChange;
  final Map<String, _ObjectUrlEntry> _objectUrls = {};
  web.HTMLDivElement? _host;

  @override
  void initState() {
    super.initState();
    _viewType = 'naiweaver-photoswipe-${_nextViewId++}';
    _onChange = ((JSNumber rawIndex) {
      final index = rawIndex.toDartInt;
      if (!mounted || index < 0 || index >= widget.items.length) return;
      final id = widget.items[index].id;
      if (id != widget.selectedId) widget.onSelect(id);
    }).toJS;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, _createHost);
  }

  @override
  void didUpdateWidget(BrowserPhotoSwipeViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(mount: false));
  }

  @override
  void dispose() {
    final host = _host;
    if (host != null) _disposePhotoSwipe(host);
    for (final entry in _objectUrls.values) {
      web.URL.revokeObjectURL(entry.url);
    }
    _objectUrls.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return widget.fallback;
    return HtmlElementView(viewType: _viewType);
  }

  web.HTMLDivElement _createHost(int _) {
    final host = web.HTMLDivElement()
      ..className = 'naiweaver-photoswipe-host'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.position = 'relative'
      ..style.overflow = 'hidden'
      ..style.backgroundColor = 'black';
    _host = host;
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(mount: true));
    return host;
  }

  void _sync({required bool mount}) {
    final host = _host;
    if (!mounted || host == null || widget.items.isEmpty) return;
    final config = _buildConfig();
    if (mount) {
      _mountPhotoSwipe(host, config.toJS, _onChange);
    } else {
      _updatePhotoSwipe(host, config.toJS);
    }
  }

  String _buildConfig() {
    final activeIds = widget.items.map((item) => item.id).toSet();
    final staleIds = _objectUrls.keys
        .where((id) => !activeIds.contains(id))
        .toList();
    for (final id in staleIds) {
      web.URL.revokeObjectURL(_objectUrls.remove(id)!.url);
    }

    final encodedItems = <Map<String, Object?>>[];
    for (final item in widget.items) {
      final src = _sourceFor(item);
      if (src == null) continue;
      encodedItems.add({
        'id': item.id,
        'src': src,
        'width': item.width ?? 0,
        'height': item.height ?? 0,
        'alt': '',
      });
    }
    final selectedIndex = encodedItems.indexWhere(
      (item) => item['id'] == widget.selectedId,
    );
    final sourceKey = encodedItems
        .map((item) => '${item['id']}|${item['src']}')
        .join('\n');
    return jsonEncode({
      'items': encodedItems,
      'index': selectedIndex < 0 ? 0 : selectedIndex,
      'sourceKey': sourceKey,
    });
  }

  String? _sourceFor(BrowserPhotoSwipeItem item) {
    final bytes = item.bytes;
    if (bytes == null) return item.url;
    final existing = _objectUrls[item.id];
    if (existing != null && identical(existing.bytes, bytes)) {
      return existing.url;
    }
    if (existing != null) web.URL.revokeObjectURL(existing.url);
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final url = web.URL.createObjectURL(blob);
    _objectUrls[item.id] = _ObjectUrlEntry(bytes, url);
    return url;
  }
}
