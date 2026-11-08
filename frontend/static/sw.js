// Bump when OFFLINE_ASSETS change, so `activate` drops the old cache.
const CACHE_NAME = 'hybridsocial-v2';

// What the offline fallback needs to render with no network. Deliberately
// tiny: navigations are network-first and nothing personal is cached — a
// signed-in page's HTML carries the viewer's data and must never be served
// from cache to whoever opens the app next.
const OFFLINE_URL = '/offline.html';
const OFFLINE_ASSETS = [OFFLINE_URL, '/icons/icon-192.png'];

// Install - precache the offline fallback
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(OFFLINE_ASSETS))
      .then(() => self.skipWaiting())
  );
});

// Activate - clean old caches, take control, and turn on navigation preload
// (so the SW's boot time isn't added to every page load)
self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      );
      if (self.registration.navigationPreload) {
        await self.registration.navigationPreload.enable();
      }
      await clients.claim();
    })()
  );
});

// Fetch - only top-level page loads are handled: try the network (or the
// preloaded response) and fall back to the offline page when it fails.
// Everything else — API calls, client-side route data, media, uploads,
// non-GET — goes straight to the network untouched.
self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.mode !== 'navigate' || request.method !== 'GET') return;

  event.respondWith(
    (async () => {
      try {
        const preloaded = await event.preloadResponse;
        if (preloaded) return preloaded;
        return await fetch(request);
      } catch {
        const cache = await caches.open(CACHE_NAME);
        const offline = await cache.match(OFFLINE_URL);
        return offline || Response.error();
      }
    })()
  );
});

// Push notification received
self.addEventListener('push', (event) => {
  let data = { title: 'HybridSocial', body: 'New notification' };

  try {
    data = event.data.json();
  } catch (e) {
    data.body = event.data ? event.data.text() : 'New notification';
  }

  const options = {
    body: data.body,
    // Android can't render SVG notification icons; the badge must be a
    // monochrome (white on transparent) image.
    icon: '/icons/icon-192.png',
    badge: '/icons/badge-96.png',
    tag: data.tag || 'default',
    data: data.data || {},
    vibrate: [200, 100, 200],
    actions: [
      { action: 'open', title: 'Open' },
      { action: 'dismiss', title: 'Dismiss' }
    ]
  };

  event.waitUntil(
    self.registration.showNotification(data.title, options)
  );
});

// Notification click
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const url = event.notification.data?.url || '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // Focus existing window if open
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.navigate(url);
          return client.focus();
        }
      }
      // Open new window
      return clients.openWindow(url);
    })
  );
});
