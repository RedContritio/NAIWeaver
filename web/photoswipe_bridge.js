import PhotoSwipe from './vendor/photoswipe/photoswipe.esm.min.js';

const mountedGalleries = new WeakMap();

function nextFrame() {
  return new Promise((resolve) => requestAnimationFrame(resolve));
}

async function waitUntilVisible(host, generation) {
  while (
    mountedGalleries.get(host)?.generation === generation &&
    (!host.isConnected || host.clientWidth === 0 || host.clientHeight === 0)
  ) {
    await nextFrame();
  }
}

function readImageSize(src, fallbackWidth, fallbackHeight) {
  if (fallbackWidth > 0 && fallbackHeight > 0) {
    return Promise.resolve({ width: fallbackWidth, height: fallbackHeight });
  }
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

async function hydrateItems(items) {
  return Promise.all(items.map(async (item) => {
    const size = await readImageSize(item.src, item.width, item.height);
    return {
      id: item.id,
      src: item.src,
      width: size.width,
      height: size.height,
      alt: item.alt || '',
    };
  }));
}

function destroyMounted(host) {
  const mounted = mountedGalleries.get(host);
  if (!mounted) return;
  mountedGalleries.delete(host);
  mounted.resizeObserver?.disconnect();
  mounted.pswp?.destroy();
  host.replaceChildren();
}

async function mount(host, configJson, onChange) {
  destroyMounted(host);
  const config = JSON.parse(configJson);
  const generation = Symbol('gallery-generation');
  const state = {
    generation,
    pswp: null,
    resizeObserver: null,
    onChange,
    sourceKey: config.sourceKey,
    pendingIndex: config.index,
  };
  mountedGalleries.set(host, state);

  await waitUntilVisible(host, generation);
  if (!host.isConnected || mountedGalleries.get(host)?.generation !== generation) {
    return;
  }

  const items = await hydrateItems(config.items);
  if (!host.isConnected || mountedGalleries.get(host)?.generation !== generation) {
    return;
  }

  const pswp = new PhotoSwipe({
    dataSource: items,
    index: Math.max(0, Math.min(state.pendingIndex, items.length - 1)),
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
    close: false,
    zoom: true,
    counter: items.length > 1,
    arrowPrev: items.length > 1,
    arrowNext: items.length > 1,
    preload: [1, 2],
  });

  const markNativeImage = (content) => {
    content?.element?.classList?.add('naiweaver-native-image');
  };
  pswp.on('contentAppend', ({ content }) => markNativeImage(content));
  pswp.on('contentActivate', ({ content }) => markNativeImage(content));
  pswp.on('change', () => {
    const current = items[pswp.currIndex];
    if (current) state.onChange(pswp.currIndex);
  });
  pswp.init();
  state.pswp = pswp;

  const resizeObserver = new ResizeObserver(() => pswp.updateSize(true));
  resizeObserver.observe(host);
  state.resizeObserver = resizeObserver;
}

function update(host, configJson) {
  const config = JSON.parse(configJson);
  const mounted = mountedGalleries.get(host);
  if (!mounted) return;
  if (mounted.sourceKey !== config.sourceKey) {
    mount(host, configJson, mounted.onChange);
    return;
  }
  mounted.pendingIndex = config.index;
  if (mounted.pswp && mounted.pswp.currIndex !== config.index) {
    mounted.pswp.goTo(config.index);
  }
}

window.naiweaverPhotoSwipe = {
  mount,
  update,
  dispose: destroyMounted,
};
