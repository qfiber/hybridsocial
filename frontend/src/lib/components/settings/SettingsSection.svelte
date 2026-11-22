<script lang="ts">
  // A card grouping related settings under a heading and a one-line "why".
  import type { Snippet } from 'svelte';

  let {
    title,
    description = '',
    children,
  }: { title: string; description?: string; children: Snippet } = $props();
</script>

<section class="settings-section">
  <header class="settings-section-header">
    <h2 class="settings-section-title">{title}</h2>
    {#if description}
      <p class="settings-section-description">{description}</p>
    {/if}
  </header>
  <div class="settings-section-body">
    {@render children()}
  </div>
</section>

<style>
  .settings-section {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow: hidden;
  }

  .settings-section-header {
    padding: var(--space-4) var(--space-5);
    border-block-end: 1px solid var(--color-border);
  }

  .settings-section-title {
    margin: 0;
    font-size: var(--text-base);
    font-weight: 700;
    color: var(--color-text);
  }

  .settings-section-description {
    margin: 2px 0 0;
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.45;
  }

  .settings-section-body {
    display: flex;
    flex-direction: column;
  }

  .settings-section-body > :global(* + *) {
    border-block-start: 1px solid var(--color-border);
  }
</style>
