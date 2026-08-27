import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

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

class _BrowserNativeSelectableTextState
    extends State<BrowserNativeSelectableText> {
  static int _nextViewId = 0;

  late final String _viewType;
  web.HTMLDivElement? _element;

  @override
  void initState() {
    super.initState();
    _viewType = 'naiweaver-native-selectable-${_nextViewId++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, _createElement);
  }

  @override
  void didUpdateWidget(BrowserNativeSelectableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final element = _element;
    if (element != null) _apply(element);
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter =
            TextPainter(
              text: TextSpan(text: widget.text, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(
              maxWidth: constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width,
            );
        final effectiveHeight =
            widget.height ??
            (painter.height + 4).clamp(24.0, 100000.0).toDouble();
        return SizedBox(
          height: effectiveHeight,
          child: HtmlElementView(viewType: _viewType),
        );
      },
    );
  }

  web.HTMLDivElement _createElement(int _) {
    final element = web.HTMLDivElement();
    element.style
      ..width = '100%'
      ..height = '100%'
      ..boxSizing = 'border-box'
      ..display = 'block'
      ..whiteSpace = 'pre-wrap'
      ..overflowWrap = 'anywhere'
      ..overflow = 'hidden'
      ..cursor = 'text';
    element.style.setProperty('-webkit-user-select', 'text');
    element.style.setProperty('user-select', 'text');
    element.style.setProperty('-webkit-touch-callout', 'default');
    _element = element;
    _apply(element);
    return element;
  }

  void _apply(web.HTMLDivElement element) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    element.textContent = widget.text;
    element.style
      ..fontFamily = style.fontFamily ?? 'sans-serif'
      ..fontSize = '${style.fontSize ?? 14}px'
      ..fontWeight = '${style.fontWeight?.value ?? 400}'
      ..fontStyle = style.fontStyle == FontStyle.italic ? 'italic' : 'normal'
      ..letterSpacing = '${style.letterSpacing ?? 0}px'
      ..lineHeight = '${style.height ?? 1.2}'
      ..paddingTop = widget.height == null ? '0' : '8px'
      ..color = _cssColor(style.color ?? Colors.black);
  }
}

String _cssColor(Color color) {
  final argb = color.toARGB32();
  final alpha = ((argb >> 24) & 0xff) / 255;
  final red = (argb >> 16) & 0xff;
  final green = (argb >> 8) & 0xff;
  final blue = argb & 0xff;
  return 'rgba($red, $green, $blue, $alpha)';
}
