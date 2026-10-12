import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extensions.dart';
import '../../../core/services/preferences_service.dart';
import '../../../core/services/tag_service.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../core/theme/vision_metrics.dart';
import '../../../core/utils/resizable_lines.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/browser_native_text_area.dart';
import '../../../core/widgets/tag_suggestion_overlay.dart';
import 'generation_page_layout.dart';
import 'prompt_shortcuts.dart';

/// Where the main prompt sits. Each place has its own room and default
/// height, so each remembers its own number of lines.
enum PromptLayoutSlot {
  /// The page footer of the bottom-panel and sidebar-right layouts.
  footer,

  /// Inside the expanded bottom settings panel.
  panel,

  /// Inside the touch-sized bottom sheet.
  sheet,

  /// At the foot of the left sidebar.
  sidebar;

  bool get embedded => this == panel || this == sheet;
}

/// The main prompt editor: the completion list, the resizable text field and
/// the action rail beside it.
///
/// It owns what only the editor needs: the focus node, the highlighted
/// completion, the number of lines, the blur clean-up and the key handling
/// (see `prompt_shortcuts.dart`), so typing does not rebuild the page. The
/// page supplies the text, the completions and what to do with them.
class PromptComposer extends StatefulWidget {
  const PromptComposer({
    super.key,
    required this.controller,
    required this.suggestions,
    required this.slot,
    required this.defaultLines,
    required this.action,
    required this.onTextChanged,
    required this.onSuggestionAccepted,
    required this.onSuggestionsDismissed,
    this.onFocusGained,
    this.shelf,
    this.seedControl,
  });

  static const fieldKey = ValueKey<String>('prompt-composer-field');

  final TextEditingController controller;

  /// The completions for the word under the caret.
  final List<DanbooruTag> suggestions;
  final PromptLayoutSlot slot;

  /// Lines to show until the user has resized this slot.
  final int defaultLines;

  /// The generate button and cost block, beside the field.
  final Widget action;

  /// Called with the new text on every edit.
  final ValueChanged<String> onTextChanged;

  /// Called to insert a completion (chip tap or Enter).
  final ValueChanged<DanbooruTag> onSuggestionAccepted;

  /// Called to close the completion list.
  final VoidCallback onSuggestionsDismissed;
  final VoidCallback? onFocusGained;

  /// Optional content above the completions (the character shelf).
  final Widget? shelf;

  /// Optional content between the completions and the field.
  final Widget? seedControl;

  @override
  State<PromptComposer> createState() => PromptComposerState();
}

class PromptComposerState extends State<PromptComposer> {
  static const Duration _blurGrace = Duration(milliseconds: 200);
  static const Duration _touchGrace = Duration(milliseconds: 300);

  final FocusNode _focusNode = FocusNode(debugLabel: 'main-prompt');
  late final Map<Type, Action<Intent>> _suggestionActions = {
    NextSuggestionIntent: PromptAction<NextSuggestionIntent>(
      enabled: () => widget.suggestions.isNotEmpty,
      onInvoke: (_) => setState(
        () => _selected = (_selected + 1) % widget.suggestions.length,
      ),
    ),
    PreviousSuggestionIntent: PromptAction<PreviousSuggestionIntent>(
      enabled: () => widget.suggestions.isNotEmpty,
      onInvoke: (_) => setState(
        () => _selected = (_selected - 1).clamp(
          -1,
          widget.suggestions.length - 1,
        ),
      ),
    ),
    AcceptSuggestionIntent: PromptAction<AcceptSuggestionIntent>(
      enabled: () => _selected >= 0 && _selected < widget.suggestions.length,
      onInvoke: (_) => _accept(widget.suggestions[_selected]),
    ),
    DismissSuggestionsIntent: PromptAction<DismissSuggestionsIntent>(
      enabled: () => widget.suggestions.isNotEmpty,
      onInvoke: (_) => _dismiss(),
    ),
  };

  int _selected = -1;
  int? _savedLines;
  int? _dragLines;
  bool _touchingSuggestions = false;
  bool _hadFocus = false;
  Timer? _blurTimer;
  Timer? _touchTimer;

  /// The editor's focus node, for callers that need to know about focus.
  FocusNode get focusNode => _focusNode;

