<script lang="ts">
  import { currentUser } from '$lib/stores/auth.js';
  import { filterSettings } from '$lib/settings-nav.js';
  import type { Identity } from '$lib/api/types.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import SettingsNav from '$lib/components/settings/SettingsNav.svelte';
  import { t } from '$lib/stores/i18n.js';

  let user = $derived($currentUser as Identity | null);
  let query = $state('');
  let groups = $derived(filterSettings(query, (k) => $t(k)));
</script>

<div class="settings-index">
  <h1 class="index-title">{$t('nav.settings')}</h1>

  {#if user}
    <a href="/@{user.handle}" class="hero">
      <span class="hero-banner" style:background-image={user.header_url ? `url("${user.header_url}")` : undefined}></span>
      <span class="hero-body">
        <span class="hero-avatar"><Avatar src={user.avatar_url} name={user.display_name || user.handle} size="lg" /></span>
        <span class="hero-text">
          <span class="hero-name">{user.display_name || user.handle}</span>
          <span class="hero-handle" dir="ltr">@{user.acct || user.handle}</span>
        </span>
        <span class="hero-view">
          {$t('settings.view_profile')}
          <svg class="rtl-mirror" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="9 18 15 12 9 6" /></svg>
        </span>
      </span>
    </a>
  {/if}

  <label class="index-search">
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="8" /><line x1="21" y1="21" x2="16.65" y2="16.65" /></svg>
    <input type="search" bind:value={query} placeholder={$t('settings.search_placeholder')} aria-label={$t('settings.search_placeholder')} />
  </label>

  {#if groups.length}
    <SettingsNav {groups} variant="detailed" />
  {:else}
    <p class="search-empty">{$t('settings.search_empty', { query })}</p>
  {/if}
</div>

<style>
  .settings-index {
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .index-title {
    font-family: var(--font-headline, inherit);
    font-size: var(--text-2xl);
    font-weight: 800;
    letter-spacing: -0.01em;
    color: var(--color-text);
  }

  /* Profile hero: the user's own header image behind their identity. */
  .hero {
    position: relative;
    display: block;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow: hidden;
    background: var(--color-surface-raised);
    color: var(--color-text);
    text-decoration: none;
    box-shadow: var(--shadow-sm);
    transition: box-shadow var(--transition-fast), border-color var(--transition-fast);
  }

  .hero:hover {
    border-color: var(--color-primary);
    text-decoration: none;
  }

  .hero:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .hero-banner {
    display: block;
    height: 96px;
    background-color: var(--color-primary-soft);
    background-image: linear-gradient(135deg, var(--color-primary-soft), var(--color-surface-container-low));
    background-size: cover;
    background-position: center;
  }

  .hero-body {
    display: flex;
    align-items: flex-end;
    gap: var(--space-3);
    padding: 0 var(--space-4) var(--space-4);
    margin-block-start: -28px;
  }

  .hero-avatar {
    flex-shrink: 0;
    border-radius: 999px;
    box-shadow: 0 0 0 4px var(--color-surface-raised);
    line-height: 0;
  }

  .hero-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
    padding-block-end: 2px;
  }

  .hero-name {
    font-weight: 800;
    font-size: var(--text-lg);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .hero-handle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    text-align: start;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .hero-view {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    flex-shrink: 0;
    padding-block-end: 4px;
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-primary);
  }

  .index-search {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: 0 var(--space-4);
    min-height: 46px;
    border: 1px solid var(--color-border);
    border-radius: 999px;
    background: var(--color-surface-raised);
    color: var(--color-text-tertiary);
    transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
  }

  .index-search:focus-within {
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px var(--color-primary-soft);
  }

  .index-search input {
    flex: 1;
    min-width: 0;
    border: 0;
    outline: 0;
    background: transparent;
    font: inherit;
    font-size: var(--text-base);
    color: var(--color-text);
  }

  .search-empty {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  @media (max-width: 480px) {
    .hero-view {
      display: none;
    }
  }
</style>
