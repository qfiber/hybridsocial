<script lang="ts">
  import { goto } from '$app/navigation';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Dropdown from '$lib/components/ui/Dropdown.svelte';
  import { currentUser, isLoggedIn, clearAuth } from '$lib/stores/auth.js';
  import { unreadCount } from '$lib/stores/notifications.js';
  import { api } from '$lib/api/client.js';
  import type { Identity } from '$lib/api/types.js';

  let user: Identity | null = $state(null);
  let authenticated = $state(false);
  let searchQuery = $state('');
  let notifCount = $state(0);

  currentUser.subscribe((v) => (user = v));
  isLoggedIn.subscribe((v) => (authenticated = v));
  unreadCount.subscribe((v) => (notifCount = v));

  function handleSearch(e: Event) {
    e.preventDefault();
    if (searchQuery.trim()) {
      const q = searchQuery.trim();
      searchQuery = '';
      goto(`/explore?q=${encodeURIComponent(q)}`);
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
    <!-- Logo + Nav -->
    <div class="header-start">
      <a href="/home" class="header-logo" aria-label="HybridSocial home">
        <svg class="logo-mark" width="32" height="32" viewBox="0 0 32 32" fill="none">
          <rect width="32" height="32" rx="10" fill="url(#logo-grad)" />
          <text x="16" y="22" text-anchor="middle" fill="white" font-size="16" font-weight="800" font-family="'Manrope', sans-serif">H</text>
          <defs>
            <linearGradient id="logo-grad" x1="0" y1="0" x2="32" y2="32">
              <stop offset="0%" stop-color="#006a69" />
              <stop offset="100%" stop-color="#0ea5a4" />
            </linearGradient>
          </defs>
        </svg>
        <span class="header-logo-text">HybridSocial</span>
      </a>

      <nav class="header-nav" aria-label="Main navigation">
        <a href="/explore" class="header-nav-link">Explore</a>
        <a href="/tags/trending" class="header-nav-link">Trends</a>
      </nav>
    </div>

    <!-- Search -->
    <form class="header-search" onsubmit={handleSearch}>
      <svg class="search-icon" width="16" height="16" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <circle cx="9" cy="9" r="7" />
        <line x1="14" y1="14" x2="19" y2="19" />
      </svg>
      <input
        type="search"
        bind:value={searchQuery}
        placeholder="Search HybridSocial..."
        class="search-input"
        aria-label="Search"
      />
    </form>

    <!-- Actions -->
    <div class="header-actions">
      {#if authenticated && user}
        <!-- Notifications -->
        <a href="/notifications" class="header-icon-btn" aria-label="Notifications">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
            <path d="M13.73 21a2 2 0 0 1-3.46 0" />
          </svg>
          {#if notifCount > 0}
            <span class="icon-badge">{notifCount > 99 ? '99+' : notifCount}</span>
          {/if}
        </a>

        <!-- Messages -->
        <a href="/messages" class="header-icon-btn" aria-label="Messages">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z" />
            <polyline points="22,6 12,13 2,6" />
          </svg>
        </a>

        <!-- User avatar dropdown -->
        <Dropdown align="end">
          {#snippet trigger()}
            <button class="avatar-btn" type="button" aria-label="Account menu">
              <span class="avatar-ring">
                <Avatar src={user.avatar_url} name={user.display_name || user.handle} size="sm" />
              </span>
            </button>
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
    background: rgba(255, 255, 255, 0.8);
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
    border-block-end: var(--ghost-border);
    z-index: var(--z-header);
  }

  .header-inner {
    display: flex;
    align-items: center;
    gap: var(--space-6);
    max-width: var(--layout-max-width);
    margin: 0 auto;
    height: 100%;
    padding: 0 var(--space-6);
  }

  /* --- Logo + Nav group --- */
  .header-start {
    display: flex;
    align-items: center;
    gap: var(--space-6);
    flex-shrink: 0;
  }

  .header-logo {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    text-decoration: none;
    color: var(--color-on-surface);
    flex-shrink: 0;
  }

  .header-logo:hover {
    text-decoration: none;
  }

  .header-logo-text {
    font-family: var(--font-headline);
    font-weight: 800;
    font-size: var(--text-lg);
    color: var(--color-primary);
    letter-spacing: -0.02em;
  }

  .header-nav {
    display: flex;
    align-items: center;
    gap: var(--space-1);
  }

  .header-nav-link {
    display: inline-flex;
    align-items: center;
    padding: var(--space-2) var(--space-3);
    font-family: var(--font-body);
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-on-surface-variant);
    text-decoration: none;
    border-radius: var(--radius-full);
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .header-nav-link:hover {
    background: var(--color-surface-container-low);
    color: var(--color-on-surface);
    text-decoration: none;
  }

  /* --- Search --- */
  .header-search {
    flex: 1;
    max-width: 420px;
    position: relative;
  }

  .search-icon {
    position: absolute;
    inset-inline-start: var(--space-4);
    top: 50%;
    transform: translateY(-50%);
    color: var(--color-text-tertiary);
    pointer-events: none;
  }

  .search-input {
    width: 100%;
    height: 40px;
    padding: var(--space-2) var(--space-4);
    padding-inline-start: var(--space-10);
    border: none;
    border-radius: var(--radius-full);
    font-family: var(--font-body);
    font-size: var(--text-sm);
    background: var(--color-surface-container-high);
    color: var(--color-on-surface);
    transition:
      background var(--transition-fast),
      box-shadow var(--transition-fast);
  }

  .search-input::placeholder {
    color: var(--color-text-tertiary);
  }

  .search-input:focus {
    outline: none;
    background: var(--color-surface-container-lowest);
    box-shadow: 0 0 0 2px var(--color-primary);
  }

  /* --- Actions --- */
  .header-actions {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-shrink: 0;
    margin-inline-start: auto;
  }

  .header-icon-btn {
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    border-radius: var(--radius-full);
    color: var(--color-on-surface-variant);
    text-decoration: none;
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .header-icon-btn:hover {
    background: var(--color-surface-container-low);
    color: var(--color-on-surface);
    text-decoration: none;
  }

  .icon-badge {
    position: absolute;
    top: 4px;
    inset-inline-end: 4px;
    min-width: 18px;
    height: 18px;
    padding: 0 5px;
    font-family: var(--font-body);
    font-size: 0.65rem;
    font-weight: 700;
    line-height: 18px;
    text-align: center;
    color: var(--color-on-primary);
    background: var(--color-error);
    border-radius: var(--radius-full);
    border: 2px solid rgba(255, 255, 255, 0.8);
  }

  .avatar-btn {
    background: none;
    border: none;
    padding: 0;
    cursor: pointer;
    border-radius: var(--radius-full);
  }

  .avatar-ring {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 2px;
    border: 2px solid var(--color-primary);
    border-radius: var(--radius-full);
    transition: border-color var(--transition-fast);
  }

  .avatar-btn:hover .avatar-ring {
    border-color: var(--color-primary-container);
  }

  /* --- Responsive --- */
  @media (max-width: 1024px) {
    .header-nav {
      display: none;
    }
  }

  @media (max-width: 768px) {
    .header-inner {
      padding: 0 var(--space-3);
      gap: var(--space-3);
    }

    .header-logo-text {
      display: none;
    }

    .header-search {
      max-width: none;
    }

    .header-nav {
      display: none;
    }
  }
</style>
