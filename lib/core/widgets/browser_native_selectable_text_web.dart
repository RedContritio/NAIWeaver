import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'web_style_bridge.dart';

/// Read-only text rendered as a DOM element, so selection handles, the
/// long-press menu and copy are the browser's own rather than Flutter's
/// canvas-drawn selection overlay.
///
/// Without an explicit [height] the widget is as tall as the browser lays the
/// text out: a `ResizeObserver` reports the element's real height back to
/// Flutter, so the last line is never clipped by a Flutter-side estimate made
/// with a different font engine.
class BrowserNativeSelectableText extends StatefulWidget {
  const BrowserNativeSelectableText({
    super.key,
    required this.text,
    this.height,
    this.style,
  });

  final String text;
  final double? height;
  final TextStyle? style;

  @override
  State<BrowserNativeSelectableText> createState() =>
      _BrowserNativeSelectableTextState();
}

/// Inline styles that never change for the lifetime of the element.
const Map<String, String> _staticSelectableCss = {
  'width': '100%',
  'margin': '0',
  'padding': '0',
  'box-sizing': 'border-box',
  'white-space': 'pre-wrap',
  'overflow-wrap': 'anywhere',
  'cursor': 'text',
  '-webkit-user-select': 'text',
  'user-select': 'text',
  '-webkit-touch-callout': 'default',
  // Touch drags have to reach Flutter, which scrolls the surrounding list.
  // With `auto` the browser claims the pan, cancels the pointer stream Flutter
  // is tracking, and then finds nothing in the DOM it could scroll. Wheel
  // events bubble to Flutter's view element either way.
  'touch-action': 'none',
};

/// Content-sized layout, measured by the browser.
const Map<String, String> _autoHeightCss = {
  'display': 'block',
  'height': 'auto',
  'overflow': 'visible',
};

/// Fixed-height layout, vertically centered like the non-Web fallback.
const Map<String, String> _fixedHeightCss = {
  'display': 'flex',
  'align-items': 'center',
  'height': '100%',
  'overflow': 'hidden',
};

class _BrowserNativeSelectableTextState
    extends State<BrowserNativeSelectableText> {
  web.HTMLDivElement? _element;
  web.Text? _textNode;
  web.ResizeObserver? _resizeObserver;
  String _renderedText = '';
  double? _measuredHeight;
  Map<String, String> _css = const {};
  Map<String, String> _appliedCss = const {};

  @override
  void dispose() {
    _detachElement();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final textCss = BrowserTextCss.fromTextStyle(
      style,
      textScaler: MediaQuery.textScalerOf(context),
    );
    _css = {
      ...textCss.properties,
      ...(widget.height == null ? _autoHeightCss : _fixedHeightCss),
    };
    final element = _element;
    if (element != null) {
      _applyCss(element);
      _syncText();
    }
    // Until the browser has measured the element, reserve a single line.
    final height =
        widget.height ??
        _measuredHeight ??
        (textCss.fontSize * (style.height ?? 1.2)).ceilToDouble();
    return SizedBox(
      height: height,
      child: HtmlElementView.fromTagName(
        tagName: 'div',
        onElementCreated: _attachElement,
      ),
    );
  }

  void _applyCss(web.HTMLDivElement element) {
    final style = element.style;
    for (final MapEntry(:key, :value) in _css.entries) {
      if (_appliedCss[key] != value) style.setProperty(key, value);
    }
    _appliedCss = _css;
  }

  void _attachElement(Object element) {
    if (!mounted) return;
    final div = element as web.HTMLDivElement;
    _detachElement();
    _element = div;
    for (final MapEntry(:key, :value) in _staticSelectableCss.entries) {
      div.style.setProperty(key, value);
    }
    _applyCss(div);
    final node = web.document.createTextNode(widget.text);
    div.appendChild(node);
    _textNode = node;
    _renderedText = widget.text;
    final observer = web.ResizeObserver(
      ((JSArray<web.ResizeObserverEntry> entries, web.ResizeObserver _) {
        if (!mounted || widget.height != null) return;
        final height = entries.toDart.last.contentRect.height.ceilToDouble();
        // A detached element reports zero; keep the last real measurement.
        if (height <= 0 || height == _measuredHeight) return;
        setState(() => _measuredHeight = height);
      }).toJS,
    );
    observer.observe(div);
    _resizeObserver = observer;
  }

  void _detachElement() {
    _resizeObserver?.disconnect();
    _resizeObserver = null;
    _element = null;
    _textNode = null;
    _appliedCss = const {};
    _renderedText = '';
  }

  void _syncText() {
    final node = _textNode;
    final text = widget.text;
    if (node == null || text == _renderedText) return;
    if (text.length > _renderedText.length && text.startsWith(_renderedText)) {
      // Streamed output only ever grows; extending the existing text node
      // avoids rebuilding the whole node for every token.
      node.appendData(text.substring(_renderedText.length));
    } else {
      node.data = text;
    }
    _renderedText = text;
  }
}
