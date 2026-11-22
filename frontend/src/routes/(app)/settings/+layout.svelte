<script lang="ts">
  import { page } from '$app/state';
  import { settingsItemForPath, filterSettings } from '$lib/settings-nav.js';
  import { instanceName } from '$lib/stores/instance.js';
  import { t } from '$lib/stores/i18n.js';
  import { currentUser } from '$lib/stores/auth.js';
  import type { Identity } from '$lib/api/types.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import SettingsNav from '$lib/components/settings/SettingsNav.svelte';

  let { children } = $props();

  let isIndex = $derived(page.url.pathname === '/settings' || page.url.pathname === '/settings/');
  let currentItem = $derived(settingsItemForPath(page.url.pathname));
  let user = $derived($currentUser as Identity | null);

  let query = $state('');
  let groups = $derived(filterSettings(query, (k) => $t(k)));
</script>

<svelte:head>
  <title>{currentItem ? `${$t(currentItem.labelKey)} - ` : ''}{$t('nav.settings')} - {$instanceName}</title>
</svelte:head>

<div class="settings-container">
<div class="settings-shell" class:is-index={isIndex}>
  {#if !isIndex}
    <!-- Section sidebar: shown beside the page when there is room. -->
    <aside class="settings-aside">
      <div class="aside-inner">
        {#if user}
          <a href="/settings" class="aside-identity">
            <Avatar src={user.avatar_url} name={user.display_name || user.handle} size="sm" />
            <span class="aside-identity-text">
              <span class="aside-name">{user.display_name || user.handle}</span>
              <span class="aside-sub">{$t('nav.settings')}</span>
            </span>
          </a>
        {/if}
        <label class="settings-search">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="8" /><line x1="21" y1="21" x2="16.65" y2="16.65" /></svg>
          <input type="search" bind:value={query} placeholder={$t('settings.search_placeholder')} aria-label={$t('settings.search_placeholder')} />
        </label>
        {#if groups.length}
          <SettingsNav {groups} activeHref={currentItem?.href ?? ''} />
        {:else}
          <p class="search-empty">{$t('settings.search_empty', { query })}</p>
        {/if}
      </div>
    </aside>
  {/if}

  <div class="settings-main">
    {#if !isIndex}
      <header class="settings-topbar">
        <a href="/settings" class="settings-back">
          <svg class="rtl-mirror" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="15 18 9 12 15 6" /></svg>
          {$t('nav.settings')}
        </a>
        {#if currentItem}
          <h1 class="settings-title">{$t(currentItem.labelKey)}</h1>
          <p class="settings-subtitle">{$t(currentItem.descKey)}</p>
        {/if}
      </header>
    {/if}

    <div class="settings-body">
      {@render children()}
    </div>
  </div>
</div>
</div>

<style>
  /* Pane decisions follow the space this area actually gets, not the
     viewport: the app sidebar collapses at its own breakpoints. The query
     container is this wrapper, so the shell inside can change its grid. */
  .settings-container {
    container: settings / inline-size;
    width: 100%;
  }

  .settings-shell {
    width: 100%;
    max-width: 1080px;
    margin: 0 auto;
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: var(--space-8);
  }

  .settings-shell.is-index {
    max-width: 960px;
  }

  .settings-aside {
    display: none;
  }

  .settings-main {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .settings-topbar {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .settings-back {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    align-self: flex-start;
    padding: 4px 8px;
    margin-inline-start: -8px;
    margin-block-end: var(--space-1);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text-secondary);
    text-decoration: none;
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .settings-back:hover {
    background: var(--color-surface-container-low);
    color: var(--color-primary);
    text-decoration: none;
  }

  .settings-back:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .settings-title {
    font-family: var(--font-headline, inherit);
    font-size: var(--text-2xl);
    font-weight: 800;
    letter-spacing: -0.01em;
    color: var(--color-text);
  }

  .settings-subtitle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .settings-body {
    min-width: 0;
  }

  /* ---- Sidebar contents ---- */
  .aside-inner {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .aside-identity {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-lg);
    color: var(--color-text);
    text-decoration: none;
  }

  .aside-identity:hover {
    background: var(--color-surface-container-low);
    text-decoration: none;
  }

  .aside-identity-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .aside-name {
    font-weight: 700;
    font-size: var(--text-sm);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .aside-sub {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .settings-search {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: 0 var(--space-3);
    min-height: 40px;
    border: 1px solid var(--color-border);
    border-radius: 999px;
    background: var(--color-surface-raised);
    color: var(--color-text-tertiary);
    transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
  }

  .settings-search:focus-within {
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px var(--color-primary-soft);
  }

  .settings-search input {
    flex: 1;
    min-width: 0;
    border: 0;
    outline: 0;
    background: transparent;
    font: inherit;
    font-size: var(--text-sm);
    color: var(--color-text);
  }

  .search-empty {
    padding: 0 var(--space-3);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  /* ---- Two panes once there is room for both ---- */
  @container settings (min-width: 820px) {
    .settings-shell:not(.is-index) {
      grid-template-columns: 232px minmax(0, 1fr);
    }

    .settings-aside {
      display: block;
      position: sticky;
      inset-block-start: calc(var(--header-height) + var(--space-4));
      align-self: start;
      max-height: calc(100dvh - var(--header-height) - var(--space-8));
      overflow-y: auto;
    }

    .settings-back {
      display: none;
    }
  }
</style>
