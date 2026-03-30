<script lang="ts">
  export type FeedTab = 'latest' | 'foryou' | 'top';

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
    { id: 'top', label: 'Top' },
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
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    padding: 3px;
    max-width: 420px;
    width: 100%;
    margin: 0 auto;
  }

  .toggle-tab {
    flex: 1;
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

  .toggle-tab:hover {
    color: var(--color-text);
  }

  .toggle-active {
    color: var(--color-on-primary);
  }

  .toggle-active:hover {
    color: var(--color-on-primary);
  }

  .toggle-slider {
    position: absolute;
    top: 3px;
    bottom: 3px;
    background: var(--color-primary);
    border-radius: 9999px;
    transition: left 0.25s cubic-bezier(0.22, 1, 0.36, 1), width 0.25s cubic-bezier(0.22, 1, 0.36, 1);
  }
</style>
