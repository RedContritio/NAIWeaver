import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../../core/services/client_diagnostics.dart';
import 'browser_photo_swipe_viewer_config.dart';

export 'browser_photo_swipe_viewer_config.dart' show BrowserPhotoSwipeItem;

/// `window.naiweaverPhotoSwipe`, installed by `web/index.html`. Every call
/// returns a promise, which rejects when the bridge module failed to load or
/// PhotoSwipe itself threw.
extension type _PhotoSwipeBridge(JSObject _) implements JSObject {
  external JSPromise<JSAny?> mount(
    web.HTMLElement host,
    JSString configJson,
    JSFunction onChange,
  );
  external JSPromise<JSAny?> update(web.HTMLElement host, JSString configJson);
  external JSPromise<JSAny?> dispose(web.HTMLElement host);
}

@JS('naiweaverPhotoSwipe')
external _PhotoSwipeBridge? get _photoSwipeBridge;

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
  const _ObjectUrlEntry(this.bytes, this.url, this.size);

  final Uint8List bytes;
  final String url;
  final ({int width, int height})? size;
}

class _BrowserPhotoSwipeViewerState extends State<BrowserPhotoSwipeViewer> {
  late final JSFunction _onChange = _handleChange.toJS;
  final Map<String, _ObjectUrlEntry> _objectUrls = {};
  web.HTMLDivElement? _host;
  String? _sentConfig;
  bool _updateScheduled = false;

  /// Set once the bridge is unavailable or PhotoSwipe failed; from then on
  /// the Flutter fallback viewer is shown instead of an empty black host.
  bool _failed = false;

  @override
  void didUpdateWidget(BrowserPhotoSwipeViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.isEmpty) {
      // build() swaps in the fallback, which removes the host element.
      _releaseHost();
      _revokeObjectUrls();
      return;
    }
    if (_updateScheduled) return;
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (mounted) _pushConfig();
    });
  }

  @override
  void dispose() {
    _releaseHost();
    _revokeObjectUrls();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || widget.items.isEmpty) return widget.fallback;
    return HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: _attachHost,
    );
  }

  void _handleChange(JSString rawId) {
    if (!mounted) return;
    final id = rawId.toDart;
    if (id == widget.selectedId) return;
    if (!widget.items.any((item) => item.id == id)) return;
    widget.onSelect(id);
  }

  void _attachHost(Object element) {
    if (!mounted) return;
    final host = element as web.HTMLDivElement;
    _releaseHost();
    host.className = 'naiweaver-photoswipe-host';
    host.style
      ..position = 'relative'
      ..overflow = 'hidden'
      ..backgroundColor = 'black';
    _host = host;
    final config = _buildConfig();
    _sentConfig = config;
    _callBridge(
      host,
      'mount',
      (bridge) => bridge.mount(host, config.toJS, _onChange),
    );
  }

  /// Sends the current items to the mounted gallery, which updates only the
  /// slides that changed so new results do not flash or reset the zoom.
  void _pushConfig() {
    final host = _host;
    if (host == null) return;
    final config = _buildConfig();
    if (config == _sentConfig) return;
    _sentConfig = config;
    _callBridge(host, 'update', (bridge) => bridge.update(host, config.toJS));
  }

  void _releaseHost() {
    final host = _host;
    if (host == null) return;
    _host = null;
    _sentConfig = null;
    if (_photoSwipeBridge == null) return;
    _callBridge(host, 'dispose', (bridge) => bridge.dispose(host));
  }

  Future<void> _callBridge(
    web.HTMLDivElement host,
    String operation,
    JSPromise<JSAny?> Function(_PhotoSwipeBridge bridge) invoke,
  ) async {
    try {
      final bridge = _photoSwipeBridge;
      if (bridge == null) {
        throw StateError('window.naiweaverPhotoSwipe is not installed');
      }
      await invoke(bridge).toDart;
    } catch (error) {
      ClientDiagnostics.instance.record('photoswipe_bridge_failed', {
        'operation': operation,
        'error_type': error.runtimeType.toString(),
        'error_message': error.toString(),
      });
      if (!mounted || !identical(_host, host)) return;
      _releaseHost();
      setState(() => _failed = true);
    }
  }

  String _buildConfig() {
    final activeIds = {for (final item in widget.items) item.id};
    _objectUrls.removeWhere((id, entry) {
      if (activeIds.contains(id)) return false;
      web.URL.revokeObjectURL(entry.url);
      return true;
    });
    final slides = <PhotoSwipeSlide>[];
    for (final item in widget.items) {
      final slide = _slideFor(item);
      if (slide != null) slides.add(slide);
    }
    return encodePhotoSwipeConfig(slides, widget.selectedId);
  }

  PhotoSwipeSlide? _slideFor(BrowserPhotoSwipeItem item) {
    final width = item.width;
    final height = item.height;
    final knownSize = width != null && height != null && width > 0 && height > 0
        ? (width: width, height: height)
        : null;
    final bytes = item.bytes;
    if (bytes == null) {
      final url = item.url;
      if (url == null) return null;
      return (
        id: item.id,
        src: url,
        width: knownSize?.width ?? 0,
        height: knownSize?.height ?? 0,
      );
    }
    var entry = _objectUrls[item.id];
    if (entry == null || !identical(entry.bytes, bytes)) {
      if (entry != null) web.URL.revokeObjectURL(entry.url);
      final blob = web.Blob(
        [bytes.toJS].toJS,
        web.BlobPropertyBag(type: 'image/png'),
      );
      entry = _ObjectUrlEntry(
        bytes,
        web.URL.createObjectURL(blob),
        pngDimensions(bytes),
      );
      _objectUrls[item.id] = entry;
    }
    final size = knownSize ?? entry.size;
    return (
      id: item.id,
      src: entry.url,
      width: size?.width ?? 0,
      height: size?.height ?? 0,
    );
  }

  void _revokeObjectUrls() {
    for (final entry in _objectUrls.values) {
      web.URL.revokeObjectURL(entry.url);
    }
    _objectUrls.clear();
  }
}
