<script lang="ts">
  import { goto } from '$app/navigation';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Dropdown from '$lib/components/ui/Dropdown.svelte';
  import { currentUser, isLoggedIn, clearAuth } from '$lib/stores/auth.js';
  import { api } from '$lib/api/client.js';
  import type { Identity } from '$lib/api/types.js';

  let user: Identity | null = $state(null);
  let authenticated = $state(false);
  let searchQuery = $state('');

  currentUser.subscribe((v) => (user = v));
  isLoggedIn.subscribe((v) => (authenticated = v));

  function handleSearch(e: Event) {
    e.preventDefault();
    if (searchQuery.trim()) {
      goto(`/explore?q=${encodeURIComponent(searchQuery.trim())}`);
    }
  }

  async function handleLogout() {
    try {
      await api.post('/api/v1/auth/logout');
    } catch {
      // Proceed with logout even if API call fails
    }
    clearAuth();
    goto('/login');
  }
</script>

<header class="header">
  <div class="header-inner">
    <a href="/home" class="header-logo" aria-label="HybridSocial home">
      <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
        <circle cx="14" cy="14" r="14" fill="var(--color-primary)" />
        <text x="14" y="19" text-anchor="middle" fill="white" font-size="14" font-weight="700">H</text>
      </svg>
      <span class="header-logo-text">HybridSocial</span>
    </a>

    <form class="header-search" onsubmit={handleSearch}>
      <svg class="search-icon" width="16" height="16" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <circle cx="9" cy="9" r="7" />
        <line x1="14" y1="14" x2="19" y2="19" />
      </svg>
      <input
        type="search"
        bind:value={searchQuery}
        placeholder="Search..."
        class="search-input"
        aria-label="Search"
      />
    </form>

    <div class="header-actions">
      {#if authenticated && user}
        <Dropdown align="end">
          {#snippet trigger()}
            <Avatar src={user.avatar_url} name={user.display_name || user.handle} size="sm" />
          {/snippet}
          <a href="/@{user.handle}">Profile</a>
          <a href="/settings">Settings</a>
          {#if user.is_admin}
            <a href="/admin">Admin</a>
          {/if}
          <div class="dropdown-divider"></div>
          <button class="dropdown-item-danger" onclick={handleLogout} type="button">Log out</button>
        </Dropdown>
      {/if}
    </div>
  </div>
</header>

<style>
  .header {
    position: fixed;
    top: 0;
    inset-inline: 0;
    height: var(--header-height);
    background: var(--color-surface-raised);
    border-block-end: 1px solid var(--color-border);
    z-index: var(--z-sticky);
  }

  .header-inner {
    display: flex;
    align-items: center;
    gap: var(--space-4);
    max-width: 1200px;
    margin: 0 auto;
    height: 100%;
    padding: 0 var(--space-4);
  }

  .header-logo {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    text-decoration: none;
    color: var(--color-text);
    font-weight: 700;
    font-size: var(--text-lg);
    flex-shrink: 0;
  }

  .header-logo:hover {
    text-decoration: none;
  }

  .header-search {
    flex: 1;
    max-width: 400px;
    margin: 0 auto;
    position: relative;
  }

  .search-icon {
    position: absolute;
    inset-inline-start: var(--space-3);
    top: 50%;
    transform: translateY(-50%);
    color: var(--color-text-tertiary);
    pointer-events: none;
  }

  .search-input {
    width: 100%;
    height: 36px;
    padding: var(--space-2) var(--space-3);
    padding-inline-start: var(--space-10);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full);
    font-size: var(--text-sm);
    background: var(--color-surface);
    color: var(--color-text);
    transition: border-color var(--transition-fast), background var(--transition-fast);
  }

  .search-input::placeholder {
    color: var(--color-text-tertiary);
  }

  .search-input:focus {
    outline: none;
    border-color: var(--color-primary);
    background: var(--color-bg);
  }

  .header-actions {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    flex-shrink: 0;
  }

  @media (max-width: 768px) {
    .header-logo-text {
      display: none;
    }

    .header-search {
      max-width: none;
    }
  }
</style>
