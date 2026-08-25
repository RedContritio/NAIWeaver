import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const bool supportsBrowserNativeTextArea = true;

/// A real browser textarea for touch-friendly selection, copy and paste.
///
/// Flutter's canvas text editing deliberately remains the fallback on native
/// platforms. On Web this widget hands the whole editing interaction to the
/// browser, including the platform's long-press selection menu.
class BrowserNativeTextArea extends StatefulWidget {
  final TextEditingController controller;
  final Widget fallback;
  final TextStyle? style;
  final String? hintText;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? selectionColor;
  final Color? selectionTextColor;
  final EdgeInsets? padding;
  final double? height;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final VoidCallback? onBlur;
  final bool Function(String key, bool control, bool alt, bool shift)?
  onKeyDown;

  const BrowserNativeTextArea({
    super.key,
    required this.controller,
    required this.fallback,
    this.style,
    this.hintText,
    this.backgroundColor,
    this.borderColor,
    this.selectionColor,
    this.selectionTextColor,
    this.padding,
    this.height,
    this.onChanged,
    this.onTap,
    this.focusNode,
    this.onBlur,
    this.onKeyDown,
  });

  @override
  State<BrowserNativeTextArea> createState() => _BrowserNativeTextAreaState();
}

class _BrowserNativeTextAreaState extends State<BrowserNativeTextArea> {
  static int _nextViewId = 0;

  late final String _viewType;
  web.HTMLTextAreaElement? _element;
  bool _syncingFromBrowser = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'naiweaver-native-textarea-${_nextViewId++}';
    widget.controller.addListener(_syncFromController);
    widget.focusNode?.addListener(_syncDomFocus);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, _createElement);
  }

  @override
  void didUpdateWidget(BrowserNativeTextArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
      _syncFromController();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_syncDomFocus);
      widget.focusNode?.addListener(_syncDomFocus);
      _syncDomFocus();
    }
    final textarea = _element;
    if (textarea != null) _applyStyle(textarea);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    widget.focusNode?.removeListener(_syncDomFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = HtmlElementView(viewType: _viewType);
    if (widget.focusNode != null) {
      child = Focus(focusNode: widget.focusNode, child: child);
    }
    return widget.height == null
        ? child
        : SizedBox(height: widget.height, child: child);
  }

  web.HTMLTextAreaElement _createElement(int _) {
    final textarea = web.HTMLTextAreaElement()
      ..value = widget.controller.text
      ..spellcheck = false
      ..autocapitalize = 'off';
    textarea.setAttribute('autocorrect', 'off');
    textarea.classList.add('naiweaver-native-textarea');
    textarea.style
      ..width = '100%'
      ..height = '100%'
      ..boxSizing = 'border-box'
      ..resize = 'none'
      ..outline = 'none'
      ..overflowY = 'auto';
    textarea.style.setProperty('-webkit-user-select', 'text');
    textarea.style.setProperty('user-select', 'text');
    textarea.style.setProperty('-webkit-touch-callout', 'default');
    _applyStyle(textarea);

    textarea.addEventListener(
      'input',
      ((web.Event _) {
        _syncingFromBrowser = true;
        final text = textarea.value;
        final start = textarea.selectionStart;
        final end = textarea.selectionEnd;
        widget.controller.value = TextEditingValue(
          text: text,
          selection: TextSelection(baseOffset: start, extentOffset: end),
        );
        _syncingFromBrowser = false;
        widget.onChanged?.call(text);
      }).toJS,
    );
    textarea.addEventListener(
      'click',
      ((web.Event _) {
        _syncSelection(textarea);
        widget.onTap?.call();
      }).toJS,
    );
    textarea.addEventListener(
      'select',
      ((web.Event _) {
        _syncSelection(textarea);
      }).toJS,
    );
    textarea.addEventListener(
      'focus',
      ((web.Event _) {
        widget.focusNode?.requestFocus();
        widget.onTap?.call();
      }).toJS,
    );
    textarea.addEventListener(
      'blur',
      ((web.Event _) {
        widget.focusNode?.unfocus();
        widget.onBlur?.call();
      }).toJS,
    );
    textarea.addEventListener(
      'keydown',
      ((web.Event rawEvent) {
        final event = rawEvent as web.KeyboardEvent;
        _syncSelection(textarea);
        final handled = widget.onKeyDown?.call(
          event.key,
          event.ctrlKey || event.metaKey,
          event.altKey,
          event.shiftKey,
        );
        if (handled == true) {
          event.preventDefault();
          event.stopPropagation();
        }
      }).toJS,
    );
    _element = textarea;
    _syncDomFocus();
    return textarea;
  }

  void _syncFromController() {
    if (_syncingFromBrowser) return;
    final textarea = _element;
    if (textarea != null && textarea.value != widget.controller.text) {
      textarea.value = widget.controller.text;
    }
  }

  void _syncDomFocus() {
    final textarea = _element;
    final focusNode = widget.focusNode;
    if (textarea == null || focusNode == null) return;
    final active = web.document.activeElement == textarea;
    if (focusNode.hasFocus && !active) {
      textarea.focus();
    } else if (!focusNode.hasFocus && active) {
      textarea.blur();
    }
  }

  void _syncSelection(web.HTMLTextAreaElement textarea) {
    final selection = TextSelection(
      baseOffset: textarea.selectionStart,
      extentOffset: textarea.selectionEnd,
    );
    if (widget.controller.selection != selection) {
      widget.controller.selection = selection;
    }
  }

  void _applySelectionColors(web.HTMLTextAreaElement textarea) {
    textarea.style.setProperty(
      '--naiweaver-selection-background',
      _cssColor(widget.selectionColor ?? const Color(0xB85D9CEC)),
    );
    textarea.style.setProperty(
      '--naiweaver-selection-foreground',
      _cssColor(widget.selectionTextColor ?? Colors.white),
    );
  }

  void _applyStyle(web.HTMLTextAreaElement textarea) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final padding = widget.padding ?? EdgeInsets.zero;
    textarea.placeholder = widget.hintText ?? '';
    textarea.style
      ..fontFamily = style.fontFamily ?? 'sans-serif'
      ..fontSize = '${style.fontSize ?? 14}px'
      ..fontWeight = '${style.fontWeight?.value ?? 400}'
      ..letterSpacing = '${style.letterSpacing ?? 0}px'
      ..lineHeight = '${style.height ?? 1.2}'
      ..color = _cssColor(style.color ?? Colors.black)
      ..backgroundColor = _cssColor(
        widget.backgroundColor ?? Colors.transparent,
      )
      ..border =
          '1px solid ${_cssColor(widget.borderColor ?? Colors.transparent)}'
      ..borderRadius = '4px'
      ..padding =
          '${padding.top}px ${padding.right}px ${padding.bottom}px ${padding.left}px';
    _applySelectionColors(textarea);
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
