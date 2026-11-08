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

interface ManifestIcon {
  src: string;
  sizes: string;
  type: string;
  purpose: string;
}

interface AppIcons {
  icon_192?: string;
  icon_512?: string;
  maskable_512?: string;
}

// The backend derives these PNGs from the favicon when it's uploaded
// (Media.AppIcons), already at the exact sizes declared here, and only when
// the source is big enough, so nothing is fetched or measured per request.
// All three or none: a partial set falls back to the defaults.
function instanceIcons(appIcons: AppIcons | null | undefined): ManifestIcon[] | null {
  const { icon_192, icon_512, maskable_512 } = appIcons ?? {};
  if (!icon_192 || !icon_512 || !maskable_512) return null;
  return [
    { src: icon_192, sizes: '192x192', type: 'image/png', purpose: 'any' },
    { src: icon_512, sizes: '512x512', type: 'image/png', purpose: 'any' },
    { src: maskable_512, sizes: '512x512', type: 'image/png', purpose: 'maskable' },
  ];
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

      // The instance's icons replace the defaults entirely: Android prefers a
      // `maskable` icon when one is listed, so leaving the default maskable
      // "H" in would put it on the launcher instead of the logo.
      icons = instanceIcons(info.app_icons as AppIcons | null) ?? icons;
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
