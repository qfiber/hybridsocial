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
    { href: '/settings/filters', label: 'Content Filters', icon: 'M22 3H2l8 9.46V19l4 2v-8.54L22 3z' },
    { href: '/settings/blocks', label: 'Blocks', icon: 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM4.93 4.93l14.14 14.14' },
    { href: '/settings/mutes', label: 'Mutes', icon: 'M1 1l22 22M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6' },
    { href: '/settings/follow-requests', label: 'Follow Requests', icon: 'M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M8.5 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM17 11l2 2 4-4' },
    { href: '/settings/sessions', label: 'Sessions', icon: 'M2 3h20a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H2a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM8 21h8M12 17v4' },
    { href: '/settings/import-export', label: 'Import / Export', icon: 'M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3' },
    { href: '/settings/migration', label: 'Migration', icon: 'M15 3l6 6-6 6M9 21l-6-6 6-6M21 9H14M3 15h7' },
    { href: '/settings/donations', label: 'Donations', icon: 'M12 2v20M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6' },
    { href: '/settings/developers', label: 'Developers', icon: 'M16 18l6-6-6-6M8 6l-6 6 6 6' },
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
