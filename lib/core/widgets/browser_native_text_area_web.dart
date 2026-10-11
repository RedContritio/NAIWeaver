import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../services/client_diagnostics.dart';
import '../services/client_diagnostics_platform.dart';
import '../theme/theme_extensions.dart';
import 'browser_native_text_area_key_policy.dart';
import 'web_style_bridge.dart';

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

/// Inline styles that never change for the lifetime of the element.
const Map<String, String> _staticTextAreaCss = {
  'width': '100%',
  'height': '100%',
  'margin': '0',
  'box-sizing': 'border-box',
  'resize': 'none',
  'outline': 'none',
  'box-shadow': 'none',
  'overflow-y': 'auto',
  'border-radius': '4px',
  '-webkit-appearance': 'none',
  'appearance': 'none',
  'opacity': '1',
  '-webkit-user-select': 'text',
  'user-select': 'text',
  '-webkit-touch-callout': 'default',
};

class _BrowserNativeTextAreaState extends State<BrowserNativeTextArea>
    with AutomaticKeepAliveClientMixin<BrowserNativeTextArea> {
  static int _nextInstanceId = 0;

  final int _instanceId = _nextInstanceId++;
  final _DomListeners _listeners = _DomListeners();
  FocusNode? _ownFocusNode;
  web.HTMLTextAreaElement? _element;
  Map<String, String> _css = const {};
  Map<String, String> _appliedCss = const {};
  String _placeholder = '';
  bool _syncingFromBrowser = false;
  bool _domHasFocus = false;
  int _lastScrollLogMs = 0;
  Timer? _pendingSelectionSync;

  /// The selection last exchanged with the DOM. A controller notification
  /// whose selection still equals this did not come from a programmatic
  /// selection change, so it must not overwrite a caret move the browser has
  /// made but not yet reported through `selectionchange`.
  TextSelection? _exchangedSelection;

  /// Flutter focus must follow the textarea even when the caller does not
  /// supply a node; otherwise keys typed into the textarea are dispatched to
  /// whichever widget had Flutter focus before (Space would press a button).
  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownFocusNode ??= FocusNode(debugLabel: 'BrowserNativeTextArea'));

  // A focused platform view must not be recycled by a surrounding sliver when
  // the mobile keyboard shrinks the visual viewport. Removing the textarea
  // from the DOM also removes browser focus and immediately dismisses the
  // keyboard.
  @override
  bool get wantKeepAlive => _domHasFocus || _focusNode.hasFocus;

  @override
  void initState() {
    super.initState();
    _record('native_textarea_init');
    widget.controller.addListener(_syncFromController);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(BrowserNativeTextArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
      _exchangedSelection = null;
      _syncFromController();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocusNode)?.removeListener(
        _handleFocusChanged,
      );
      _focusNode.addListener(_handleFocusChanged);
      updateKeepAlive();
      _syncDomFocus();
    }
  }

  @override
  void dispose() {
    _record('native_textarea_dispose');
    _detachElement();
    widget.controller.removeListener(_syncFromController);
    _focusNode.removeListener(_handleFocusChanged);
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _css = _resolveCss(context);
    _placeholder = widget.hintText ?? '';
    final textarea = _element;
    if (textarea != null) _applyCss(textarea);

    Widget child = HtmlElementView.fromTagName(
      tagName: 'textarea',
      onElementCreated: _attachElement,
    );
    child = Focus(focusNode: _focusNode, child: child);
    child = Shortcuts(shortcuts: browserNativeTextAreaShortcuts, child: child);
    return widget.height == null
        ? child
        : SizedBox(height: widget.height, child: child);
  }

  Map<String, String> _resolveCss(BuildContext context) {
    final t = context.t;
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final textColor = style.color ?? t.textPrimary;
    final text = BrowserTextCss.fromTextStyle(
      style.copyWith(color: textColor),
      textScaler: MediaQuery.textScalerOf(context),
      minFontSize: browserInputMinFontSize(defaultTargetPlatform),
    );
    final background = widget.backgroundColor;
    final border = widget.borderColor;
    final padding = widget.padding ?? EdgeInsets.zero;
    return {
      ...text.properties,
      'caret-color': cssColor(textColor),
      'background-color': background == null
          ? 'transparent'
          : cssColor(background),
      'border':
          '1px solid ${border == null ? 'transparent' : cssColor(border)}',
      'padding':
          '${padding.top}px ${padding.right}px '
          '${padding.bottom}px ${padding.left}px',
      'color-scheme': cssColorScheme(
        Color.alphaBlend(background ?? t.background, t.background),
      ),
      '--naiweaver-placeholder-color': cssColor(t.hintText),
      '--naiweaver-selection-background': cssColor(
        widget.selectionColor ?? t.accent.withValues(alpha: 0.72),
      ),
      '--naiweaver-selection-foreground': cssColor(
        widget.selectionTextColor ?? textColor,
      ),
    };
  }

  void _applyCss(web.HTMLTextAreaElement textarea) {
    final style = textarea.style;
    for (final MapEntry(:key, :value) in _css.entries) {
      if (_appliedCss[key] != value) style.setProperty(key, value);
    }
    _appliedCss = _css;
    if (textarea.placeholder != _placeholder) {
      textarea.placeholder = _placeholder;
    }
  }

  void _attachElement(Object element) {
    if (!mounted) return;
    final textarea = element as web.HTMLTextAreaElement;
    _detachElement();
    _element = textarea;
    _appliedCss = const {};
    textarea
      ..value = widget.controller.text
      ..spellcheck = false
      ..autocapitalize = 'off';
    textarea.setAttribute('autocorrect', 'off');
    textarea.classList.add('naiweaver-native-textarea');
    for (final MapEntry(:key, :value) in _staticTextAreaCss.entries) {
      textarea.style.setProperty(key, value);
    }
    _applyCss(textarea);
    _applyControllerSelection(textarea);
    _listenToElement(textarea);
    _record('native_textarea_dom_created');
    // The element is attached to the DOM when the next frame is composited;
    // only then can it take focus that the focus node already holds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_element, textarea)) _syncDomFocus();
    });
  }

  void _detachElement() {
    _listeners.removeAll();
    _pendingSelectionSync?.cancel();
    _element = null;
  }

  void _listenToElement(web.HTMLTextAreaElement textarea) {
    _listen(textarea, 'input', (rawEvent) {
      final event = rawEvent as web.InputEvent;
      final text = textarea.value;
      final selection = _domSelection(textarea);
      _syncingFromBrowser = true;
      try {
        widget.controller.value = TextEditingValue(
          text: text,
          selection: selection,
        );
      } finally {
        _syncingFromBrowser = false;
      }
      _exchangedSelection = selection;
      widget.onChanged?.call(text);
      _record(
        'native_textarea_input',
        extra: {
          'character_count': text.length,
          'selection_start': selection.start,
          'selection_end': selection.end,
          'dom_input_type': event.inputType,
          'is_composing': event.isComposing,
        },
      );
    });
    _listen(textarea, 'click', (_) {
      _syncSelectionFromDom();
      _record('native_textarea_click');
      widget.onTap?.call();
    });
    _listen(textarea, 'select', (_) {
      _syncSelectionFromDom();
      _record(
        'native_textarea_selection_changed',
        extra: {
          'selection_start': textarea.selectionStart,
          'selection_end': textarea.selectionEnd,
        },
      );
    });
    // Caret moves from the keyboard (Home, Cmd+Left, arrows), selection
    // drags and touch handles produce no input event. Keyup and pointerup
    // sync at once; `selectionchange`, which browsers fire on the document,
    // covers the rest once the selection settles (see _scheduleSelectionSync).
    _listen(web.document, 'selectionchange', (_) {
      if (web.document.activeElement == textarea) _scheduleSelectionSync();
    });
    _listen(textarea, 'keyup', (_) => _syncSelectionFromDom());
    _listen(textarea, 'pointerup', (_) => _syncSelectionFromDom());
    _listen(textarea, 'compositionstart', (_) {
      _record('native_textarea_composition_started');
    });
    _listen(textarea, 'compositionend', (_) {
      _record(
        'native_textarea_composition_finished',
        extra: {
          'character_count': textarea.value.length,
          'selection_start': textarea.selectionStart,
          'selection_end': textarea.selectionEnd,
        },
      );
    });
    _listen(textarea, 'scroll', (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastScrollLogMs < 100) return;
      _lastScrollLogMs = now;
      _record(
        'native_textarea_scrolled',
        extra: {
          'scroll_top': textarea.scrollTop,
          'scroll_height': textarea.scrollHeight,
          'client_height': textarea.clientHeight,
        },
      );
    });
    _listen(textarea, 'focus', (_) {
      _domHasFocus = true;
      _record('native_textarea_dom_focus', includeViewport: true);
      updateKeepAlive();
      _focusNode.requestFocus();
    });
    _listen(textarea, 'blur', (_) {
      _domHasFocus = false;
      _record('native_textarea_dom_blur', includeViewport: true);
      updateKeepAlive();
      _focusNode.unfocus();
      widget.onBlur?.call();
    });
    _listen(textarea, 'keydown', (rawEvent) {
      final event = rawEvent as web.KeyboardEvent;
      _syncSelectionFromDom();
      final handled = widget.onKeyDown?.call(
        event.key,
        event.ctrlKey || event.metaKey,
        event.altKey,
        event.shiftKey,
      );
      final policy = browserNativeTextAreaKeyPolicy(handled == true);
      if (policy.preventDefault) event.preventDefault();
      if (policy.stopPropagation) event.stopPropagation();
    });
  }

  /// Registers a DOM listener that is removed with the element and ignores
  /// events delivered after this state has been disposed.
  void _listen(
    web.EventTarget target,
    String type,
    void Function(web.Event event) handler,
  ) {
    _listeners.add(target, type, (event) {
      if (mounted) handler(event);
    });
  }

  void _handleFocusChanged() {
    _record('native_textarea_focus_node_changed');
    updateKeepAlive();
    _syncDomFocus();
  }

  void _syncFromController() {
    if (_syncingFromBrowser) return;
    final textarea = _element;
    if (textarea == null) return;
    final value = widget.controller.value;
    if (textarea.value != value.text) {
      // Assigning `value` resets the caret to the end and clears the native
      // undo history, so it only happens for real text changes, and the
      // controller's selection is restored straight after.
      textarea.value = value.text;
      _applyControllerSelection(textarea);
    } else if (value.selection != _exchangedSelection &&
        web.document.activeElement == textarea) {
      _applyControllerSelection(textarea);
    }
  }

  void _applyControllerSelection(web.HTMLTextAreaElement textarea) {
    final selection = widget.controller.selection;
    if (!selection.isValid) return;
    final length = textarea.value.length;
    final base = selection.baseOffset.clamp(0, length);
    final extent = selection.extentOffset.clamp(0, length);
    textarea.setSelectionRange(
      base < extent ? base : extent,
      base < extent ? extent : base,
      base > extent ? 'backward' : 'forward',
    );
    _exchangedSelection = selection;
  }

  /// A selection drag fires `selectionchange` for every pointer move, and
  /// every controller notification reaches the app's listeners; only the
  /// settled selection is forwarded.
  void _scheduleSelectionSync() {
    _pendingSelectionSync?.cancel();
    _pendingSelectionSync = Timer(const Duration(milliseconds: 50), () {
      if (mounted) _syncSelectionFromDom();
    });
  }

  void _syncSelectionFromDom() {
    _pendingSelectionSync?.cancel();
    final textarea = _element;
    if (textarea == null) return;
    // While the DOM is ahead of the controller (its `input` event is still
    // pending, e.g. during IME composition) the DOM offsets may not fit the
    // controller's text; the `input` handler syncs both together.
    if (textarea.value != widget.controller.text) return;
    final selection = _domSelection(textarea);
    _exchangedSelection = selection;
    if (widget.controller.selection == selection) return;
    _syncingFromBrowser = true;
    try {
      widget.controller.selection = selection;
    } finally {
      _syncingFromBrowser = false;
    }
  }

  void _syncDomFocus() {
    final textarea = _element;
    if (textarea == null) return;
    final active = web.document.activeElement == textarea;
    if (_focusNode.hasFocus && !active) {
      _record('native_textarea_focus_dom_requested', includeViewport: true);
      textarea.focus();
      _applyControllerSelection(textarea);
    } else if (!_focusNode.hasFocus && active) {
      _record('native_textarea_blur_dom_requested', includeViewport: true);
      textarea.blur();
    }
  }

  /// Diagnostics are recorded on every keystroke, so they must stay cheap:
  /// nothing here may read computed style or element geometry, which would
  /// force a synchronous layout. Viewport geometry is attached only to focus
  /// transitions, where the soft keyboard makes it relevant.
  void _record(
    String event, {
    bool includeViewport = false,
    Map<String, Object?> extra = const {},
  }) {
    final textarea = _element;
    ClientDiagnostics.instance.record(event, {
      'instance_id': _instanceId,
      'mounted': mounted,
      'dom_has_focus': _domHasFocus,
      'focus_node_has_focus': _focusNode.hasFocus,
      'is_active_element':
          textarea != null && web.document.activeElement == textarea,
      'applied_font_size': _appliedCss['font-size'],
      if (includeViewport) ...clientViewportDiagnostics(),
      ...extra,
    });
  }
}

TextSelection _domSelection(web.HTMLTextAreaElement textarea) {
  final start = textarea.selectionStart;
  final end = textarea.selectionEnd;
  return textarea.selectionDirection == 'backward'
      ? TextSelection(baseOffset: end, extentOffset: start)
      : TextSelection(baseOffset: start, extentOffset: end);
}

/// DOM listeners owned by one textarea binding, removable as a group.
class _DomListeners {
  final List<(web.EventTarget, String, JSFunction)> _entries = [];

  void add(
    web.EventTarget target,
    String type,
    void Function(web.Event event) handler,
  ) {
    final callback = handler.toJS;
    target.addEventListener(type, callback);
    _entries.add((target, type, callback));
  }

  void removeAll() {
    for (final (target, type, callback) in _entries) {
      target.removeEventListener(type, callback);
    }
    _entries.clear();
  }
}
