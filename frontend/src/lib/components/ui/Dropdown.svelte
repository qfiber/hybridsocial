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
  let menuEl: HTMLDivElement | undefined = $state();
  let menuStyle = $state('');

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

  // Position the menu with viewport clamping. The menu is anchored to the
  // trigger's physical side (so `align="end"` right-aligns it to the trigger),
  // then clamped into the viewport so a trigger near a screen edge can't push
  // the menu off-screen. This is what used to happen to the profile ⋯ menu on
  // mobile: an RTL document flipped `inset-inline-end` to the left, so the menu
  // grew rightward off the screen. `position: fixed` + clamp is direction- and
  // edge-agnostic.
  function positionMenu() {
    if (!containerEl || !menuEl) return;
    const pad = 8;
    const gap = 4;
    const trig = containerEl.getBoundingClientRect();
    const mw = menuEl.offsetWidth;
    const mh = menuEl.offsetHeight;
    const vw = window.innerWidth;
    const vh = window.innerHeight;

    // Below the trigger by default; flip above when it would overflow the
    // bottom (e.g. a menu opened near the bottom nav on mobile).
    let top = trig.bottom + gap;
    if (top + mh > vh - pad) {
      top = Math.max(pad, trig.top - gap - mh);
    }

    // `end` right-aligns the menu to the trigger; `start` left-aligns it.
    let left = align === 'end' ? trig.right - mw : trig.left;
    left = Math.min(Math.max(pad, left), Math.max(pad, vw - mw - pad));

    menuStyle = `position: fixed; inset: auto; top: ${Math.round(top)}px; left: ${Math.round(left)}px; margin: 0;`;
  }

  $effect(() => {
    if (!open) {
      menuStyle = '';
      return;
    }
    // Measure + place before paint so the menu never flashes at the wrong
    // spot, then keep it pinned while scrolling/resizing.
    positionMenu();
    document.addEventListener('click', handleClickOutside, true);
    document.addEventListener('keydown', handleKeydown);
    window.addEventListener('scroll', positionMenu, true);
    window.addEventListener('resize', positionMenu);
    return () => {
      document.removeEventListener('click', handleClickOutside, true);
      document.removeEventListener('keydown', handleKeydown);
      window.removeEventListener('scroll', positionMenu, true);
      window.removeEventListener('resize', positionMenu);
    };
  });
</script>

<div class="dropdown" bind:this={containerEl}>
  <button class="dropdown-trigger" onclick={toggle} aria-expanded={open} aria-haspopup="true" type="button">
    {@render trigger()}
  </button>

  {#if open}
    <!-- Close on any click bubbling up from a menu item. Without this
         the dropdown stays open while SvelteKit handles the SPA
         navigation (there's no unmount until the new route mounts),
         which is what made the user-menu look frozen. -->
    <div
      class="dropdown-menu dropdown-align-{align}"
      role="menu"
      bind:this={menuEl}
      style={menuStyle}
      onclick={() => (open = false)}
    >
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
