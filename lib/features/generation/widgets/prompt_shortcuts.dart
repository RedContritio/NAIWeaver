import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/widgets/browser_native_key_event.dart';

/// One keyboard vocabulary for every prompt editor.
///
/// Flutter key events (desktop and mobile text fields) and DOM keydown events
/// (the browser-native textarea) are both turned into a [PromptChord], mapped
/// to an [Intent] by [promptIntentFor], and run through the same [Actions]
/// tree. The page owns the actions that are not about one field (generate,
/// cycle style, see [GenerationShortcuts]); each editor owns the weight and
/// completion actions that act on its text.

/// Starts a generation.
class GenerateIntent extends Intent {
  const GenerateIntent();
}

/// Nudges the weight of the tag under the caret.
class AdjustTagWeightIntent extends Intent {
  const AdjustTagWeightIntent(this.delta);

  final double delta;
}

/// Activates the next (or previous) style.
class CycleStyleIntent extends Intent {
  const CycleStyleIntent({required this.forward});

  final bool forward;
}

/// Moves the highlight to the next completion.
class NextSuggestionIntent extends Intent {
  const NextSuggestionIntent();
}

/// Moves the highlight to the previous completion.
class PreviousSuggestionIntent extends Intent {
  const PreviousSuggestionIntent();
}

/// Inserts the highlighted completion.
class AcceptSuggestionIntent extends Intent {
  const AcceptSuggestionIntent();
}

/// Closes the completion list without inserting anything.
class DismissSuggestionsIntent extends Intent {
  const DismissSuggestionsIntent();
}

/// The keys the prompt shortcuts care about.
enum PromptKey { enter, tab, escape, arrowUp, arrowDown, arrowLeft, arrowRight }

/// A key press stripped of its source (Flutter or DOM).
class PromptChord {
  const PromptChord(
    this.key, {
    this.control = false,
    this.meta = false,
    this.alt = false,
    this.shift = false,
  });

  final PromptKey key;
  final bool control;
  final bool meta;
  final bool alt;
  final bool shift;

  /// The chord of a Flutter key press, or null for a key that is not bound.
  static PromptChord? fromKeyEvent(KeyEvent event) {
    final key = _flutterKeys[event.logicalKey];
    if (key == null) return null;
    final keyboard = HardwareKeyboard.instance;
    return PromptChord(
      key,
      control: keyboard.isControlPressed,
      meta: keyboard.isMetaPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
    );
  }

  /// The chord of a DOM keydown, or null for a key that is not bound.
  static PromptChord? fromBrowserEvent(BrowserNativeKeyEvent event) {
    final key = _domKeys[event.key];
    if (key == null) return null;
    return PromptChord(
      key,
      control: event.control,
      meta: event.meta,
      alt: event.alt,
      shift: event.shift,
    );
  }

  static final Map<LogicalKeyboardKey, PromptKey> _flutterKeys = {
    LogicalKeyboardKey.enter: PromptKey.enter,
    LogicalKeyboardKey.numpadEnter: PromptKey.enter,
    LogicalKeyboardKey.tab: PromptKey.tab,
    LogicalKeyboardKey.escape: PromptKey.escape,
    LogicalKeyboardKey.arrowUp: PromptKey.arrowUp,
    LogicalKeyboardKey.arrowDown: PromptKey.arrowDown,
    LogicalKeyboardKey.arrowLeft: PromptKey.arrowLeft,
    LogicalKeyboardKey.arrowRight: PromptKey.arrowRight,
  };

  static const Map<String, PromptKey> _domKeys = {
    'Enter': PromptKey.enter,
    'Tab': PromptKey.tab,
    'Escape': PromptKey.escape,
    'ArrowUp': PromptKey.arrowUp,
    'ArrowDown': PromptKey.arrowDown,
    'ArrowLeft': PromptKey.arrowLeft,
    'ArrowRight': PromptKey.arrowRight,
  };
}

/// True on Apple platforms (macOS, iOS), including the Web on a Mac, where
/// [defaultTargetPlatform] follows the browser's platform.
bool usesCommandKey([TargetPlatform? platform]) {
  final target = platform ?? defaultTargetPlatform;
  return target == TargetPlatform.macOS || target == TargetPlatform.iOS;
}

