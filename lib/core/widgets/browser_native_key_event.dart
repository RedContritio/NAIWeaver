/// A keydown reported by the browser-native textarea, with the modifiers kept
/// apart so callers can choose Command or Control per platform.
class BrowserNativeKeyEvent {
  const BrowserNativeKeyEvent({
    required this.key,
    this.control = false,
    this.meta = false,
    this.alt = false,
    this.shift = false,
    this.isComposing = false,
  });

  /// The DOM `KeyboardEvent.key` value, e.g. `Enter` or `ArrowUp`.
  final String key;
  final bool control;
  final bool meta;
  final bool alt;
  final bool shift;

  /// True while an input method (IME) has an uncommitted composition.
  final bool isComposing;
}

/// Returns true when the key was consumed (the browser default is prevented).
typedef BrowserNativeKeyHandler = bool Function(BrowserNativeKeyEvent event);
