<script lang="ts">
  import { page } from '$app/state';
  import Badge from '$lib/components/ui/Badge.svelte';
  import { currentUser } from '$lib/stores/auth.js';
  import { unreadCount } from '$lib/stores/notifications.js';
  import type { Identity } from '$lib/api/types.js';

  let user: Identity | null = $state(null);
  let notifCount = $state(0);

  currentUser.subscribe((v) => (user = v));
  unreadCount.subscribe((v) => (notifCount = v));

  interface TabItem {
    href: string;
    label: string;
    icon: string;
    badge?: () => number;
    isCompose?: boolean;
  }

  let tabs: TabItem[] = $derived([
    { href: '/home', label: 'Home', icon: 'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-4 0h4' },
    { href: '/explore', label: 'Explore', icon: 'M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z' },
    { href: '/compose', label: 'Compose', icon: 'M12 4v16m8-8H4', isCompose: true },
    { href: '/notifications', label: 'Notifications', icon: 'M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9', badge: () => notifCount },
    { href: user ? `/@${user.handle}` : '/profile', label: 'Profile', icon: 'M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z' },
  ]);

  function isActive(href: string): boolean {
    return page.url.pathname === href;
  }
</script>

<nav class="bottom-tabs" aria-label="Mobile navigation">
  {#each tabs as tab (tab.href)}
    <a
      href={tab.href}
      class="tab-item"
      class:active={isActive(tab.href)}
      class:compose={tab.isCompose}
      aria-label={tab.label}
      aria-current={isActive(tab.href) ? 'page' : undefined}
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
</style>
