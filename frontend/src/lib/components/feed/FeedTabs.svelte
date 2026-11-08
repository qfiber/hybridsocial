<script lang="ts">
  // Generalized sliding-pill tab switcher. Used by TimelineFeed for both
  // the home (Latest / For You / Top) and explore (Local / Global /
  // Trending) feeds, so the tab styling lives in exactly one place.
  interface Tab {
    id: string;
    label: string;
    /** Optional Material Symbols glyph name shown before the label. */
    icon?: string;
  }

  let {
    tabs,
    active,
    onchange,
  }: {
    tabs: Tab[];
    active: string;
    onchange?: (id: string) => void;
  } = $props();

  let activeIndex = $derived(Math.max(0, tabs.findIndex((t) => t.id === active)));
</script>

<div class="feed-tabs" role="tablist" aria-label="Feed type">
  <div
    class="feed-tabs-slider"
    style="inset-inline-start: calc({activeIndex} * (100% / {tabs.length}) + 3px); width: calc(100% / {tabs.length} - 6px);"
    aria-hidden="true"
  ></div>
  {#each tabs as tab (tab.id)}
    <button
      type="button"
      role="tab"
      class="feed-tab"
      class:feed-tab-active={active === tab.id}
      aria-selected={active === tab.id}
      onclick={() => tab.id !== active && onchange?.(tab.id)}
    >
      {#if tab.icon}
        <span class="material-symbols-outlined feed-tab-icon" aria-hidden="true">{tab.icon}</span>
      {/if}
      {tab.label}
    </button>
  {/each}
</div>

<style>
  .feed-tabs {
    position: relative;
    display: flex;
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    padding: 3px;
    max-width: 420px;
    width: 100%;
    margin: 0 auto;
    box-shadow: var(--shadow-sm);
  }

  .feed-tab {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    padding: 8px 16px;
    white-space: nowrap;
    background: transparent;
    border: none;
    border-radius: 9999px;
    font-family: 'Inter', var(--font-sans);
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: color 200ms ease;
    position: relative;
    z-index: 1;
    text-align: center;
  }

  .feed-tab:hover {
    color: var(--color-text);
  }

  .feed-tab-active,
  .feed-tab-active:hover {
    color: var(--color-on-primary);
  }

  .feed-tab-icon {
    font-size: 18px;
  }

  .feed-tabs-slider {
    position: absolute;
    top: 3px;
    bottom: 3px;
    background: var(--gradient-primary);
    border-radius: 9999px;
    box-shadow: 0 1px 4px rgba(var(--color-primary-rgb), 0.18);
    /* Logical offset: the tabs flow right-to-left in an RTL locale, so a
       physical `left` drew the highlight over the mirrored tab — tapping
       "Local" lit up "Trending" (the right feed loaded; only the pill lied). */
    transition:
      inset-inline-start 0.25s cubic-bezier(0.22, 1, 0.36, 1),
      width 0.25s cubic-bezier(0.22, 1, 0.36, 1);
  }
</style>
