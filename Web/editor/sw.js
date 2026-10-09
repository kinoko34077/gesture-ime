// Only public, versioned static assets are cached; imported user JSON never hits fetch.
const CACHE = 'gesture-ime-preview-__BUILD_SHA__';
const ASSETS = ['./', './index.html', './app.js', './host-browser.js', './style.css',
  './manifest.webmanifest', './icon.svg', './default-ja.json',
  './wasm/gesture_ime_core_web.js', './wasm/gesture_ime_core_web_bg.wasm'];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(ASSETS)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(names => Promise.all(names
    .filter(name => name.startsWith('gesture-ime-preview-') && name !== CACHE)
    .map(name => caches.delete(name)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET' || new URL(event.request.url).origin !== self.location.origin) return;
  event.respondWith(fetch(event.request).then(response => {
    if (response.ok) {
      const copy = response.clone();
      caches.open(CACHE).then(cache => cache.put(event.request, copy)).catch(() => {});
    }
    return response;
  }).catch(() => caches.match(event.request)));
});
