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
    this.keyCode = 0,
  });

  /// The DOM `KeyboardEvent.key` value, e.g. `Enter` or `ArrowUp`.
  final String key;
  final bool control;
  final bool meta;
  final bool alt;
  final bool shift;

  /// True while an input method (IME) has an uncommitted composition.
  final bool isComposing;

  /// The legacy `KeyboardEvent.keyCode`. Browsers report 229 for a key the
  /// input method processed.
  final int keyCode;

  /// True while an input method owns the key. Safari fires `compositionend`
  /// before the keydown of the Enter that confirmed the composition, so that
  /// keydown has `isComposing == false` and only `keyCode == 229`.
  bool get imeActive => isComposing || keyCode == 229;
}

/// Returns true when the key was consumed (the browser default is prevented).
typedef BrowserNativeKeyHandler = bool Function(BrowserNativeKeyEvent event);
