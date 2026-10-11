import PhotoSwipe from './vendor/photoswipe/photoswipe.esm.min.js';
import { photoSwipeKeyAction } from './photoswipe_key_policy.js';

// host element -> gallery state. A state stays registered from mount() until
// dispose(); every async step re-checks that it is still the registered one.
const galleries = new WeakMap();

function isCurrent(host, state) {
  return galleries.get(host) === state;
}

function isVisible(host) {
  return host.isConnected && host.clientWidth > 0 && host.clientHeight > 0;
}

// PhotoSwipe measures its viewport on init, so wait until Flutter has
// composited the platform view and given it a size. Resolves early when the
// gallery is disposed first.
function waitUntilVisible(host, state) {
  if (isVisible(host)) return Promise.resolve();
  return new Promise((resolve) => {
    const observer = new ResizeObserver(() => {
      if (isCurrent(host, state) && !isVisible(host)) return;
      stop();
    });
    const stop = () => {
      observer.disconnect();
      state.cancelWait = null;
      resolve();
    };
    state.cancelWait = stop;
    observer.observe(host);
  });
}

function readImageSize(src) {
  return new Promise((resolve) => {
    const image = new Image();
    image.decoding = 'async';
    image.onload = () => resolve({
      width: image.naturalWidth || 1,
      height: image.naturalHeight || 1,
    });
    image.onerror = () => resolve({ width: 1, height: 1 });
    image.src = src;
  });
}

// Slides normally arrive with their pixel size. Only sizeless slides are
// decoded, once per source.
async function hydrate(state, rawItems) {
  const items = await Promise.all(rawItems.map(async (item) => {
    let size = item.width > 0 && item.height > 0
      ? { width: item.width, height: item.height }
      : state.sizes.get(item.src);
    if (!size) {
      size = await readImageSize(item.src);
      state.sizes.set(item.src, size);
    }
    return {
      id: item.id,
      src: item.src,
      width: size.width,
      height: size.height,
      alt: item.alt || '',
    };
  }));
  const liveSources = new Set(items.map((item) => item.src));
  for (const src of state.sizes.keys()) {
    if (!liveSources.has(src)) state.sizes.delete(src);
  }
  return items;
}

function clampIndex(index, count) {
  return Math.max(0, Math.min(index, count - 1));
}

function sameSlide(a, b) {
  return a !== undefined
    && a.id === b.id
    && a.src === b.src
    && a.width === b.width
    && a.height === b.height;
}

// Programmatic changes (Flutter selecting another result, slides being
// refreshed) also fire PhotoSwipe's `change` event; only user navigation may
// be reported back, or it would override Flutter's own selection.
function withoutChangeReports(state, action) {
  state.applying = true;
  try {
    action();
  } finally {
    state.applying = false;
  }
}

function handleKeydown(host, pswp, event) {
  const original = event.originalEvent;
  const target = original.target;
  const action = photoSwipeKeyAction({
    insideViewer: target instanceof Node && host.contains(target),
    key: original.key,
    ctrlKey: original.ctrlKey,
    metaKey: original.metaKey,
    altKey: original.altKey,
    shiftKey: original.shiftKey,
    slideCount: pswp.getNumItems(),
  });
  if (action === 'default') return;
  // Prevent PhotoSwipe's built-in handling; the DOM event itself is left
  // untouched for keys that belong to the rest of the page.
  event.preventDefault();
  if (action === 'ignore') return;
  original.preventDefault();
  if (action === 'previous') {
    pswp.prev();
  } else {
    pswp.next();
  }
}