/// The step one weight shortcut applies.
const double kTagWeightStep = 0.1;

/// Maps [chord] to the intent it triggers, or null.
///
/// The command modifier is Cmd on Apple platforms and Ctrl elsewhere; the
/// other one never counts, so the system's own Cmd+Arrow (macOS) and
/// Ctrl+Arrow (elsewhere) navigation stays distinguishable.
Intent? promptIntentFor(PromptChord chord, {TargetPlatform? platform}) {
  final apple = usesCommandKey(platform);
  final command = apple
      ? chord.meta && !chord.control
      : chord.control && !chord.meta;
  final noCommand = !chord.control && !chord.meta;
  switch (chord.key) {
    case PromptKey.enter:
      if (command && !chord.alt) return const GenerateIntent();
      if (noCommand && !chord.alt && !chord.shift) {
        return const AcceptSuggestionIntent();
      }
      return null;
    case PromptKey.arrowUp:
    case PromptKey.arrowDown:
      if (!command || chord.alt) return null;
      return AdjustTagWeightIntent(
        chord.key == PromptKey.arrowUp ? kTagWeightStep : -kTagWeightStep,
      );
    case PromptKey.arrowLeft:
    case PromptKey.arrowRight:
      // Alt+Arrow leaves the OS word-by-word selection (Ctrl/Cmd+Shift+Arrow)
      // free.
      if (!chord.alt || !noCommand) return null;
      return CycleStyleIntent(forward: chord.key == PromptKey.arrowRight);
    case PromptKey.tab:
      if (!noCommand || chord.alt) return null;
      return chord.shift
          ? const PreviousSuggestionIntent()
          : const NextSuggestionIntent();
    case PromptKey.escape:
      if (!noCommand || chord.alt || chord.shift) return null;
      return const DismissSuggestionsIntent();
  }
}

/// Runs [intent] on the nearest action above [context]. Returns false when
/// no enabled action takes it, so the key can fall through.
bool dispatchPromptIntent(BuildContext context, Intent intent) {
  final action = Actions.maybeFind<Intent>(context, intent: intent);
  if (action == null || !action.isEnabled(intent)) return false;
  Actions.of(context).invokeAction(action, intent, context);
  return true;
}

/// True while an input method holds an uncommitted composition (Chinese,
/// Japanese, ...). Enter and Tab belong to the IME then.
bool isImeComposing(TextEditingController controller) {
  final composing = controller.value.composing;
  return composing.isValid && !composing.isCollapsed;
}

bool _isCompositionKey(PromptChord chord) =>
    chord.key == PromptKey.enter || chord.key == PromptKey.tab;

/// An [Action] that can switch itself off, so an intent it cannot serve
/// right now (no completions, ...) lets the key through.
class PromptAction<T extends Intent> extends Action<T> {
  PromptAction({required this.onInvoke, this.enabled});

  final void Function(T intent) onInvoke;
  final bool Function()? enabled;

  @override
  bool isEnabled(T intent) => enabled?.call() ?? true;

  @override
  Object? invoke(T intent) {
    onInvoke(intent);
    return null;
  }
}

/// Page-level shortcuts: generate and cycle style work wherever the focus is.
/// [onGenerate] and [onCycleStyle] are the only places those two are
/// implemented.
class GenerationShortcuts extends StatelessWidget {
  const GenerationShortcuts({
    super.key,
    required this.onGenerate,
    required this.onCycleStyle,
    required this.child,
  });

  final VoidCallback onGenerate;
  final ValueChanged<bool> onCycleStyle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        GenerateIntent: PromptAction<GenerateIntent>(
          onInvoke: (_) => onGenerate(),
        ),
        CycleStyleIntent: PromptAction<CycleStyleIntent>(
          onInvoke: (intent) => onCycleStyle(intent.forward),
        ),
      },
      child: Builder(
        builder: (scope) => Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final chord = PromptChord.fromKeyEvent(event);
            final intent = chord == null ? null : promptIntentFor(chord);
            if (intent is! GenerateIntent && intent is! CycleStyleIntent) {
              return KeyEventResult.ignored;
            }
            return dispatchPromptIntent(scope, intent!)
                ? KeyEventResult.handled
                : KeyEventResult.ignored;
          },
          child: child,
        ),
      ),
    );
  }
}

