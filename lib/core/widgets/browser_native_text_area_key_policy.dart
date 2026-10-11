import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keyboard routing for the browser-native prompt editor.
///
/// A keydown aimed at the DOM textarea reaches Flutter first: the engine
/// listens on `window` in the *capture* phase and dispatches the key to the
/// primary [FocusNode], which is the editor's own node while the textarea has
/// DOM focus. If an ancestor `Shortcuts` claims the key (WidgetsApp's Web
/// defaults turn Space into a page scroll and the arrow keys into
/// `ScrollIntent`s), the engine calls `preventDefault()` and the textarea
/// never inserts the space or moves the caret. Nothing the textarea does in
/// its own listener can undo that, because the decision is made before the
/// event reaches the element.
///
/// [browserNativeTextAreaShortcuts] is therefore installed directly above the
/// editor's focus node. It binds the keys the browser must keep to
/// [DoNothingAndStopPropagationIntent] — the same technique `EditableText`
/// uses on the Web — which stops Flutter's key bubbling at the editor and
/// reports the event as unhandled, so the browser performs its default action.
/// Modified combinations such as Ctrl+Arrow or Alt+Arrow are left alone so
/// application shortcuts above the editor keep working.
final Map<ShortcutActivator, Intent> browserNativeTextAreaShortcuts = {
  for (final shift in const [false, true])
    for (final key in _selectionKeys)
      SingleActivator(key, shift: shift):
          const DoNothingAndStopPropagationIntent(),
  const SingleActivator(LogicalKeyboardKey.space):
      const DoNothingAndStopPropagationIntent(),
};

const List<LogicalKeyboardKey> _selectionKeys = [
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.pageUp,
  LogicalKeyboardKey.pageDown,
  LogicalKeyboardKey.home,
  LogicalKeyboardKey.end,
];

/// What the textarea's own (target-phase) keydown listener does with a key.
///
/// By the time this listener runs, Flutter has already seen the key (see
/// above), so the policy cannot influence Flutter shortcuts. It only governs
/// the DOM:
///
/// * a key the `onKeyDown` callback handled suppresses the browser's default
///   action (e.g. no newline for a handled Enter);
/// * every key stops propagating, so document- and window-level *bubble*
///   listeners (such as PhotoSwipe's document keydown handler) never react to
///   text typed into the editor.
({bool preventDefault, bool stopPropagation}) browserNativeTextAreaKeyPolicy(
  bool handled,
) => (preventDefault: handled, stopPropagation: true);
