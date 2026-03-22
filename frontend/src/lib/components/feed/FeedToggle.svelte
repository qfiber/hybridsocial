<script lang="ts">
  let {
    active = 'latest',
    onchange,
  }: {
    active?: 'latest' | 'foryou';
    onchange?: (tab: 'latest' | 'foryou') => void;
  } = $props();

  let isLatest = $derived(active === 'latest');

  function handleTabClick(tab: 'latest' | 'foryou') {
    if (tab !== active) {
      onchange?.(tab);
    }
  }

  function handleKeydown(e: KeyboardEvent, tab: 'latest' | 'foryou') {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      handleTabClick(tab);
    }
  }
</script>

<div class="feed-toggle" role="tablist" aria-label="Feed type">
  <button
    type="button"
    role="tab"
    class="toggle-tab"
    class:toggle-active={isLatest}
    aria-selected={isLatest}
    onclick={() => handleTabClick('latest')}
    onkeydown={(e) => handleKeydown(e, 'latest')}
  >
    Latest
  </button>
  <button
    type="button"
    role="tab"
    class="toggle-tab"
    class:toggle-active={!isLatest}
    aria-selected={!isLatest}
    onclick={() => handleTabClick('foryou')}
    onkeydown={(e) => handleKeydown(e, 'foryou')}
  >
    For You
  </button>
  <div
    class="toggle-indicator"
    class:indicator-right={!isLatest}
    aria-hidden="true"
  ></div>
</div>

<style>
  .feed-toggle {
    position: relative;
    display: flex;
    background: var(--color-bg-tertiary);
    border-radius: var(--radius-lg);
    padding: 3px;
    max-width: 280px;
    margin: 0 auto var(--space-4);
  }

  .toggle-tab {
    flex: 1;
    padding: var(--space-2) var(--space-4);
    background: transparent;
    border: none;
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-weight: var(--font-medium);
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: color var(--transition-fast);
    position: relative;
    z-index: 1;
  }

  .toggle-tab:hover {
    color: var(--color-text);
  }

  .toggle-active {
    color: var(--color-text);
  }

  .toggle-indicator {
    position: absolute;
    inset-block-start: 3px;
    inset-block-end: 3px;
    inset-inline-start: 3px;
    width: calc(50% - 3px);
    background: var(--color-surface);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow-sm);
    transition: inset-inline-start var(--transition-base);
  }

  .indicator-right {
    inset-inline-start: calc(50%);
  }
</style>