/// Wires one prompt editor to the shared shortcuts. [builder] receives the
/// handler for the browser-native textarea's keydown, so the Flutter
/// `TextField` fallback and the DOM textarea inside it run the same code.
///
/// Handles weight up/down for [controller] itself; [actions] adds the
/// editor's completion actions. Generate and cycle style come from the
/// enclosing [GenerationShortcuts]. Enter and Tab are never taken while an
/// input method is composing.
class PromptKeyScope extends StatelessWidget {
  const PromptKeyScope({
    super.key,
    required this.controller,
    required this.builder,
    this.actions = const {},
  });

  final TextEditingController controller;
  final Map<Type, Action<Intent>> actions;
  final Widget Function(BuildContext context, BrowserNativeKeyHandler onKeyDown)
  builder;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        AdjustTagWeightIntent: PromptAction<AdjustTagWeightIntent>(
          onInvoke: (intent) => adjustTagWeight(controller, intent.delta),
        ),
        ...actions,
      },
      child: Builder(
        builder: (scope) => Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final chord = PromptChord.fromKeyEvent(event);
            if (chord == null) return KeyEventResult.ignored;
            if (_isCompositionKey(chord) && isImeComposing(controller)) {
              return KeyEventResult.skipRemainingHandlers;
            }
            final intent = promptIntentFor(chord);
            if (intent == null) return KeyEventResult.ignored;
            return dispatchPromptIntent(scope, intent)
                ? KeyEventResult.handled
                : KeyEventResult.ignored;
          },
          child: builder(scope, (event) {
            final chord = PromptChord.fromBrowserEvent(event);
            if (chord == null) return false;
            if (_isCompositionKey(chord) &&
                (event.isComposing || isImeComposing(controller))) {
              return false;
            }
            final intent = promptIntentFor(chord);
            return intent != null && dispatchPromptIntent(scope, intent);
          }),
        ),
      ),
    );
  }
}

/// Moves the weight of the comma-delimited tag under the caret by [delta]
/// (NAI `1.2::tag::` syntax; legacy `{tag:1.2}` and `{tag}` are upgraded).
void adjustTagWeight(TextEditingController controller, double delta) {
  final text = controller.text;
  final sel = controller.selection;
  if (!sel.isValid || sel.baseOffset < 0) return;
  final cursor = sel.baseOffset;

  // Find tag boundaries (comma-delimited)
  final start = text.lastIndexOf(',', cursor - 1) + 1;
  var end = text.indexOf(',', cursor);
  if (end < 0) end = text.length;

  final tag = text.substring(start, end).trim();
  if (tag.isEmpty) return;

  // Parse existing weight: value::tag:: (NAI format) or legacy {tag:weight}
  var weight = 1.0;
  var bareTag = tag;

  final naiMatch = RegExp(r'^(-?[0-9.]+)::(.+)::$').firstMatch(tag);
  final legacyMatch = RegExp(r'^\{(.+):([0-9.-]+)\}$').firstMatch(tag);

  if (naiMatch != null) {
    weight = double.tryParse(naiMatch.group(1)!) ?? 1.0;
    bareTag = naiMatch.group(2)!;
  } else if (legacyMatch != null) {
    bareTag = legacyMatch.group(1)!;
    weight = double.tryParse(legacyMatch.group(2)!) ?? 1.0;
  } else if (tag.startsWith('{') && tag.endsWith('}')) {
    bareTag = tag.substring(1, tag.length - 1);
    weight = 1.05;
  }

  weight = ((weight + delta) * 10).round() / 10;

  final result = (weight - 1.0).abs() < 0.01
      ? bareTag
      : '${weight.toStringAsFixed(1)}::$bareTag::';

  // Preserve spacing
  final prefix = text.substring(
    start,
    start +
        (text.substring(start).length - text.substring(start).trimLeft().length),
  );
  final newText =
      text.substring(0, start) + prefix + result + text.substring(end);
  controller.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(
      offset: start + prefix.length + result.length,
    ),
  );
}