function createGallery(host, state, items, index) {
  const pswp = new PhotoSwipe({
    dataSource: items,
    index,
    appendToEl: host,
    getViewportSizeFn: () => ({
      x: host.clientWidth,
      y: host.clientHeight,
    }),
    mainClass: 'naiweaver-embedded-pswp',
    showHideAnimationType: 'none',
    bgOpacity: 1,
    loop: false,
    wheelToZoom: true,
    allowPanToNext: true,
    pinchToClose: false,
    closeOnVerticalDrag: false,
    clickToCloseNonZoomable: false,
    imageClickAction: false,
    tapAction: false,
    doubleTapAction: 'zoom',
    trapFocus: false,
    returnFocus: false,
    escKey: false,
    arrowKeys: false,
    close: false,
    zoom: true,
    // Always created; PhotoSwipe hides them via `.pswp--one-slide` while the
    // gallery holds a single slide, so they appear once more results arrive.
    counter: true,
    arrowPrev: true,
    arrowNext: true,
    preload: [1, 2],
  });

  const markNativeImage = (content) => {
    content?.element?.classList?.add('naiweaver-native-image');
  };
  pswp.on('contentAppend', ({ content }) => markNativeImage(content));
  pswp.on('contentActivate', ({ content }) => markNativeImage(content));
  pswp.on('change', () => {
    if (state.applying) return;
    const current = state.items[pswp.currIndex];
    if (current) state.onChange(current.id);
  });
  pswp.on('keydown', (event) => handleKeydown(host, pswp, event));
  return pswp;
}

// Brings a live gallery to `items` without recreating it: only slides whose
// content changed are re-rendered, so the visible image neither flashes nor
// loses its zoom when new results are appended.
function applyItems(state, items, requestedIndex) {
  const { pswp } = state;
  const previous = state.items;
  state.items = items;
  pswp.options.dataSource = items;
  withoutChangeReports(state, () => {
    if (pswp.currIndex >= items.length) pswp.goTo(items.length - 1);
    let refreshed = false;
    items.forEach((item, index) => {
      if (sameSlide(previous[index], item)) return;
      pswp.refreshSlideContent(index);
      refreshed = true;
    });
    // refreshSlideContent() emits `change`, which updates the counter and
    // arrow buttons; a pure removal at the end has to emit it explicitly.
    if (!refreshed && previous.length !== items.length) {
      pswp.dispatch('change');
    }
    const index = clampIndex(requestedIndex, items.length);
    if (pswp.currIndex !== index) pswp.goTo(index);
  });
}

function destroyGallery(host) {
  const state = galleries.get(host);
  if (!state) return;
  galleries.delete(host);
  state.cancelWait?.();
  state.resizeObserver?.disconnect();
  state.pswp?.destroy();
  host.replaceChildren();
}

async function mount(host, configJson, onChange) {
  destroyGallery(host);
  const state = {
    config: JSON.parse(configJson),
    onChange,
    items: [],
    sizes: new Map(),
    pswp: null,
    resizeObserver: null,
    cancelWait: null,
    applying: false,
    revision: 0,
  };
  galleries.set(host, state);
  try {
    await waitUntilVisible(host, state);
    if (!isCurrent(host, state)) return false;
    // update() calls that arrive while waiting only replace state.config.
    let config;
    let items;
    do {
      config = state.config;
      items = await hydrate(state, config.items);
      if (!isCurrent(host, state)) return false;
    } while (config !== state.config);
    if (items.length === 0) {
      destroyGallery(host);
      return false;
    }

    state.items = items;
    withoutChangeReports(state, () => {
      state.pswp = createGallery(
        host,
        state,
        items,
        clampIndex(config.index, items.length),
      );
      state.pswp.init();
    });
    state.resizeObserver = new ResizeObserver(() => state.pswp?.updateSize(true));
    state.resizeObserver.observe(host);
    return true;
  } catch (error) {
    if (isCurrent(host, state)) destroyGallery(host);
    throw error;
  }
}

async function update(host, configJson) {
  const state = galleries.get(host);
  if (!state) return false;
  const config = JSON.parse(configJson);
  state.config = config;
  // A mount still in progress picks up state.config when it gets there.
  if (!state.pswp) return true;
  const revision = ++state.revision;
  const items = await hydrate(state, config.items);
  if (!isCurrent(host, state) || revision !== state.revision) return false;
  if (items.length === 0) return false;
  applyItems(state, items, config.index);
  return true;
}

async function dispose(host) {
  destroyGallery(host);
  return true;
}

window.naiweaverPhotoSwipe = {
  mount,
  update,
  dispose,
};
