<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Tab {
    id: string;
    label: string;
  }

  let {
    tabs,
    active = $bindable(''),
    children,
    header,
    sticky = true,
    stickyTop = 'var(--header-height)',
  }: {
    tabs: Tab[];
    active?: string;
    children?: Snippet;
    /** Rendered inside the pinned bar, above the tab row (a section title,
        search…), so it stays in view with the tabs. */
    header?: Snippet;
    /** Keep the tab row in view while the panel scrolls (default). */
    sticky?: boolean;
    /** Where the bar pins — below the app header by default; a page with
        its own pinned title above passes that offset too. */
    stickyTop?: string;
  } = $props();

  // Default to first tab
  if (!active && tabs?.length > 0) {
    active = tabs[0].id;
  }
</script>

<div class="tabs-container">
  <div class="tabs-bar" class:tabs-bar-sticky={sticky} style:--tabs-sticky-top={stickyTop}>
  {#if header}{@render header()}{/if}
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

  /* The section's options stay in view while its content scrolls: the tab
     row (and any header passed in) pins under the app header on a solid
     surface. */
  .tabs-bar-sticky {
    position: sticky;
    inset-block-start: var(--tabs-sticky-top, var(--header-height));
    z-index: var(--z-sticky);
    background: var(--color-surface-base, var(--color-bg));
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
