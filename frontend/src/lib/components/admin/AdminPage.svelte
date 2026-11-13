<script lang="ts">
  // Standard admin page frame: title, one-line purpose, actions, content.
  // `width="narrow"` caps forms at a readable measure; tables and dashboards
  // use the default full width.
  import type { Snippet } from 'svelte';

  let {
    title,
    description = '',
    width = 'wide',
    actions,
    children,
  }: {
    title: string;
    description?: string;
    width?: 'narrow' | 'wide';
    actions?: Snippet;
    children: Snippet;
  } = $props();
</script>

<svelte:head>
  <title>{title} - Admin</title>
</svelte:head>

<div class="admin-page" class:narrow={width === 'narrow'}>
  <header class="admin-page-header">
    <div class="admin-page-heading">
      <h1 class="admin-page-title">{title}</h1>
      {#if description}
        <p class="admin-page-description">{description}</p>
      {/if}
    </div>
    {#if actions}
      <div class="admin-page-actions">{@render actions()}</div>
    {/if}
  </header>

  {@render children()}
</div>

<style>
  .admin-page {
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
    min-width: 0;
  }

  .admin-page.narrow {
    max-width: 760px;
  }

  .admin-page-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-4);
    flex-wrap: wrap;
  }

  .admin-page-heading {
    min-width: 0;
    flex: 1 1 320px;
  }

  .admin-page-title {
    margin: 0;
    font-size: var(--text-2xl);
    font-weight: 700;
    color: var(--color-text);
  }

  .admin-page-description {
    margin: 4px 0 0;
    max-width: 60ch;
    font-size: var(--text-sm);
    line-height: 1.5;
    color: var(--color-text-secondary);
  }

  .admin-page-actions {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-wrap: wrap;
  }
</style>
