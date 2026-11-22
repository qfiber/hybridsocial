// Bump when OFFLINE_ASSETS change, so `activate` drops the old cache.
const CACHE_NAME = 'hybridsocial-v3';

// What the offline fallback needs to render with no network. Deliberately
// tiny: navigations are network-first and nothing personal is cached — a
// signed-in page's HTML carries the viewer's data and must never be served
// from cache to whoever opens the app next.
const OFFLINE_URL = '/offline.html';
const OFFLINE_ASSETS = [OFFLINE_URL, '/icons/icon-192.png'];

// The instance's own name and logo for the offline page, read from its
// per-instance /manifest.json while online. Public data only. Kept under
// private keys in the same cache and refreshed at most once a day.
const BRAND_KEY = '/__offline/brand';
const LOCALE_KEY = '/__offline/locale';
const LOGO_KEY = '/__offline/logo';
const BRAND_MAX_AGE_MS = 24 * 60 * 60 * 1000;

function pickIcon(icons) {
  if (!Array.isArray(icons)) return null;
  const size = (i) => parseInt(String(i.sizes || '0').split('x')[0], 10) || 0;
  // A plain ("any") icon: a maskable one is padded for launcher masks and
  // looks shrunken on its own. Closest to 192px, preferring larger.
  const plain = icons.filter((i) => i && i.src && !/maskable/.test(i.purpose || 'any'));
  const list = plain.length ? plain : icons.filter((i) => i && i.src);
  list.sort((a, b) => Math.abs(size(a) - 192) - Math.abs(size(b) - 192) || size(b) - size(a));
  return list[0] || null;
}

async function refreshBrand(force) {
  try {
    const cache = await caches.open(CACHE_NAME);
    if (!force) {
      const current = await cache.match(BRAND_KEY);
      if (current) {
        const saved = await current.json();
        if (Date.now() - (saved.saved_at || 0) < BRAND_MAX_AGE_MS) return;
      }
    }
    const res = await fetch('/manifest.json', { cache: 'no-cache' });
    if (!res.ok) return;
    const manifest = await res.json();
    const icon = pickIcon(manifest.icons);
    const iconUrl = icon ? new URL(icon.src, self.location.origin).href : '';
    let hasLogo = false;
    if (icon) {
      // Instance icons usually live on a separate media host without CORS:
      // an opaque response is still cacheable and renders in an <img>.
      const logo = await fetch(iconUrl, {
        mode: 'no-cors',
        cache: 'no-cache',
      });
      if (logo.ok || logo.type === 'opaque') {
        await cache.put(LOGO_KEY, logo);
        hasLogo = true;
      }
    }
    const brand = {
      name: typeof manifest.name === 'string' ? manifest.name : '',
      theme_color: typeof manifest.theme_color === 'string' ? manifest.theme_color : '',
      has_logo: hasLogo,
      // Absolute logo URL for notification icons (the browser fetches those
      // itself, outside this worker, so the cached copy can't be used).
      icon_url: iconUrl,
      saved_at: Date.now(),
    };
    await cache.put(
      BRAND_KEY,
      new Response(JSON.stringify(brand), { headers: { 'content-type': 'application/json' } })
    );
  } catch {
    // Offline or the manifest is unavailable: keep what we had.
  }
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[c]);
}

// The offline page with the instance's name, logo and brand colour filled in.
async function offlineResponse() {
  const cache = await caches.open(CACHE_NAME);
  const page = await cache.match(OFFLINE_URL);
  if (!page) return Response.error();
  let html = await page.text();
  let brand = null;
  try {
    const saved = await cache.match(BRAND_KEY);
    if (saved) brand = await saved.json();
  } catch {
    brand = null;
  }
  if (brand && brand.name) {
    html = html.split('__INSTANCE_NAME__').join(escapeHtml(brand.name));
  }
  if (brand && brand.has_logo) {
    html = html.replace('src="/icons/icon-192.png"', `src="${LOGO_KEY}"`);
  }
  if (brand && /^#[0-9a-f]{3,8}$/i.test(brand.theme_color)) {
    html = html.replace('</head>', `<style>:root{--brand:${brand.theme_color}}</style></head>`);
  }
  return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8' } });
}

async function readJson(key) {
  try {
    const cache = await caches.open(CACHE_NAME);
    const hit = await cache.match(key);
    return hit ? await hit.json() : null;
  } catch {
    return null;
  }
}

