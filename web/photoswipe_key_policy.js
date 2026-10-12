/**
 * Keyboard policy for the embedded PhotoSwipe viewer.
 *
 * PhotoSwipe listens for `keydown` on `document`, so it sees every key typed
 * anywhere in the app, Flutter text fields included: "z" toggles zoom, the
 * arrow keys switch slides (which also turns off auto-follow), Tab pulls
 * focus into the viewer. This decides what the viewer does with one keydown:
 *
 * - 'ignore'   the key belongs to something outside the viewer; PhotoSwipe
 *              must not act on it.
 * - 'previous' / 'next'
 *              a plain Left/Right arrow while focus is inside the viewer
 *              steps through the slides. PhotoSwipe's own arrow navigation is
 *              disabled (`arrowKeys: false`) so this is the only path.
 * - 'default'  let PhotoSwipe handle it (zoom with "z", panning with
 *              Up/Down while zoomed, Escape, Tab).
 *
 * @param {object} key
 * @param {boolean} key.insideViewer the event target is inside the viewer host
 * @param {string} key.key `KeyboardEvent.key`
 * @param {boolean} [key.ctrlKey]
 * @param {boolean} [key.metaKey]
 * @param {boolean} [key.altKey]
 * @param {boolean} [key.shiftKey]
 * @param {number} key.slideCount number of slides in the gallery
 * @returns {'ignore' | 'previous' | 'next' | 'default'}
 */
export function photoSwipeKeyAction({
  insideViewer,
  key,
  ctrlKey = false,
  metaKey = false,
  altKey = false,
  shiftKey = false,
  slideCount,
}) {
  if (!insideViewer) return 'ignore';
  if (ctrlKey || metaKey || altKey || shiftKey || slideCount < 2) {
    return 'default';
  }
  if (key === 'ArrowLeft') return 'previous';
  if (key === 'ArrowRight') return 'next';
  return 'default';
}
