<script lang="ts">
  export type FeedTab = 'latest' | 'foryou' | 'trending';

  let {
    active = 'latest',
    onchange,
  }: {
    active?: FeedTab;
    onchange?: (tab: FeedTab) => void;
  } = $props();

  const tabs: { id: FeedTab; label: string }[] = [
    { id: 'latest', label: 'Latest' },
    { id: 'foryou', label: 'For You' },
    { id: 'trending', label: 'Trending' },
  ];

  let activeIndex = $derived(tabs.findIndex(t => t.id === active));

  function handleTabClick(tab: FeedTab) {
    if (tab !== active) {
      onchange?.(tab);
    }
  }
</script>

<div class="feed-toggle" role="tablist" aria-label="Feed type">
  <div
    class="toggle-slider"
    style="left: calc({activeIndex} * (100% / {tabs.length}) + 3px); width: calc(100% / {tabs.length} - 6px);"
    aria-hidden="true"
  ></div>
  {#each tabs as tab}
    <button
      type="button"
      role="tab"
      class="toggle-tab"
      class:toggle-active={active === tab.id}
      aria-selected={active === tab.id}
      onclick={() => handleTabClick(tab.id)}
    >
      {tab.label}
    </button>
  {/each}
</div>

<style>
  .feed-toggle {
    position: relative;
    display: flex;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full);
    padding: 3px;
    max-width: 420px;
    width: 100%;
    margin: 0 auto;
  }

  .toggle-tab {
    flex: 1;
    padding: var(--space-2) var(--space-4);
    white-space: nowrap;
    background: transparent;
    border: none;
    border-radius: var(--radius-full);
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text-tertiary);
    cursor: pointer;
    transition: color 0.2s ease;
    position: relative;
    z-index: 1;
    text-align: center;
  }

  .toggle-tab:hover {
    color: var(--color-text-secondary);
  }

  .toggle-active {
    color: var(--color-text-on-primary);
  }

  .toggle-active:hover {
    color: var(--color-text-on-primary);
  }

  .toggle-slider {
    position: absolute;
    top: 3px;
    bottom: 3px;
    background: var(--color-primary);
    border-radius: var(--radius-full);
    transition: left 0.25s cubic-bezier(0.22, 1, 0.36, 1), width 0.25s cubic-bezier(0.22, 1, 0.36, 1);
  }
</style>
