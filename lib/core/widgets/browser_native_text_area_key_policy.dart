/// DOM event policy for the browser-native prompt editor.
///
/// Handled application shortcuts suppress the browser action as well as event
/// propagation. Ordinary text-editing keys keep the browser's default action
/// (so Space inserts a space) but do not bubble into Flutter's global keyboard
/// dispatcher.
({bool preventDefault, bool stopPropagation}) browserNativeTextAreaKeyPolicy(
  bool handled,
) => (preventDefault: handled, stopPropagation: true);
