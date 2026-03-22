<script lang="ts">
  import { page } from '$app/stores';

  let { children } = $props();

  let currentPath = $state('');
  const unsub = page.subscribe(($page) => {
    currentPath = $page.url.pathname;
  });

  const menuItems = [
    { href: '/settings', label: 'Profile', icon: 'M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2M12 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8z' },
    { href: '/settings/privacy', label: 'Privacy', icon: 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z' },
    { href: '/settings/notifications', label: 'Notifications', icon: 'M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9M13.73 21a2 2 0 0 1-3.46 0' },
    { href: '/settings/security', label: 'Security', icon: 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10zM9 12l2 2 4-4' },
    { href: '/settings/account', label: 'Account', icon: 'M12 15v2m-6 4h12a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2zm10-10V7a4 4 0 0 0-8 0v4' },
  ];

  function isActive(href: string): boolean {
    if (href === '/settings') return currentPath === '/settings';
    return currentPath.startsWith(href);
  }

  import { onMount } from 'svelte';
  onMount(() => () => unsub());
</script>

<svelte:head>
  <title>Settings - HybridSocial</title>
</svelte:head>

<div class="settings-layout">
  <nav class="settings-nav" aria-label="Settings navigation">
    <h2 class="settings-nav-title">Settings</h2>
    <ul class="settings-menu">
      {#each menuItems as item (item.href)}
        <li>
          <a
            href={item.href}
            class="settings-menu-item"
            class:active={isActive(item.href)}
            aria-current={isActive(item.href) ? 'page' : undefined}
          >
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d={item.icon} />
            </svg>
            {item.label}
          </a>
        </li>
      {/each}
    </ul>
  </nav>

  <main class="settings-content">
    {@render children()}
  </main>
</div>

<style>
  .settings-layout {
    max-width: 900px;
    margin: 0 auto;
    display: flex;
    gap: var(--space-6);
  }

  .settings-nav {
    width: 220px;
    flex-shrink: 0;
    position: sticky;
    top: calc(var(--header-height) + var(--space-4));
    align-self: flex-start;
  }

  .settings-nav-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
    padding: var(--space-2) var(--space-3);
    margin-block-end: var(--space-2);
  }

  .settings-menu {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .settings-menu-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text-secondary);
    text-decoration: none;
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .settings-menu-item:hover {
    background: var(--color-surface);
    color: var(--color-text);
    text-decoration: none;
  }

  .settings-menu-item.active {
    background: var(--color-primary-soft);
    color: var(--color-primary);
  }

  .settings-content {
    flex: 1;
    min-width: 0;
  }

  @media (max-width: 640px) {
    .settings-layout {
      flex-direction: column;
    }

    .settings-nav {
      width: 100%;
      position: static;
    }

    .settings-menu {
      flex-direction: row;
      overflow-x: auto;
      scrollbar-width: none;
      gap: var(--space-1);
      padding-block-end: var(--space-2);
      border-block-end: 1px solid var(--color-border);
    }

    .settings-menu::-webkit-scrollbar {
      display: none;
    }

    .settings-menu-item {
      white-space: nowrap;
    }
  }
</style>
