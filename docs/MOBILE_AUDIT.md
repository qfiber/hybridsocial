# Responsive & Mobile Audit

Date: 2026-07-11 (reconciled against `main` 2026-07-17)
Scope: `frontend/` (SvelteKit + Svelte 5)

> **Note:** findings #1, #13, and the `theme-color` half of #10 already landed in
> `main` via #65 and are marked **RESOLVED** below (no action needed on those).

Goal: make the platform behave correctly and feel native across **all devices and
screen sizes** — phones, tablets, and desktops — not phone-only. Every fix below
is expressed with responsive primitives (logical CSS properties, `dvh`,
`env(safe-area-*)`, breakpoints) so it improves the experience everywhere and
lays the groundwork for a future native app.

The responsive foundation is already mature: global `overflow-x: clip` +
`max-width: 100vw`, `img,video { max-width: 100% }`, `pre`/`table` wrapped in
`overflow-x: auto`, a clean fixed bottom nav, and a touch-correct reaction tray.
The issues below are concentrated and mostly small.

---

## Findings (ranked by severity × confidence)

| # | Issue | Location | Severity | Confidence | Fix |
|---|-------|----------|----------|------------|-----|
| 1 | ~~`viewport-fit=cover` missing~~ **RESOLVED (already in main via #65):** `viewport-fit=cover` is present in `src/app.html:5`, so `env(safe-area-inset-*)` resolves correctly | `src/app.html:5` | n/a | n/a | No action |
| 2 | Feed avatar hard-pinned to physical `left` on narrow screens, breaking the core RTL (Arabic) layout | `src/lib/components/post/PostCard.svelte:1386` | High | High | `inset-inline-start: 0` + `padding-inline-start` |
| 3 | Inputs `< 16px` trigger iOS auto-zoom on focus (search + DM compose) | `src/lib/components/layout/Header.svelte:319`, `src/lib/components/dm/MessageInput.svelte:359` | High | High | `font-size: 16px` on these inputs at `<= 768px` |
| 4 | `ProfileHoverCard` opens on hover/focus only; its Follow/Mute/Block actions are unreachable by touch | `src/lib/components/ui/ProfileHoverCard.svelte:136` | High | High | Open on tap when `matchMedia('(hover: none)')` |
| 5 | Arabic font stack broken: `Manrope` has no Arabic glyphs; `Rubik` is named but never loaded → falls back to bare `sans-serif` | `src/app.css:196` | High-med | High | Load a real Arabic webfont (Cairo / Tajawal / Noto Sans Arabic) |
| 6 | Service worker does nothing offline — empty precache, no `fetch` handler, no offline fallback | `static/sw.js` | High | High | App-shell precache + offline page + network-first navigations |
| 7 | Manifest fails Android installability — only an SVG icon, no 192/512 PNG, no maskable, empty `screenshots` | `static/manifest.json`, `static/icons/` | High | High | Generate PNG icons (192, 512, maskable) + screenshots |
| 8 | Primary feed action buttons (~28px) are under the 44px touch-target guidance | `src/lib/components/post/PostActions.svelte:1640` | Med-high | High | `min-height/min-width: 44px` hit-area |
| 9 | No body-scroll-lock behind modals / sheets — the page scrolls underneath on touch | `src/lib/components/ui/Modal.svelte`, `src/lib/components/layout/BottomTabs.svelte:146` | Med | High | Shared `overflow: hidden` + `overscroll-behavior: contain` while open |
| 10 | iOS `apple-touch-icon` is an SVG (renders blank on iOS); needs a 180px PNG. (The dark-mode `theme_color` sync is **already RESOLVED in main via #65**: `src/app.html:11-24` seeds/syncs `theme-color` to the resolved mode.) | `src/app.html:44`, `static/manifest.json` | Med | High | Add a 180px PNG apple-touch-icon |
| 11 | Fullscreen/modal heights use `vh` not `dvh`, overshooting the visible viewport when browser chrome shows | `src/lib/components/ui/Modal.svelte:124`, `ImageLightbox.svelte:508`, `StoryViewer.svelte:409` | Med | Med | Use `dvh` with a `vh` fallback |
| 12 | Back / chevron icons don't mirror in RTL | `src/routes/(app)/post/[id]/+page.svelte:128` and others | Med | High | `[dir="rtl"] .back-icon { transform: scaleX(-1) }` |
| 13 | ~~`<html lang>` never updates~~ **RESOLVED (already in main via #65):** `src/routes/+layout.svelte:65` sets `document.documentElement.lang = $locale` alongside `dir` | `src/routes/+layout.svelte:65` | n/a | n/a | No action |
| 14 | Push permission requested automatically right after login (no user gesture) → often auto-denied | `src/routes/(auth)/login/+page.svelte:71` | Med | Med | Gate behind an explicit "Enable notifications" action |
| 15 | Fonts are render-blocking Google Fonts (blocks first paint on slow networks; privacy) | `src/app.html` (fonts link) | Med | High | Self-host + `preload` a woff2 subset, `font-display: swap` |

Lower-priority leftovers: DM reaction overlay uses physical left/right
(`MessageBubble.svelte:1023`), no responsive `srcset`/`sizes` on feed images,
missing `enterkeyhint`/`inputmode` on inputs, a few admin `text-align: left`.

---

## Suggested new features (responsive, all-device)

These are designed to adapt across phone / tablet / desktop, not to be mobile-only:

- **Pull-to-refresh** on feeds (`/home`, `/explore`, `/notifications`) using
  `overscroll-behavior-y: contain`; degrades to the existing header refresh on
  pointer devices.
- **Swipe actions** on feed items (react / reply / bookmark / boost) reusing the
  existing handlers; pointer devices keep the button row.
- **Long-press / right-click context menu** on posts mirroring the proven
  reaction long-press, giving large-target Report/Mute/Share everywhere.
- **Offline feed read** — cache the last-viewed timeline (stale-while-revalidate)
  so a re-open works offline, with an offline banner.
- **App badge count** via the Badging API, driven by the existing unread count.
- **Auto per-post direction** — extend the existing `detectDirection()` /
  `dir="auto"` to feed post bodies so mixed Arabic/English timelines align each
  post correctly regardless of UI locale.
- **Rich PWA install prompt** (`beforeinstallprompt`) surfaced as an in-app CTA.

---

## PR batching plan

- **PR-A — iOS safe-area + theme sync** (#1, #10 theme-color, #13): **already landed
  in main via #65**; these findings are resolved, no further work.
- **PR-B — input zoom + tap targets** (#3, #8): CSS only.
- **PR-C — RTL fixes** (#2, #12, physical leftovers).
- **PR-D — touch reachability** (#4, #9).
- **PR-E — Arabic font** (#5, + self-host fonts #15).
- **PR-F — PWA offline + install** (#6, #7, #10 apple-touch-icon PNG): the largest;
  needs asset generation.
