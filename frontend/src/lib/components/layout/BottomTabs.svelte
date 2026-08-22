<script lang="ts">
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import Badge from '$lib/components/ui/Badge.svelte';
  import { currentUser, clearAuth } from '$lib/stores/auth.js';
  import { unreadCount } from '$lib/stores/notifications.js';
  import { dmUnreadTotal } from '$lib/stores/dm-unread.js';
  import { api } from '$lib/api/client.js';
  import { t } from '$lib/stores/i18n.js';
  import type { Identity } from '$lib/api/types.js';

  let user: Identity | null = $state(null);
  let notifCount = $state(0);
  let dmCount = $state(0);

  currentUser.subscribe((v) => (user = v));
  unreadCount.subscribe((v) => (notifCount = v));
  dmUnreadTotal.subscribe((v) => (dmCount = v));

  interface TabItem {
    href: string;
    labelKey: string;
    icon: string;
    badge?: () => number;
    isCompose?: boolean;
    isMore?: boolean;
  }

  let tabs: TabItem[] = $derived([
    { href: '/home', labelKey: 'nav.home', icon: 'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-4 0h4' },
    { href: '/explore', labelKey: 'nav.explore', icon: 'M12 21a9.004 9.004 0 008.716-6.747M12 21a9.004 9.004 0 01-8.716-6.747M12 21c2.485 0 4.5-4.03 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.03-4.5-9S9.515 3 12 3m0 0a8.997 8.997 0 017.843 4.582M12 3a8.997 8.997 0 00-7.843 4.582m15.686 0A11.953 11.953 0 0112 10.5c-2.998 0-5.74-1.1-7.843-2.918m15.686 0A8.959 8.959 0 0121 12c0 .778-.099 1.533-.284 2.253m0 0A17.919 17.919 0 0112 16.5c-3.162 0-6.133-.815-8.716-2.247m0 0A9.015 9.015 0 013 12c0-1.605.42-3.113 1.157-4.418' },
    { href: '/compose', labelKey: 'nav.compose_aria', icon: 'M12 4v16m8-8H4', isCompose: true },
    // Streams takes the notifications slot: the header already carries a
    // notifications bell, so a second one here was pure duplication. The bell
    // (and its unread badge) still lives in the "More" sheet for reachability.
    { href: '/streams', labelKey: 'nav.streams', icon: 'M3 5h18v14H3z M3 9h18 M8 5v4 M13 5v4 M18 5v4 M10 13l4 2-4 2z' },
    // Profile moved into the "More" sheet so Compose sits dead-centre
    // with two tabs on each side (5 total — within the ≤5 nav guideline).
    { href: '#more', labelKey: 'nav.more', icon: 'M5 12h.01M12 12h.01M19 12h.01M6 12a1 1 0 11-2 0 1 1 0 012 0zm7 0a1 1 0 11-2 0 1 1 0 012 0zm7 0a1 1 0 11-2 0 1 1 0 012 0z', isMore: true, badge: () => dmCount },
  ]);

  // The "More" sheet lists every Sidebar destination that doesn't
  // have a dedicated bottom tab — keeps Messages/Lists/Settings
  // reachable on mobile. The Messages badge is mirrored on the
  // More tab itself so users see "you have DMs" without opening
  // the sheet.
  interface MoreItem {
    href: string;
    labelKey: string;
    icon: string;
    badge?: () => number;
  }

  let moreItems: MoreItem[] = $derived([
    { href: user ? `/@${(user as Identity).handle}` : '/profile', labelKey: 'nav.profile', icon: 'M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z' },
    { href: '/messages', labelKey: 'nav.messages', icon: 'M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z', badge: () => dmCount },
    { href: '/lists', labelKey: 'nav.lists', icon: 'M4 6h16M4 10h16M4 14h16M4 18h16' },
    { href: '/groups', labelKey: 'nav.groups', icon: 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z' },
    { href: '/pages', labelKey: 'nav.pages', icon: 'M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z M9 22V12h6v10' },
    { href: '/notifications', labelKey: 'nav.notifications', icon: 'M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9', badge: () => notifCount },
    { href: '/bookmarks', labelKey: 'nav.bookmarks', icon: 'M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z' },
    { href: '/scheduled', labelKey: 'nav.scheduled', icon: 'M12 2a10 10 0 100 20 10 10 0 000-20z M12 6v6l4 2' },
    { href: '/drafts', labelKey: 'nav.drafts', icon: 'M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z' },
    { href: '/settings', labelKey: 'nav.settings', icon: 'M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z M15 12a3 3 0 11-6 0 3 3 0 016 0z' },
  ]);

  let showMoreSheet = $state(false);

  function isActive(href: string): boolean {
    return page.url.pathname === href || page.url.pathname.startsWith(href + '/');
  }

  function handleTabClick(e: MouseEvent, tab: TabItem) {
    // The compose tab isn't a real route — there's no /compose page.
    // The composer is a modal that lives on every (app) route and
    // listens for an `open-composer` window event. Fire that instead
    // of letting the browser navigate to a 404.
    if (tab.isCompose) {
      e.preventDefault();
      window.dispatchEvent(new CustomEvent('open-composer', { detail: {} }));
      return;
    }
    if (tab.isMore) {
      e.preventDefault();
      showMoreSheet = !showMoreSheet;
      return;
    }
  }

  function closeMoreSheet() {
    showMoreSheet = false;
  }

  function handleSheetKey(e: KeyboardEvent) {
    if (e.key === 'Escape') closeMoreSheet();
  }

  // The header avatar dropdown (the old logout home) is hidden on mobile,
  // so the More sheet carries logout now — separated from nav links.
  async function handleLogout() {
    closeMoreSheet();
    try {
      await api.post('/api/v1/auth/logout');
    } catch {
      // Log out locally even if the API call fails.
    }
    clearAuth();
    goto('/login');
  }
</script>

<svelte:window onkeydown={handleSheetKey} />

<nav class="bottom-tabs" aria-label={$t('nav.mobile_label')}>
  {#each tabs as tab (tab.href)}
    <a
      href={tab.href}
      class="tab-item"
      class:active={isActive(tab.href)}
      class:compose={tab.isCompose}
      aria-label={$t(tab.labelKey)}
      aria-current={isActive(tab.href) ? 'page' : undefined}
      onclick={(e) => handleTabClick(e, tab)}
    >
      {#if tab.isCompose}
        <span class="compose-btn">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d={tab.icon} />
          </svg>
        </span>
      {:else}
        <span class="tab-icon-wrapper">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d={tab.icon} />
          </svg>
          {#if tab.badge}
            {@const count = tab.badge()}
            {#if count > 0}
              <span class="tab-badge">
                <Badge count={count} variant="danger" />
              </span>
            {/if}
          {/if}
        </span>
      {/if}
    </a>
  {/each}
</nav>

{#if showMoreSheet}
  <div
    class="more-sheet-backdrop"
    onclick={closeMoreSheet}
    role="presentation"
  ></div>
  <div
    class="more-sheet"
    role="dialog"
    aria-modal="true"
    aria-label={$t('nav.more_label')}
  >
    <div class="more-sheet-handle" aria-hidden="true"></div>
    <ul class="more-sheet-list">
      {#each moreItems as item (item.href)}
        <li>
          <a
            href={item.href}
            class="more-sheet-item"
            class:active={isActive(item.href)}
            onclick={closeMoreSheet}
          >
            <span class="more-sheet-icon-wrap">
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d={item.icon} />
              </svg>
              {#if item.badge}
                {@const count = item.badge()}
                {#if count > 0}
                  <span class="more-sheet-badge">
                    <Badge count={count} variant="danger" />
                  </span>
                {/if}
              {/if}
            </span>
            <span class="more-sheet-label">{$t(item.labelKey)}</span>
          </a>
        </li>
      {/each}
    </ul>

    <div class="more-sheet-sep" aria-hidden="true"></div>
    <button type="button" class="more-sheet-item more-sheet-logout" onclick={handleLogout}>
      <span class="more-sheet-icon-wrap">
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
          <polyline points="16 17 21 12 16 7" />
          <line x1="21" y1="12" x2="9" y2="12" />
        </svg>
      </span>
      <span class="more-sheet-label">{$t('auth.logout')}</span>
    </button>
  </div>
{/if}

<style>
  .bottom-tabs {
    display: none;
  }

  @media (max-width: 768px) {
    .bottom-tabs {
      position: fixed;
      bottom: 0;
      inset-inline: 0;
      height: var(--header-height);
      display: flex;
      align-items: center;
      justify-content: space-around;
      background: var(--color-surface-raised);
      border-block-start: 1px solid var(--color-border);
      z-index: var(--z-sticky);
      padding: 0 var(--space-2);
      /* Honour iOS home-indicator inset so the bar isn't hidden
         under the gesture area on notched devices. */
      padding-block-end: env(safe-area-inset-bottom, 0);
      box-sizing: content-box;
    }
  }

  .tab-item {
    display: flex;
    align-items: center;
    justify-content: center;
    flex: 1;
    height: 100%;
    color: var(--color-text-secondary);
    text-decoration: none;
    transition: color var(--transition-fast);
  }

  .tab-item:hover {
    text-decoration: none;
    color: var(--color-text);
  }

  .tab-item.active {
    color: var(--color-primary);
  }

  .tab-icon-wrapper {
    position: relative;
    display: flex;
  }

  .tab-badge {
    position: absolute;
    top: -4px;
    inset-inline-end: -8px;
  }

  .compose-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    background: var(--color-primary);
    color: var(--color-text-on-primary);
    border-radius: var(--radius-full);
  }

  /* ---- More sheet ----
     Slides up from the bottom on mobile. Sits above BottomTabs
     (z-sticky=20) but below modals (z-modal=40) — same rationale
     as the post 3-dot menu. */
  .more-sheet-backdrop {
    position: fixed;
    inset: 0;
    background: var(--scrim-medium);
    z-index: 28;
    animation: more-fade 0.15s ease;
  }

  .more-sheet {
    position: fixed;
    inset-inline: 0;
    bottom: 0;
    z-index: 29;
    background: var(--color-surface-raised);
    border-start-start-radius: 18px;
    border-start-end-radius: 18px;
    box-shadow: 0 -8px 24px rgba(0, 0, 0, 0.12);
    padding: var(--space-2) var(--space-2) calc(var(--header-height) + env(safe-area-inset-bottom, 0px) + var(--space-3));
    max-height: 70vh;
    overflow-y: auto;
    animation: more-slide-up 0.22s cubic-bezier(0.22, 1, 0.36, 1);
  }

  @keyframes more-fade {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes more-slide-up {
    from { transform: translateY(100%); }
    to { transform: translateY(0); }
  }

  .more-sheet-handle {
    width: 36px;
    height: 4px;
    background: var(--color-border);
    border-radius: 999px;
    margin: var(--space-2) auto var(--space-2);
  }

  .more-sheet-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .more-sheet-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border-radius: var(--radius-lg);
    color: var(--color-on-surface);
    text-decoration: none;
    font-size: var(--text-base);
    font-weight: 500;
  }

  .more-sheet-item:hover,
  .more-sheet-item:focus-visible {
    background: var(--color-surface-container-low);
    text-decoration: none;
    outline: none;
  }

  .more-sheet-item.active {
    background: var(--color-secondary-container, var(--color-surface-container-low));
    color: var(--color-primary);
    font-weight: 600;
  }

  .more-sheet-sep {
    height: 1px;
    background: var(--color-border);
    margin: var(--space-2);
  }

  /* Destructive action, visually separated from the nav links above. */
  .more-sheet-logout {
    width: 100%;
    background: none;
    border: none;
    cursor: pointer;
    text-align: start;
    color: var(--color-error);
    font-family: inherit;
  }

  .more-sheet-logout:hover,
  .more-sheet-logout:focus-visible {
    background: color-mix(in oklab, var(--color-error) 10%, transparent);
    outline: none;
  }

  .more-sheet-icon-wrap {
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .more-sheet-badge {
    position: absolute;
    top: -4px;
    inset-inline-end: -8px;
    transform: scale(0.85);
    transform-origin: top right;
    pointer-events: none;
  }

  /* Hide the sheet on desktop — the Sidebar already covers it. The
     sheet itself only opens via the More tab which is mobile-only,
     but extra belt-and-braces here keeps it from ever flashing if
     someone resizes a window with the sheet open. */
  @media (min-width: 769px) {
    .more-sheet,
    .more-sheet-backdrop {
      display: none;
    }
  }
</style>
