<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Tab {
    id: string;
    label: string;
  }

  let {
    tabs,
    active = $bindable(''),
    children
  }: {
    tabs: Tab[];
    active?: string;
    children?: Snippet;
  } = $props();

  // Default to first tab
  if (!active && tabs?.length > 0) {
    active = tabs[0].id;
  }
</script>

<div class="tabs-container">
  <div class="tabs-list" role="tablist">
    {#each tabs as tab (tab.id)}
      <button
        class="tab-item"
        class:active={active === tab.id}
        role="tab"
        aria-selected={active === tab.id}
        id="tab-{tab.id}"
        aria-controls="tabpanel-{tab.id}"
        onclick={() => (active = tab.id)}
        type="button"
      >
        {tab.label}
      </button>
    {/each}
  </div>
  <div
    class="tab-panel"
    role="tabpanel"
    id="tabpanel-{active}"
    aria-labelledby="tab-{active}"
  >
    {#if children}{@render children()}{/if}
  </div>
</div>

<style>
  .tabs-container {
    width: 100%;
  }

  .tabs-list {
    display: flex;
    border-block-end: 1px solid var(--color-border);
    gap: 0;
    overflow-x: auto;
    scrollbar-width: none;
  }

  .tabs-list::-webkit-scrollbar {
    display: none;
  }

  .tab-item {
    position: relative;
    padding: var(--space-3) var(--space-4);
    border: none;
    background: none;
    font-size: var(--text-sm);
    font-weight: var(--font-medium);
    color: var(--color-text-secondary);
    cursor: pointer;
    white-space: nowrap;
    transition: color var(--transition-fast);
  }

  .tab-item:hover {
    color: var(--color-text);
  }

  .tab-item.active {
    color: var(--color-primary);
  }

  .tab-item.active::after {
    content: '';
    position: absolute;
    inset-inline: 0;
    bottom: -1px;
    height: 2px;
    background-color: var(--color-primary);
    border-radius: var(--radius-full) var(--radius-full) 0 0;
  }

  .tab-panel {
    padding-block-start: var(--space-4);
  }
</style>
