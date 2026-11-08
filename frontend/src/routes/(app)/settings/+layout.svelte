<script lang="ts">
  import { page } from '$app/state';
  import { settingsItemForPath } from '$lib/settings-nav.js';
  import { instanceName } from '$lib/stores/instance.js';

  let { children } = $props();

  let isIndex = $derived(page.url.pathname === '/settings');
  let currentItem = $derived(settingsItemForPath(page.url.pathname));
</script>

<svelte:head>
  <title>Settings - {$instanceName}</title>
</svelte:head>

<div class="settings-shell" class:is-index={isIndex}>
  <header class="settings-topbar">
    {#if isIndex}
      <h1 class="settings-title">Settings</h1>
    {:else}
      <a href="/settings" class="settings-back">
        <svg class="rtl-mirror" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="15 18 9 12 15 6"/></svg>
        Settings
      </a>
      {#if currentItem}
        <h1 class="settings-title">{currentItem.label}</h1>
      {/if}
    {/if}
  </header>

  <div class="settings-body">
    {@render children()}
  </div>
</div>

<style>
  .settings-shell {
    width: 100%;
    max-width: 760px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  /* The index card grid gets more room to breathe than the forms. */
  .settings-shell.is-index {
    max-width: 900px;
  }

  .settings-topbar {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .settings-back {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    align-self: flex-start;
    padding: 4px 8px;
    margin-inline-start: -8px;
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
</style>
