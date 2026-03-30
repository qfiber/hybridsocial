<script lang="ts">
  import { page } from '$app/state';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Badge from '$lib/components/ui/Badge.svelte';
  import { currentUser } from '$lib/stores/auth.js';
  import { unreadCount } from '$lib/stores/notifications.js';
  import type { Identity } from '$lib/api/types.js';

  let user: Identity | null = $state(null);
  let notifCount = $state(0);

  currentUser.subscribe((v) => (user = v));
  unreadCount.subscribe((v) => (notifCount = v));

  interface NavItem {
    href: string;
    label: string;
    icon: string;
    badge?: () => number;
  }

  const navItems: NavItem[] = [
    { href: '/home', label: 'Home', icon: 'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-4 0h4' },
    { href: '/explore', label: 'Explore', icon: 'M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z' },
    { href: '/notifications', label: 'Notifications', icon: 'M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9', badge: () => notifCount },
    { href: '/messages', label: 'Messages', icon: 'M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z' },
    { href: '/lists', label: 'Lists', icon: 'M4 6h16M4 10h16M4 14h16M4 18h16' },
    { href: '/groups', label: 'Groups', icon: 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z' },
    { href: '/pages', label: 'Pages', icon: 'M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z M9 22V12h6v10' },
    { href: '/streams', label: 'Streams', icon: 'M5 3l14 9-14 9V3z' },
    { href: '/bookmarks', label: 'Bookmarks', icon: 'M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z' },
    { href: '/favourites', label: 'Favourites', icon: 'M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z' },
    { href: '/scheduled', label: 'Scheduled', icon: 'M12 2a10 10 0 100 20 10 10 0 000-20z M12 6v6l4 2' },
    { href: '/settings', label: 'Settings', icon: 'M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z M15 12a3 3 0 11-6 0 3 3 0 016 0z' },
    { href: '/developers', label: 'Developers', icon: 'M16 18l6-6-6-6M8 6l-6 6 6 6' },
  ];

  function isActive(href: string): boolean {
    return page.url.pathname === href || page.url.pathname.startsWith(href + '/');
  }
</script>

<aside class="sidebar">
  <nav class="sidebar-nav" aria-label="Main navigation">
    <ul class="nav-list">
      {#each navItems as item (item.href)}
        <li>
          <a
            href={item.href}
            class="nav-item"
            class:active={isActive(item.href)}
            aria-current={isActive(item.href) ? 'page' : undefined}
          >
            <svg class="nav-icon" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d={item.icon} />
            </svg>
            <span class="nav-label">{item.label}</span>
            {#if item.badge}
              {@const badgeCount = item.badge()}
              {#if badgeCount > 0}
                <Badge count={badgeCount} variant="danger" />
              {/if}
            {/if}
          </a>
        </li>
      {/each}
    </ul>
  </nav>

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
    overflow-y: auto;
  }

  .sidebar-nav {
    flex: 1;
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

  .nav-item.active {
    background: var(--color-secondary-container);
    color: var(--color-primary);
    font-weight: 600;
  }

  .nav-icon {
    flex-shrink: 0;
  }

  .sidebar-user {
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
  }

  /* Mobile: hidden */
  @media (max-width: 768px) {
    .sidebar {
      display: none;
    }
  }
</style>
