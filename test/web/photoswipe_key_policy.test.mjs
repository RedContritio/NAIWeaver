// Run with: node --test test/web/photoswipe_key_policy.test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { photoSwipeKeyAction } from '../../web/photoswipe_key_policy.js';

test('PhotoSwipe ignores keys typed outside the viewer', () => {
  // "z" toggles zoom, the arrows switch slides and Tab grabs focus when
  // PhotoSwipe handles them; typed into a text field they must do nothing.
  for (const key of ['z', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'Tab', 'Escape']) {
    assert.equal(
      photoSwipeKeyAction({ insideViewer: false, key, slideCount: 3 }),
      'ignore',
      key,
    );
    assert.notEqual(
      photoSwipeKeyAction({ insideViewer: true, key, slideCount: 3 }),
      'ignore',
      `${key} inside the viewer`,
    );
  }
});
