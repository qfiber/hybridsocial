import { writable, get } from 'svelte/store';
import type { ThemeConfig } from '$lib/api/types.js';
import { browser } from '$app/environment';
import { preferencesStore } from './preferences.js';

export const themeStore = writable<ThemeConfig | null>(null);

export type ThemeMode = 'light' | 'dark' | 'auto';

// The mode actually in effect right now ('auto' resolved against the OS).
// Components subscribe to this to pick mode-specific assets (e.g. a dark
// vs light logo). Updated by applyTheme() and on OS preference changes.
export const resolvedMode = writable<'light' | 'dark'>('light');

// localStorage key the no-FOUC boot script in app.html also reads so the
// resolved mode is set on <html> before first paint on repeat visits.
export const MODE_STORAGE_KEY = 'hs-theme-mode';

// Maps admin theme keys → the CSS custom properties the app actually
// reads. A single key can write to several properties when the app
// uses multiple aliases (e.g. color_primary_contrast flows into both
// --color-on-primary and --color-text-on-primary).
const PROPERTY_MAP: Record<string, string[]> = {
  color_primary: ['--color-primary'],
  color_primary_hover: ['--color-primary-hover'],
  color_primary_soft: ['--color-primary-soft'],
  color_primary_contrast: ['--color-on-primary', '--color-text-on-primary'],
  color_secondary: ['--color-secondary'],
  color_accent: ['--color-accent'],
  color_success: ['--color-success'],
  color_warning: ['--color-warning'],
  color_danger: ['--color-danger', '--color-error'],
  color_info: ['--color-info'],
  color_bg: ['--color-bg', '--color-background'],
  color_bg_wash: ['--color-bg-wash'],
  color_surface: ['--color-surface'],
  color_border: ['--color-border'],
  color_text: ['--color-text'],
  color_text_secondary: ['--color-text-secondary'],
  color_text_link: ['--color-text-link'],
  gradient_start: ['--gradient-start'],
  gradient_end: ['--gradient-end'],
  gradient_direction: ['--gradient-direction'],
  font_family: ['--font-sans'],
};

// Admin-selectable fonts we self-host are registered under @fontsource's
// "<Name> Variable" family, so a stored plain name ("Inter") must map to it.
// Other choices are passed through and rely on the visitor having the font.
const SELF_HOSTED_FONTS: Record<string, string> = {
  Inter: "'Inter Variable', Inter, sans-serif",
};

export function resolveFontFamily(name: string): string {
  return SELF_HOSTED_FONTS[name.trim()] ?? name;
}

// Hybrid dark model: only the BRAND hues are derived from the light theme
// (set the brand once, both modes track it). Everything else in dark comes
// from the designed [data-theme="dark"] ramp in app.css, unless the admin
// supplies an explicit dark_<key> override (which always wins).
const BRAND_KEYS = new Set(['color_primary', 'color_secondary', 'color_accent']);

// How much to lift a brand colour's lightness for dark so it reads as an
// accent on the violet-ink surfaces (tuned to match the static dark ramp:
// #6c3edd → ~#8b6cf0).
const DARK_BRAND_LIFT = 0.13;

// border_radius (sharp/rounded/pill) and density (compact/comfortable/
// spacious) are discrete choices, not colors — applied as data
// attributes so the app's CSS can key off them if it wants.
const ATTR_KEYS: Array<keyof ThemeConfig> = ['border_radius', 'density'];

// Parse a #rgb / #rrggbb string into {r,g,b} 0-255. Returns null for
// anything that isn't a valid hex colour.
function parseHex(hex: string): { r: number; g: number; b: number } | null {
  const m = /^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.exec(hex.trim());
  if (!m) return null;
  let h = m[1];
  if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
  return {
    r: parseInt(h.slice(0, 2), 16),
    g: parseInt(h.slice(2, 4), 16),
    b: parseInt(h.slice(4, 6), 16),
  };
}

// "r, g, b" channels for use inside rgba(var(--color-primary-rgb), <a>).
function hexToRgbChannels(hex: string): string | null {
  const rgb = parseHex(hex);
  return rgb ? `${rgb.r}, ${rgb.g}, ${rgb.b}` : null;
}

function rgbToHsl(r: number, g: number, b: number): [number, number, number] {
  r /= 255;
  g /= 255;
  b /= 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  let h = 0;
  let s = 0;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h /= 6;
  }
  return [h, s, l];
}

