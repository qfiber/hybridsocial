<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    align = 'end',
    trigger,
    children
  }: {
    align?: 'start' | 'end';
    trigger: Snippet;
    children?: Snippet;
  } = $props();

  let open = $state(false);
  let containerEl: HTMLDivElement | undefined = $state();

  function toggle() {
    open = !open;
  }

  function handleClickOutside(e: MouseEvent) {
    if (containerEl && !containerEl.contains(e.target as Node)) {
      open = false;
    }
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      open = false;
    }
  }

  $effect(() => {
    if (open) {
      document.addEventListener('click', handleClickOutside, true);
      document.addEventListener('keydown', handleKeydown);
      return () => {
        document.removeEventListener('click', handleClickOutside, true);
        document.removeEventListener('keydown', handleKeydown);
      };
    }
  });
</script>

<div class="dropdown" bind:this={containerEl}>
  <button class="dropdown-trigger" onclick={toggle} aria-expanded={open} aria-haspopup="true" type="button">
    {@render trigger()}
  </button>

  {#if open}
    <div class="dropdown-menu dropdown-align-{align}" role="menu">
      {#if children}{@render children()}{/if}
    </div>
  {/if}
</div>

<style>
  .dropdown {
    position: relative;
    display: inline-flex;
  }

  .dropdown-trigger {
    display: inline-flex;
    align-items: center;
    background: none;
    border: none;
    padding: 0;
    cursor: pointer;
    color: inherit;
  }

  .dropdown-menu {
    position: absolute;
    top: 100%;
    z-index: var(--z-dropdown);
    margin-block-start: var(--space-1);
    min-width: 180px;
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-lg);
    padding: var(--space-1);
    animation: dropdown-in 150ms ease;
  }

  .dropdown-align-end {
    inset-inline-end: 0;
  }

  .dropdown-align-start {
    inset-inline-start: 0;
  }

  @keyframes dropdown-in {
    from {
      opacity: 0;
      transform: translateY(-4px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .dropdown-menu :global(a),
  .dropdown-menu :global(button) {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    width: 100%;
    padding: var(--space-2) var(--space-3);
    border: none;
    background: none;
    border-radius: var(--radius-sm);
    font-size: var(--text-sm);
    color: var(--color-text);
    cursor: pointer;
    text-decoration: none;
    white-space: nowrap;
    text-align: start;
  }

  .dropdown-menu :global(a:hover),
  .dropdown-menu :global(button:hover) {
    background: var(--color-surface);
    text-decoration: none;
  }

  .dropdown-menu :global(.dropdown-divider) {
    height: 1px;
    background: var(--color-border);
    margin: var(--space-1) 0;
  }

  .dropdown-menu :global(.dropdown-item-danger) {
    color: var(--color-danger);
  }
</style>
