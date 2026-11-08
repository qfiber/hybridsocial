import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';

// The web app manifest, built per instance. A static file named every
// deployment "HybridSocial" with the default "H" icon, so installing an
// instance as an app ignored its own name and logo — even though a plain
// browser shortcut (which reads <title> and the favicon) got them right.
// Name, description, theme colour and icon now come from the instance's
// public info and admin theme, falling back to the defaults below.

const DEFAULT_NAME = 'HybridSocial';
const DEFAULT_DESCRIPTION = 'Decentralized social networking platform';
const DEFAULT_THEME_COLOR = '#6c3edd';

const DEFAULT_ICONS: ManifestIcon[] = [
  { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
  { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
  { src: '/icons/icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
  { src: '/icons/icon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any' },
];

// Browsers want a launcher icon of at least this size; a smaller custom icon
// would install blurry, so the defaults are kept instead.
const MIN_ICON_PX = 192;
const ICON_PROBE_TIMEOUT_MS = 3000;
const CACHE_TTL_MS = 5 * 60 * 1000;

interface ManifestIcon {
  src: string;
  sizes: string;
  type: string;
  purpose: string;
}

// The probe fetches the icon, so remember the answer per URL for a while.
const iconCache = new Map<string, { icon: ManifestIcon | null; at: number }>();

// Read a PNG's dimensions from its IHDR chunk (bytes 16–24), so the manifest
// declares the icon's real size — browsers skip an icon whose declared size
// doesn't match, and then the instance can't be installed with it.
function pngSize(bytes: Uint8Array): { width: number; height: number } | null {
  const sig = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length < 24 || !sig.every((b, i) => bytes[i] === b)) return null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return { width: view.getUint32(16), height: view.getUint32(20) };
}

async function probeIcon(fetchFn: typeof fetch, url: string): Promise<ManifestIcon | null> {
  const cached = iconCache.get(url);
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) return cached.icon;

  let icon: ManifestIcon | null = null;
  try {
    const res = await fetchFn(url, { signal: AbortSignal.timeout(ICON_PROBE_TIMEOUT_MS) });
    if (res.ok) {
      const type = (res.headers.get('content-type') ?? '').split(';')[0].trim().toLowerCase();
      const bytes = new Uint8Array(await res.arrayBuffer());
      const isSvg = type === 'image/svg+xml' || /\.svg(\?|$)/i.test(url);
      if (isSvg) {
        icon = { src: url, sizes: 'any', type: 'image/svg+xml', purpose: 'any' };
      } else {
        const size = pngSize(bytes);
        if (size && size.width === size.height && size.width >= MIN_ICON_PX) {
          icon = {
            src: url,
            sizes: `${size.width}x${size.height}`,
            type: 'image/png',
            purpose: 'any',
          };
        }
      }
    }
  } catch {
    // Unreachable or slow: fall back to the default icons.
  }

  iconCache.set(url, { icon, at: Date.now() });
  return icon;
}

export const GET: RequestHandler = async ({ fetch }) => {
  const base = env.INTERNAL_API_URL || 'http://backend:4000';

  let name = DEFAULT_NAME;
  let description = DEFAULT_DESCRIPTION;
  let themeColor = DEFAULT_THEME_COLOR;
  let icons = DEFAULT_ICONS;

  try {
    // Same internal call as +layout.server.ts (see there for why the
    // forwarded-proto header is needed).
    const res = await fetch(`${base}/api/v1/instance`, {
      headers: { 'x-forwarded-proto': 'https' },
    });
    if (res.ok) {
      const info = (await res.json()) as Record<string, unknown>;
      const theme = (info.theme as Record<string, unknown> | null) ?? null;

      const title = typeof info.title === 'string' ? info.title.trim() : '';
      if (title) name = title;

      const desc = (info.short_description as string) || (info.description as string) || '';
      if (desc.trim()) description = desc.trim();

      const primary = theme?.color_primary;
      if (typeof primary === 'string' && /^#[0-9a-f]{3,8}$/i.test(primary)) themeColor = primary;

      const faviconUrl = (info.favicon_url as string) || (theme?.favicon_url as string) || '';
      if (faviconUrl) {
        const custom = await probeIcon(fetch, faviconUrl);
        // The instance's own icon replaces the defaults entirely: Android
        // prefers a `maskable` icon when one is listed, so leaving the default
        // maskable "H" in would put it on the launcher instead of the logo.
        if (custom) icons = [custom];
      }
    }
  } catch {
    // Backend unreachable: serve the defaults so the app stays installable.
  }

  const manifest = {
    id: '/',
    // Instance names are often Arabic (or mixed): let the browser pick the
    // direction from the text instead of assuming LTR.
    dir: 'auto',
    name,
    short_name: name,
    description,
    start_url: '/',
    scope: '/',
    display: 'standalone',
    background_color: '#ffffff',
    theme_color: themeColor,
    icons,
    categories: ['social'],
    shortcuts: [
      { name: 'Home', url: '/home' },
      { name: 'Notifications', url: '/notifications' },
      { name: 'Messages', url: '/messages' },
    ],
  };

  return new Response(JSON.stringify(manifest), {
    headers: {
      'content-type': 'application/manifest+json; charset=utf-8',
      // Short: an admin's rename or new logo should reach new installs soon.
      'cache-control': 'public, max-age=300',
    },
  });
};