function hslToHex(h: number, s: number, l: number): string {
  const hue2rgb = (p: number, q: number, t: number) => {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  let r: number;
  let g: number;
  let b: number;
  if (s === 0) {
    r = g = b = l;
  } else {
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const p = 2 * l - q;
    r = hue2rgb(p, q, h + 1 / 3);
    g = hue2rgb(p, q, h);
    b = hue2rgb(p, q, h - 1 / 3);
  }
  const to = (x: number) =>
    Math.round(x * 255)
      .toString(16)
      .padStart(2, '0');
  return `#${to(r)}${to(g)}${to(b)}`;
}

// Derive a brand colour's dark-mode variant by lifting its lightness (and
// nudging saturation up a touch so it stays vivid on dark). Falls back to
// the input if it isn't a hex colour.
export function liftForDark(hex: string, deltaL = DARK_BRAND_LIFT): string {
  const rgb = parseHex(hex);
  if (!rgb) return hex;
  const [h, s, l] = rgbToHsl(rgb.r, rgb.g, rgb.b);
  const nl = Math.min(0.82, Math.max(0, l + deltaL));
  const ns = Math.min(1, s + 0.05);
  return hslToHex(h, ns, nl);
}

function str(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

let currentConfig: ThemeConfig | null = null;
let mql: MediaQueryList | null = null;

function resolveMode(mode: ThemeMode): 'light' | 'dark' {
  if (mode === 'auto') {
    return browser && window.matchMedia('(prefers-color-scheme: dark)').matches
      ? 'dark'
      : 'light';
  }
  return mode;
}

// The user's explicit theme choice ('auto' | 'light' | 'dark'), or null when
// they haven't picked one — in which case we follow the instance default.
function userThemeMode(): ThemeMode | null {
  const m = get(preferencesStore).theme_mode;
  return m === 'auto' || m === 'light' || m === 'dark' ? m : null;
}

// Precedence: the user's explicit choice wins over the admin-configured
// instance default, which in turn falls back to 'auto' (follow the OS).
function effectiveMode(cfg: Record<string, unknown>): ThemeMode {
  const adminDefault = (str(cfg.mode) as ThemeMode) || 'auto';
  return userThemeMode() ?? adminDefault;
}

export function applyTheme(config: ThemeConfig | null): void {
  themeStore.set(config);
  currentConfig = config;
  if (!browser) return;

  const cfg = (config ?? {}) as Record<string, unknown>;

  // Keep dark/light in sync with the OS while the effective mode is 'auto'.
  if (!mql) mql = window.matchMedia('(prefers-color-scheme: dark)');
  mql.onchange = () => {
    const c = (currentConfig ?? {}) as Record<string, unknown>;
    if (effectiveMode(c) === 'auto') render(c, 'auto');
  };

  render(cfg, effectiveMode(cfg));
}

// Re-apply the theme whenever the user's theme_mode preference changes — when
// they pick a mode in settings, or when it's hydrated from the server on
// login (cross-device). The colours still come from the admin config; only
// the light/dark selection follows the user.
if (browser) {
  // Seed with the current value so the subscription's immediate fire is a
  // no-op — applyTheme() handles the initial render. Only a genuine *change*
  // (user picks a mode, or the server hydrates one on login) re-applies,
  // which avoids a flash racing against the first applyTheme call.
  let lastThemeMode = get(preferencesStore).theme_mode;
  preferencesStore.subscribe((p) => {
    if (p.theme_mode !== lastThemeMode) {
      lastThemeMode = p.theme_mode;
      const c = (currentConfig ?? {}) as Record<string, unknown>;
      render(c, effectiveMode(c));
    }
  });
}

function render(cfg: Record<string, unknown>, mode: ThemeMode): void {
  const root = document.documentElement;
  const resolved = resolveMode(mode);
  root.setAttribute('data-theme', resolved);
  resolvedMode.set(resolved);
  try {
    localStorage.setItem(MODE_STORAGE_KEY, mode);
  } catch {
    // storage may be unavailable (private mode) — boot script just falls
    // back to 'auto', which is the default anyway.
  }

  const dark = resolved === 'dark';

  for (const [key, cssVars] of Object.entries(PROPERTY_MAP)) {
    const darkOverride = str(cfg[`dark_${key}`]);
    const lightVal = str(cfg[key]);
    let value = '';

    if (dark) {
      if (darkOverride) value = darkOverride;
      else if (BRAND_KEYS.has(key) && lightVal) value = liftForDark(lightVal);
      // else: leave unset so the designed dark ramp in app.css applies.
    } else if (lightVal) {
      value = lightVal;
    }
    if (value && key === 'font_family') value = resolveFontFamily(value);

    for (const v of cssVars) {
      if (value) root.style.setProperty(v, value);
      else root.style.removeProperty(v);
    }
  }

  // --color-primary-rgb tracks whichever primary is active in this mode.
  const activePrimary = dark
    ? str(cfg.dark_color_primary) ||
      (str(cfg.color_primary) ? liftForDark(str(cfg.color_primary)) : '')
    : str(cfg.color_primary);
  const channels = activePrimary ? hexToRgbChannels(activePrimary) : null;
  if (channels) root.style.setProperty('--color-primary-rgb', channels);
  else root.style.removeProperty('--color-primary-rgb');

  // Mobile browser chrome / URL bar. Follow the *configured* palette instead
  // of a baked-in brand colour: dark mode matches the page background, light
  // mode the brand primary — both read live from the just-applied CSS vars so
  // an admin's custom palette flows through. Cache it per mode so the no-FOUC
  // boot script in app.html can seed the same value before first paint.
  const barColor = getComputedStyle(root)
    .getPropertyValue(dark ? '--color-bg' : '--color-primary')
    .trim();
  if (barColor) {
    let meta = document.querySelector('meta[name="theme-color"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.setAttribute('name', 'theme-color');
      document.head.appendChild(meta);
    }
    meta.setAttribute('content', barColor);
    try {
      localStorage.setItem(dark ? 'hs-theme-color-dark' : 'hs-theme-color-light', barColor);
    } catch {
      // storage unavailable — boot just skips seeding, theme.ts re-applies here.
    }
  }

  for (const key of ATTR_KEYS) {
    const value = str(cfg[key as string]);
    if (value) root.setAttribute(`data-${(key as string).replace('_', '-')}`, value);
    else root.removeAttribute(`data-${(key as string).replace('_', '-')}`);
  }
}

export function clearTheme(): void {
  themeStore.set(null);
  currentConfig = null;
  if (!browser) return;

  const root = document.documentElement;
  for (const cssVars of Object.values(PROPERTY_MAP)) {
    for (const v of cssVars) root.style.removeProperty(v);
  }
  root.style.removeProperty('--color-primary-rgb');
  for (const key of ATTR_KEYS) {
    root.removeAttribute(`data-${(key as string).replace('_', '-')}`);
  }
  // Fall back to OS preference rather than forcing light.
  root.setAttribute('data-theme', resolveMode('auto'));
}
