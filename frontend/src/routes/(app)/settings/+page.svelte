<script lang="ts">
  import { currentUser } from '$lib/stores/auth.js';
  import { settingsGroups } from '$lib/settings-nav.js';
  import type { Identity } from '$lib/api/types.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import { instanceName } from '$lib/stores/instance.js';

  let user = $derived($currentUser as Identity | null);
</script>

<svelte:head>
  <title>Settings - {$instanceName}</title>
</svelte:head>

<div class="settings-index">
  {#if user}
    <a href="/@{user.handle}" class="identity-card">
      <Avatar src={user.avatar_url} name={user.display_name || user.handle} size="lg" />
      <div class="identity-text">
        <span class="identity-name">{user.display_name || user.handle}</span>
        <span class="identity-handle">@{user.acct || user.handle}</span>
      </div>
      <span class="identity-view">View profile
        <svg class="rtl-mirror" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="9 18 15 12 9 6"/></svg>
      </span>
    </a>
  {/if}

  {#each settingsGroups as group (group.title)}
    <section class="settings-group">
      <h2 class="group-title">{group.title}</h2>
      <div class="card-grid">
        {#each group.items as item (item.href)}
          <a href={item.href} class="settings-card">
            <span class="card-icon">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d={item.icon} />
              </svg>
            </span>
            <span class="card-text">
              <span class="card-label">{item.label}</span>
              <span class="card-desc">{item.description}</span>
            </span>
            <svg class="rtl-mirror card-chevron" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="9 18 15 12 9 6"/></svg>
          </a>
        {/each}
      </div>
    </section>
  {/each}
</div>

<style>
  .settings-index {
    display: flex;
    flex-direction: column;
    gap: var(--space-6);
  }

  .identity-card {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-4);
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    text-decoration: none;
    color: var(--color-text);
    box-shadow: var(--shadow-sm);
    transition: background var(--transition-fast);
  }

  .identity-card:hover {
    background: var(--color-surface-container-low);
    text-decoration: none;
  }

  .identity-card:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .identity-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
  }

  .identity-name {
    font-weight: 700;
    font-size: var(--text-base);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .identity-handle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .identity-view {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    flex-shrink: 0;
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-primary);
  }

  .settings-group {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .group-title {
    font-size: var(--text-xs);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--color-text-tertiary);
    padding-inline: var(--space-1);
  }

  .card-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
    gap: var(--space-3);
  }

  .settings-card {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-4);
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    text-decoration: none;
    color: var(--color-text);
    transition: background var(--transition-fast), border-color var(--transition-fast), transform var(--transition-fast);
  }

  .settings-card:hover {
    background: var(--color-surface-container-low);
    border-color: var(--color-primary);
    text-decoration: none;
  }

  .settings-card:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .card-icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    flex-shrink: 0;
    border-radius: var(--radius-md);
    background: var(--color-primary-soft);
    color: var(--color-primary);
  }

  .card-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
    gap: 1px;
  }

  .card-label {
    font-weight: 600;
    font-size: var(--text-sm);
  }

  .card-desc {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    line-height: 1.35;
  }

  .card-chevron {
    flex-shrink: 0;
    color: var(--color-text-tertiary);
  }
</style>
