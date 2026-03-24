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
</script>

<div class="feed-toggle" role="tablist" aria-label="Feed type">
  <div
    class="toggle-slider"
    class:slider-right={!isLatest}
    aria-hidden="true"
  ></div>
  <button
    type="button"
    role="tab"
    class="toggle-tab"
    class:toggle-active={isLatest}
    aria-selected={isLatest}
    onclick={() => handleTabClick('latest')}
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
  >
    For You
  </button>
</div>

<style>
  .feed-toggle {
    position: relative;
    display: flex;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full);
    padding: 3px;
    max-width: 360px;
    width: 100%;
    margin: 0 auto;
  }

  .toggle-tab {
    flex: 1;
    padding: var(--space-2) var(--space-6);
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
    left: 3px;
    width: calc(50% - 3px);
    background: var(--color-primary);
    border-radius: var(--radius-full);
    transition: left 0.25s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .slider-right {
    left: calc(50%);
  }
</style>
