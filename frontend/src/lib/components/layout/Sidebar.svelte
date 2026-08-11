<script lang="ts">
  import { page } from '$app/state';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Badge from '$lib/components/ui/Badge.svelte';
  import { currentUser } from '$lib/stores/auth.js';
  import { unreadCount } from '$lib/stores/notifications.js';
  import { dmUnreadTotal } from '$lib/stores/dm-unread.js';
  import { t } from '$lib/stores/i18n.js';
  import type { Identity } from '$lib/api/types.js';

  // Auto-subscribed derivations — these unsubscribe automatically when
  // the component is destroyed, unlike a bare store.subscribe() which
  // would leak its listener.
  let user = $derived($currentUser);
  let notifCount = $derived($unreadCount);
  let dmCount = $derived($dmUnreadTotal);

  interface NavItem {
    href: string;
    labelKey: string;
    icon: string;
    badge?: () => number;
  }

  // Grouped so the 12 destinations read as clusters (primary / discover /
  // your content / utility) instead of one flat wall. Rendered with a
  // thin divider between groups. Labels are i18n keys resolved at render
  // time so they react to locale changes (see $t below).
  const navGroups: NavItem[][] = [
    [
      { href: '/home', labelKey: 'nav.home', icon: 'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-4 0h4' },
      { href: '/explore', labelKey: 'nav.explore', icon: 'M12 21a9.004 9.004 0 008.716-6.747M12 21a9.004 9.004 0 01-8.716-6.747M12 21c2.485 0 4.5-4.03 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.03-4.5-9S9.515 3 12 3m0 0a8.997 8.997 0 017.843 4.582M12 3a8.997 8.997 0 00-7.843 4.582m15.686 0A11.953 11.953 0 0112 10.5c-2.998 0-5.74-1.1-7.843-2.918m15.686 0A8.959 8.959 0 0121 12c0 .778-.099 1.533-.284 2.253m0 0A17.919 17.919 0 0112 16.5c-3.162 0-6.133-.815-8.716-2.247m0 0A9.015 9.015 0 013 12c0-1.605.42-3.113 1.157-4.418' },
      { href: '/notifications', labelKey: 'nav.notifications', icon: 'M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9', badge: () => notifCount },
      { href: '/messages', labelKey: 'nav.messages', icon: 'M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z', badge: () => dmCount },
    ],
    [
      { href: '/lists', labelKey: 'nav.lists', icon: 'M4 6h16M4 10h16M4 14h16M4 18h16' },
      { href: '/groups', labelKey: 'nav.groups', icon: 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z' },
      { href: '/pages', labelKey: 'nav.pages', icon: 'M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z M9 22V12h6v10' },
      { href: '/streams', labelKey: 'nav.streams', icon: 'M7 4h10a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z M10.5 9.5l4 2.5-4 2.5z' },
    ],
    [
      { href: '/bookmarks', labelKey: 'nav.bookmarks', icon: 'M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z' },
      { href: '/scheduled', labelKey: 'nav.scheduled', icon: 'M12 2a10 10 0 100 20 10 10 0 000-20z M12 6v6l4 2' },
      { href: '/drafts', labelKey: 'nav.drafts', icon: 'M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z' },
    ],
    [
      { href: '/settings', labelKey: 'nav.settings', icon: 'M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z M15 12a3 3 0 11-6 0 3 3 0 016 0z' },
    ],
  ];

  // Accessible name that folds in the unread count and survives the
  // icon-only tablet mode where the visible label is hidden. `translate`
  // is the reactive $t so this recomputes on locale change.
  function navAriaLabel(item: NavItem, translate: typeof $t): string {
    const label = translate(item.labelKey);
    const count = item.badge ? item.badge() : 0;
    return count > 0 ? translate('nav.unread', { label, count }) : label;
  }

  function isActive(href: string): boolean {
    return page.url.pathname === href || page.url.pathname.startsWith(href + '/');
  }

  // Routes where opening the global composer doesn't make sense
  // (DMs have their own composer, settings/admin are task-focused).
  // Mirrors the gate the FAB used to apply.
  const NO_COMPOSE_PREFIXES = ['/messages', '/admin', '/settings'];
  let showCompose = $derived(
    !NO_COMPOSE_PREFIXES.some((p) => page.url.pathname.startsWith(p)),
  );

  function openComposer() {
    window.dispatchEvent(new CustomEvent('open-composer', { detail: {} }));
  }
</script>

<aside class="sidebar">
  <nav class="sidebar-nav" aria-label={$t('nav.main_label')}>
    <ul class="nav-list">
      {#each navGroups as group, gi (gi)}
        {#if gi > 0}
          <li class="nav-divider" role="separator" aria-hidden="true"></li>
        {/if}
        {#each group as item (item.href)}
          {@const active = isActive(item.href)}
          <li>
            <a
              href={item.href}
              class="nav-item"
              class:active
              aria-current={active ? 'page' : undefined}
              aria-label={navAriaLabel(item, $t)}
              title={$t(item.labelKey)}
            >
              <span class="nav-icon-wrap">
                <svg class="nav-icon" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width={active ? 2.5 : 2} stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                  <path d={item.icon} />
                </svg>
                {#if item.badge}
                  {@const badgeCount = item.badge()}
                  {#if badgeCount > 0}
                    <span class="nav-badge-wrap">
                      <Badge count={badgeCount} variant="danger" />
                    </span>
                  {/if}
                {/if}
              </span>
              <span class="nav-label">{$t(item.labelKey)}</span>
            </a>
          </li>
        {/each}
      {/each}
    </ul>
  </nav>

  {#if showCompose}
    <!-- Composer trigger pinned below the scrollable nav list so it stays
         reachable on short viewports instead of scrolling off with the
         destinations. Same gating as the old FAB — hidden inside DMs /
         admin / settings where it'd just be in the way. -->
    <div class="sidebar-footer">
      <button
        type="button"
        class="nav-item nav-item-compose"
        onclick={openComposer}
        aria-label={$t('nav.compose_aria')}
      >
        <span class="nav-icon-wrap">
          <svg class="nav-icon" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5" />
            <path d="M18.586 3.586a2 2 0 112.828 2.828L12 16l-4 1 1-4 9.586-9.414z" />
          </svg>
        </span>
        <span class="nav-label">{$t('nav.compose')}</span>
      </button>
    </div>
  {/if}

  {#if user}
    <div class="sidebar-user">
      <a href="/@{user.handle}" class="user-link">
        <Avatar src={user.avatar_url} name={user.display_name || user.handle} size="sm" />
        <div class="user-info">
          <span class="user-name">{user.display_name || user.handle}</span>
          <span class="user-handle">@{user.handle}</span>
        </div>
      </a>
    </div>
  {/if}
</aside>

<style>
  .sidebar {
    position: sticky;
    top: calc(var(--header-height) + var(--space-8));
    height: calc(100vh - var(--header-height) - var(--space-8));
    display: flex;
    flex-direction: column;
    padding: var(--space-2) 0;
    /* The sidebar itself doesn't scroll — only the nav destinations do,
       so the compose button + user stay pinned at the bottom on short
       (low-res / zoomed) viewports. */
    overflow: hidden;
  }

  /* Destinations scroll when they can't all fit; min-height:0 lets the
     flex child actually shrink so the pinned footer/user always show. */
  .sidebar-nav {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
  }

  .sidebar-footer {
    flex-shrink: 0;
  }

  .nav-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .nav-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border-radius: var(--radius-full);
    color: var(--color-on-surface-variant);
    text-decoration: none;
    font-family: var(--font-body);
    font-size: var(--text-base);
    font-weight: 500;
    transition: background var(--transition-fast), color var(--transition-fast);
    white-space: nowrap;
  }

  .nav-item:hover {
    background: var(--color-surface-container-low);
    color: var(--color-on-surface);
    text-decoration: none;
  }

  .nav-item:focus-visible {
    background: var(--color-surface-container-low);
    color: var(--color-on-surface);
    outline: 2px solid var(--color-primary);
    outline-offset: -2px;
    text-decoration: none;
  }

  .nav-item.active {
    background: var(--color-secondary-container);
    color: var(--color-primary);
    font-weight: 600;
  }

  /* Thin rule between destination groups. Indented to the row's text
     inset so it doesn't run edge-to-edge. */
  .nav-divider {
    height: 1px;
    background: var(--color-border);
    margin: var(--space-2) var(--space-4);
    list-style: none;
  }

  /* Compose is rendered as a <button>; reset the user-agent styles
     so it lines up pixel-for-pixel with the <a> nav items above. */
  button.nav-item {
    width: 100%;
    background: var(--color-primary);
    color: var(--color-text-on-primary);
    border: none;
    cursor: pointer;
    margin-block-start: var(--space-2);
    font-weight: 600;
  }

  button.nav-item:hover {
    background: var(--color-primary-hover);
    color: var(--color-text-on-primary);
  }

  button.nav-item:focus-visible {
    background: var(--color-primary-hover);
    color: var(--color-text-on-primary);
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .nav-icon {
    flex-shrink: 0;
  }

  .nav-icon-wrap {
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  /* Always anchor the badge to the icon's top-right corner. In
     expanded mode this keeps it tied to the icon (consistent with
     the topbar bell); in compact/icon-only mode it prevents the
     pill from bulging out the sidebar row. The small translate
     overlaps the corner rather than sitting flush. */
  .nav-badge-wrap {
    position: absolute;
    top: -4px;
    inset-inline-end: -8px;
    /* Shrink the pill a touch so it reads as an icon annotation
       rather than a full-size chip. */
    transform: scale(0.85);
    transform-origin: top right;
    pointer-events: none;
  }

  .sidebar-user {
    flex-shrink: 0;
    padding-block-start: var(--space-4);
    margin-block-start: var(--space-4);
  }

  .user-link {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border-radius: var(--radius-full);
    text-decoration: none;
    color: var(--color-on-surface);
    transition: background var(--transition-fast);
  }

  .user-link:hover {
    background: var(--color-surface-container-low);
    text-decoration: none;
  }

  .user-link:focus-visible {
    background: var(--color-surface-container-low);
    outline: 2px solid var(--color-primary);
    outline-offset: -2px;
    text-decoration: none;
  }

  .user-info {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .user-name {
    font-family: var(--font-headline);
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-on-surface);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .user-handle {
    font-size: var(--text-xs);
    color: var(--color-on-surface-variant);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* Tablet: icon-only */
  @media (max-width: 1280px) {
    .sidebar {
      align-items: center;
      padding: var(--space-2) 0;
    }

    .nav-label,
    .user-info {
      display: none;
    }

    .nav-item {
      justify-content: center;
      padding: var(--space-3);
      border-radius: var(--radius-full);
    }

    .user-link {
      justify-content: center;
      padding: var(--space-3);
    }

    /* Tighten the group dividers so they don't run wider than the
       icon rail. */
    .nav-divider {
      margin-inline: var(--space-3);
    }
  }

  /* Mobile: hidden */
  @media (max-width: 768px) {
    .sidebar {
      display: none;
    }
  }
</style>
