// Askance's service worker: keeps the app working with no signal.
//
// Flutter's own worker is deprecated and now ships as a stub that unregisters
// itself, so the bootstrap is told not to register it and this one is
// registered from index.html instead.
//
// Each deploy gets its own cache. `make deploy-web` replaces BUILD below with
// a hash of the build, which changes this file's bytes, which is what makes
// the browser install a new worker. index.html then promotes it and reloads.
//
// Nothing is listed up front beyond the page itself. The renderer comes in
// several builds and each browser loads only one, so the worker caches what
// this browser actually fetches: through the fetch handler once it controls
// the page, and on the very first visit (before it did) from the list the
// page posts once the app has drawn.
//
// Every network fetch revalidates ('no-cache'): an HTTP-cached file from the
// previous deploy stored beside this deploy's files would mix two builds,
// and main.dart.mjs and main.dart.wasm from different builds do not run.

const BUILD = 'dev';
const CACHE = `askance-${BUILD}`;

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => store(cache, './')));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const key of await caches.keys()) {
        if (key.startsWith('askance-') && key !== CACHE) {
          await caches.delete(key);
        }
      }
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
  } else if (event.data?.type === 'warm') {
    event.waitUntil(warm(event.data.urls));
  }
});

self.addEventListener('fetch', (event) => {
  // Unstamped means `flutter run`, whose files change under hot restart; a
  // cache there would serve yesterday's code.
  if (BUILD === 'dev') return;
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    // One page, whatever the query string: a shared link with tracking
    // parameters is still the app.
    event.respondWith(
      caches
        .match('./', { cacheName: CACHE })
        .then((hit) => hit || fetchAndStore(new URL('./', self.location).href))
        .catch(() => caches.match('./', { cacheName: CACHE })),
    );
    return;
  }

  event.respondWith(
    caches
      .match(request, { cacheName: CACHE })
      .then((hit) => hit || fetchAndStore(request.url)),
  );
});

async function fetchAndStore(url) {
  const response = await fetch(url, { cache: 'no-cache' });
  if (response.ok && response.type === 'basic') {
    const cache = await caches.open(CACHE);
    await cache.put(url, response.clone());
  }
  return response;
}

async function store(cache, url) {
  const response = await fetch(url, { cache: 'no-cache' });
  if (response.ok) await cache.put(url, response);
}

async function warm(urls) {
  const cache = await caches.open(CACHE);
  for (const url of urls) {
    if (new URL(url).origin !== self.location.origin) continue;
    if (await cache.match(url)) continue;
    try {
      await store(cache, url);
    } catch (_) {
      // Offline already; the fetch handler fills the gap next time.
    }
  }
}