  /// Takes the focus away from the editor.
  void unfocus() => _focusNode.unfocus();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _savedLines ??= context.read<PreferencesService>().uiMainPromptLinesFor(
      widget.slot.name,
    );
  }

  @override
  void didUpdateWidget(PromptComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slot != widget.slot) {
      // The same editor moved to another layout: that layout's height applies.
      _dragLines = null;
      _savedLines = context.read<PreferencesService>().uiMainPromptLinesFor(
        widget.slot.name,
      );
    }
  }

  @override
  void dispose() {
    _blurTimer?.cancel();
    _touchTimer?.cancel();
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  int get _lines => (_dragLines ?? _savedLines ?? widget.defaultLines).clamp(
    kMainPromptMinLines,
    kMainPromptMaxLines,
  );

  /// The one place focus changes are handled: opening the sheet on focus, and
  /// closing the completions shortly after focus leaves (unless a chip is
  /// being pressed).
  void _onFocusChanged() {
    final hasFocus = _focusNode.hasFocus;
    if (hasFocus == _hadFocus) return;
    _hadFocus = hasFocus;
    if (hasFocus) {
      _blurTimer?.cancel();
      widget.onFocusGained?.call();
    } else {
      _scheduleDismiss();
    }
  }

  void _scheduleDismiss() {
    _blurTimer?.cancel();
    _blurTimer = Timer(_blurGrace, () {
      if (!mounted || _touchingSuggestions) return;
      _dismiss();
    });
  }

  void _dismiss() {
    widget.onSuggestionsDismissed();
    if (_selected != -1) setState(() => _selected = -1);
  }

  /// Inserts [tag] and hands the focus back to the editor, so the soft
  /// keyboard stays up for the next tag.
  void _accept(DanbooruTag tag) {
    widget.onSuggestionAccepted(tag);
    _blurTimer?.cancel();
    setState(() => _selected = -1);
    _focusNode.requestFocus();
  }

  void _onChanged(String text) {
    widget.onTextChanged(text);
    if (_selected != -1) setState(() => _selected = -1);
  }

  void _pressSuggestions(bool down) {
    _touchTimer?.cancel();
    if (down) {
      _touchingSuggestions = true;
    } else {
      _touchTimer = Timer(_touchGrace, () => _touchingSuggestions = false);
    }
  }

  void _resizeDone(int lines) {
    final clamped = lines.clamp(kMainPromptMinLines, kMainPromptMaxLines);
    setState(() {
      _savedLines = clamped;
      _dragLines = null;
    });
    unawaited(
      context.read<PreferencesService>().setUiMainPromptLinesFor(
        widget.slot.name,
        clamped,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final slot = widget.slot;
    final touch = windowSizeClassOf(context).isTouchSized;
    final padding = switch (slot) {
      PromptLayoutSlot.panel || PromptLayoutSlot.sheet => const EdgeInsets.all(
        VisionMetrics.space12,
      ).copyWith(top: VisionMetrics.space8, bottom: VisionMetrics.space8),
      PromptLayoutSlot.sidebar => const EdgeInsets.fromLTRB(
        VisionMetrics.space16,
        VisionMetrics.space8,
        VisionMetrics.space16,
        VisionMetrics.space12,
      ),
      PromptLayoutSlot.footer => const EdgeInsets.fromLTRB(
        VisionMetrics.space16,
        0,
        VisionMetrics.space16,
        VisionMetrics.space12,
      ),
    };
    final decoration = switch (slot) {
      PromptLayoutSlot.panel || PromptLayoutSlot.sheet => null,
      PromptLayoutSlot.sidebar => BoxDecoration(
        color: t.surfaceHigh,
        border: Border(top: BorderSide(color: t.borderMedium)),
      ),
      PromptLayoutSlot.footer => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            t.background.withValues(alpha: VisionMetrics.opacityOverlay),
            t.background,
          ],
          stops: const [0.4, 0.7, 1.0],
        ),
      ),
    };
    final fontSize = t.promptFontSize - 1;

    return Container(
      padding: padding,
      decoration: decoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?widget.shelf,
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _pressSuggestions(true),
            onPointerUp: (_) => _pressSuggestions(false),
            onPointerCancel: (_) => _pressSuggestions(false),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: TagSuggestionOverlay(
                suggestions: widget.suggestions,
                onTagSelected: _accept,
                selectedIndex: _selected,
              ),
            ),
          ),
          if (widget.seedControl != null)
            Padding(
              padding: const EdgeInsets.only(bottom: VisionMetrics.space8),
              child: widget.seedControl,
            ),
          ResizableGenerationComposer(
            promptLines: _lines,
            promptFontSize: fontSize,
            actionWidth: touch ? 72 : 68,
            onPromptLinesChanged: (lines) => setState(() => _dragLines = lines),
            onPromptResizeDone: _resizeDone,
            promptInput: PromptKeyScope(
              controller: widget.controller,
              actions: _suggestionActions,
              builder: (context, onKeyDown) => BrowserNativeTextArea(
                key: PromptComposer.fieldKey,
                controller: widget.controller,
                focusNode: _focusNode,
                hintText: context.l.mainEnterPrompt.toUpperCase(),
                style: TextStyle(fontSize: fontSize, letterSpacing: 0.5),
                backgroundColor: t.background.withValues(
                  alpha: VisionMetrics.opacityOverlay,
                ),
                borderColor: t.borderMedium,
                selectionColor: t.accent.withValues(
                  alpha: VisionMetrics.opacityOverlay,
                ),
                selectionTextColor: t.background,
                padding: const EdgeInsets.symmetric(
                  horizontal: VisionMetrics.space16,
                  vertical: VisionMetrics.space12,
                ),
                onChanged: _onChanged,
                onKeyDown: onKeyDown,
                fallback: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.stylus,
                    },
                  ),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    onChanged: _onChanged,
                    onTapOutside: (_) => _scheduleDismiss(),
                    style: TextStyle(fontSize: fontSize, letterSpacing: 0.5),
                    decoration: InputDecoration(
                      hintText: context.l.mainEnterPrompt.toUpperCase(),
                      hintStyle: TextStyle(
                        fontSize: t.fontSize(touch ? 12 : 9),
                        letterSpacing: 2,
                        color: t.hintText,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: VisionMetrics.space16,
                        vertical: VisionMetrics.space12,
                      ),
                      fillColor: t.background.withValues(
                        alpha: VisionMetrics.opacityOverlay,
                      ),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          VisionMetrics.radius4,
                        ),
                        borderSide: BorderSide(color: t.borderMedium),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          VisionMetrics.radius4,
                        ),
                        borderSide: BorderSide(color: t.borderMedium),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            action: widget.action,
          ),
        ],
      ),
    );
  }
}