// The page tells the worker its interface language (routes/+layout.svelte).
self.addEventListener('message', (event) => {
  const msg = event.data;
  if (!msg || msg.type !== 'hs-locale' || typeof msg.locale !== 'string') return;
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) =>
      cache.put(
        LOCALE_KEY,
        new Response(JSON.stringify({ locale: msg.locale }), {
          headers: { 'content-type': 'application/json' },
        })
      )
    )
  );
});

// Notification wording per type, for languages other than the server's
// English. {name} is the actor. Types not listed keep the server's text.
const PUSH_TEXT = {
  ar: {
    follow: ['{name} بدأ متابعتك', 'لديك متابِع جديد'],
    follow_request: ['{name} طلب متابعتك', 'لديك طلب متابعة جديد'],
    reaction: ['{name} تفاعل مع منشورك', 'تفاعل أحدهم مع منشورك'],
    boost: ['{name} أعاد نشر منشورك', 'أُعيد نشر منشورك'],
    quote: ['{name} اقتبس منشورك', 'اقتُبس منشورك'],
    reply: ['{name} ردّ على منشورك', 'لديك ردّ جديد'],
    mention: ['{name} أشار إليك', 'أُشير إليك في منشور'],
    poll_ended: ['انتهى استطلاع', 'انتهى استطلاع شاركت فيه'],
    group_invite: ['{name} دعاك إلى مجموعة', 'دُعيت للانضمام إلى مجموعة'],
    group_application: ['طلب انضمام جديد إلى مجموعة', 'طلب أحدهم الانضمام إلى مجموعتك'],
    page_invite: ['{name} دعاك لإدارة صفحة', 'دُعيت لإدارة صفحة'],
    report: ['بلاغ جديد', 'قُدِّم بلاغ جديد'],
    moderation_takedown: ['أُزيل محتوى لك', 'أُزيل محتوى لك بقرار من الإشراف'],
  },
};
const PUSH_ACTIONS = {
  ar: { open: 'فتح', dismiss: 'تجاهل' },
  en: { open: 'Open', dismiss: 'Dismiss' },
};

function localizePush(data, lang) {
  const table = PUSH_TEXT[lang];
  const type = data.data && data.data.type;
  const row = table && type ? table[type] : null;
  if (!row) return { title: data.title, body: data.body };
  const name = (data.data && data.data.actor_name) || '';
  // A title that needs a name it doesn't have keeps the server's wording.
  if (row[0].includes('{name}') && !name) return { title: data.title, body: data.body };
  return { title: row[0].split('{name}').join(name), body: row[1] };
}

// Install - precache the offline fallback and the instance's branding
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(OFFLINE_ASSETS))
      .then(() => refreshBrand(true))
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
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  // The offline page's own images. They are subresource requests, not
  // navigations, so they used to go to the (absent) network and the page
  // showed a broken image. Network first so updates still land.
  if (
    url.origin === self.location.origin &&
    (url.pathname.startsWith('/__offline/') || OFFLINE_ASSETS.includes(url.pathname))
  ) {
    event.respondWith(
      (async () => {
        if (url.pathname.startsWith('/__offline/')) {
          const hit = await caches.match(url.pathname);
          return hit || Response.error();
        }
        try {
          return await fetch(request);
        } catch {
          const hit = await caches.match(url.pathname);
          return hit || Response.error();
        }
      })()
    );
    return;
  }

  if (request.mode !== 'navigate') return;

  event.respondWith(
    (async () => {
      try {
        const preloaded = await event.preloadResponse;
        const response = preloaded || (await fetch(request));
        // Online: keep the instance's name/logo current (at most daily).
        event.waitUntil(refreshBrand(false));
        return response;
      } catch {
        return offlineResponse();
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

  event.waitUntil(
    (async () => {
      const [brand, pref] = await Promise.all([readJson(BRAND_KEY), readJson(LOCALE_KEY)]);
      const lang = ((pref && pref.locale) || self.navigator.language || 'en').split('-')[0];
      const text = localizePush(data, lang);
      const actions = PUSH_ACTIONS[lang] || PUSH_ACTIONS.en;
      const rtl = lang === 'ar' || lang === 'he' || lang === 'fa';
      return self.registration.showNotification(text.title, {
        body: text.body,
        dir: rtl ? 'rtl' : 'auto',
        lang,
        // The instance's own logo when known. Android can't render SVG
        // notification icons; the badge must be a monochrome (white on
        // transparent) image.
        icon: (brand && brand.icon_url) || '/icons/icon-192.png',
        badge: '/icons/badge-96.png',
        tag: data.tag || 'default',
        data: data.data || {},
        vibrate: [200, 100, 200],
        actions: [
          { action: 'open', title: actions.open },
          { action: 'dismiss', title: actions.dismiss },
        ],
      });
    })()
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
