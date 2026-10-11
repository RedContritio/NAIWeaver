import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../services/client_diagnostics.dart';
import 'browser_native_text_area_key_policy.dart';

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

class _BrowserNativeTextAreaState extends State<BrowserNativeTextArea>
    with AutomaticKeepAliveClientMixin<BrowserNativeTextArea> {
  static int _nextViewId = 0;

  late final String _viewType;
  web.HTMLTextAreaElement? _element;
  bool _syncingFromBrowser = false;
  bool _domHasFocus = false;
  int _lastScrollLogMs = 0;

  // A focused platform view must not be recycled by a surrounding sliver when
  // the mobile keyboard shrinks the visual viewport. Removing the textarea
  // from the DOM also removes browser focus and immediately dismisses the
  // keyboard.
  @override
  bool get wantKeepAlive =>
      _domHasFocus || (widget.focusNode?.hasFocus ?? false);

  @override
  void initState() {
    super.initState();
    _viewType = 'naiweaver-native-textarea-${_nextViewId++}';
    _record('native_textarea_init');
    widget.controller.addListener(_syncFromController);
    widget.focusNode?.addListener(_handleFocusChanged);
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
      oldWidget.focusNode?.removeListener(_handleFocusChanged);
      widget.focusNode?.addListener(_handleFocusChanged);
      updateKeepAlive();
      _syncDomFocus();
    }
    final textarea = _element;
    if (textarea != null) _applyStyle(textarea);
  }

  @override
  void dispose() {
    _record('native_textarea_dispose');
    widget.controller.removeListener(_syncFromController);
    widget.focusNode?.removeListener(_handleFocusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
      ..boxShadow = 'none'
      ..overflowY = 'auto';
    textarea.style.setProperty('-webkit-appearance', 'none');
    textarea.style.setProperty('appearance', 'none');
    textarea.style.setProperty('color-scheme', 'dark');
    textarea.style.setProperty('opacity', '1');
    textarea.style.setProperty('-webkit-user-select', 'text');
    textarea.style.setProperty('user-select', 'text');
    textarea.style.setProperty('-webkit-touch-callout', 'default');
    _applyStyle(textarea);
    _record('native_textarea_dom_created');

    textarea.addEventListener(
      'input',
      ((web.Event rawEvent) {
        final event = rawEvent as web.InputEvent;
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
        _record(
          'native_textarea_input',
          textarea: textarea,
          extra: {
            'character_count': text.length,
            'selection_start': start,
            'selection_end': end,
            'dom_input_type': event.inputType,
            'is_composing': event.isComposing,
          },
        );
      }).toJS,
    );
    textarea.addEventListener(
      'click',
      ((web.Event _) {
        _syncSelection(textarea);
        _record('native_textarea_click', textarea: textarea);
        widget.onTap?.call();
      }).toJS,
    );
    textarea.addEventListener(
      'select',
      ((web.Event _) {
        _syncSelection(textarea);
        _record(
          'native_textarea_selection_changed',
          textarea: textarea,
          extra: {
            'selection_start': textarea.selectionStart,
            'selection_end': textarea.selectionEnd,
          },
        );
      }).toJS,
    );
    textarea.addEventListener(
      'compositionstart',
      ((web.Event _) {
        _record('native_textarea_composition_started', textarea: textarea);
      }).toJS,
    );
    textarea.addEventListener(
      'compositionend',
      ((web.Event _) {
        _record(
          'native_textarea_composition_finished',
          textarea: textarea,
          extra: {
            'character_count': textarea.value.length,
            'selection_start': textarea.selectionStart,
            'selection_end': textarea.selectionEnd,
          },
        );
      }).toJS,
    );
    textarea.addEventListener(
      'scroll',
      ((web.Event _) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastScrollLogMs < 100) return;
        _lastScrollLogMs = now;
        _record(
          'native_textarea_scrolled',
          textarea: textarea,
          extra: {
            'scroll_top': textarea.scrollTop,
            'scroll_height': textarea.scrollHeight,
            'client_height': textarea.clientHeight,
          },
        );
      }).toJS,
    );
    textarea.addEventListener(
      'focus',
      ((web.Event _) {
        if (!mounted) return;
        _domHasFocus = true;
        _record('native_textarea_dom_focus', textarea: textarea);
        updateKeepAlive();
        widget.focusNode?.requestFocus();
      }).toJS,
    );
    textarea.addEventListener(
      'blur',
      ((web.Event _) {
        if (!mounted) return;
        _domHasFocus = false;
        _record('native_textarea_dom_blur', textarea: textarea);
        updateKeepAlive();
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
        final policy = browserNativeTextAreaKeyPolicy(handled == true);
        if (policy.preventDefault) {
          event.preventDefault();
        }
        // Editing belongs to the real DOM textarea. Let the browser perform
        // unhandled input (notably Space), but never bubble the same key into
        // Flutter's document-level keyboard dispatcher where it can be
        // interpreted as an app shortcut or scrolling command.
        if (policy.stopPropagation) event.stopPropagation();
      }).toJS,
    );
    _element = textarea;
    _syncDomFocus();
    return textarea;
  }

  void _handleFocusChanged() {
    _record('native_textarea_focus_node_changed');
    updateKeepAlive();
    _syncDomFocus();
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
      _record('native_textarea_focus_dom_requested', textarea: textarea);
      textarea.focus();
    } else if (!focusNode.hasFocus && active) {
      _record('native_textarea_blur_dom_requested', textarea: textarea);
      textarea.blur();
    }
  }

  void _record(
    String event, {
    web.HTMLTextAreaElement? textarea,
    Map<String, Object?> extra = const {},
  }) {
    final visualViewport = web.window.visualViewport;
    final computedStyle = textarea == null
        ? null
        : web.window.getComputedStyle(textarea);
    ClientDiagnostics.instance.record(event, {
      'view_type': _viewType,
      'mounted': mounted,
      'dom_has_focus': _domHasFocus,
      'focus_node_has_focus': widget.focusNode?.hasFocus,
      'is_active_element':
          textarea != null && web.document.activeElement == textarea,
      'window_inner_height': web.window.innerHeight,
      'visual_viewport_height': visualViewport?.height,
      'visual_viewport_offset_top': visualViewport?.offsetTop,
      'computed_background_color': computedStyle?.backgroundColor,
      'computed_font_size': computedStyle?.fontSize,
      'textarea_client_width': textarea?.clientWidth,
      'textarea_client_height': textarea?.clientHeight,
      ...extra,
    });
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
      ..caretColor = _cssColor(style.color ?? Colors.black)
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
