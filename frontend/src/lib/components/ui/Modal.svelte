<script lang="ts">
  import type { Snippet } from 'svelte';
  import { fly, fade } from 'svelte/transition';
  import { lockScroll } from '$lib/utils/scroll-lock.js';

  let {
    open = $bindable(false),
    title = '',
    onclose,
    children,
    // `sm` (480px) is the historical default. `lg` (900px) is for
    // management UIs that fit a sidebar + content layout — anything
    // wider than that and the dialog stops feeling like a dialog and
    // starts feeling like a page, so we cap there. `full` lets a
    // caller stretch to the viewport when needed.
    size = 'sm',
  }: {
    open?: boolean;
    title?: string;
    onclose?: () => void;
    children?: Snippet;
    size?: 'sm' | 'md' | 'lg' | 'full';
  } = $props();

  let dialogEl: HTMLDivElement | undefined = $state();
  let previouslyFocused: HTMLElement | null = null;

  function close() {
    open = false;
    onclose?.();
    previouslyFocused?.focus();
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault();
      close();
    }
    if (e.key === 'Tab' && dialogEl) {
      const focusable = dialogEl.querySelectorAll<HTMLElement>(
        'a[href], button:not([disabled]), textarea, input, select, [tabindex]:not([tabindex="-1"])'
      );
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    }
  }

  function handleBackdropClick(e: MouseEvent) {
    if (e.target === e.currentTarget) {
      close();
    }
  }

  // Hold the page still behind the dialog (touch scrolls otherwise leak
  // through the backdrop to the feed).
  $effect(() => {
    if (open) return lockScroll();
  });

  $effect(() => {
    if (open) {
      previouslyFocused = document.activeElement as HTMLElement;
      requestAnimationFrame(() => {
        const focusable = dialogEl?.querySelector<HTMLElement>(
          'a[href], button:not([disabled]), textarea, input, select, [tabindex]:not([tabindex="-1"])'
        );
        focusable?.focus();
      });
    }
  });
</script>

{#if open}
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <div
    class="modal-backdrop"
    role="dialog"
    aria-modal="true"
    aria-label={title}
    transition:fade={{ duration: 150 }}
    onkeydown={handleKeydown}
    onclick={handleBackdropClick}
  >
    <div
      class="modal modal-{size}"
      bind:this={dialogEl}
      transition:fly={{ y: 20, duration: 200 }}
    >
      <div class="modal-header">
        <h2 class="modal-title">{title}</h2>
        <button class="modal-close" onclick={close} aria-label="Close dialog" type="button">
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2">
            <line x1="4" y1="4" x2="16" y2="16" />
            <line x1="16" y1="4" x2="4" y2="16" />
          </svg>
        </button>
      </div>
      <div class="modal-body">
        {#if children}{@render children()}{/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .modal-backdrop {
    position: fixed;
    inset: 0;
    z-index: var(--z-modal-backdrop);
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--color-overlay);
    padding: var(--space-4);
  }

  .modal {
    z-index: var(--z-modal);
    background: var(--color-surface-raised);
    border-radius: var(--radius-xl);
    box-shadow: var(--shadow-xl);
    width: 100%;
    /* dvh: on phones `vh` measures the viewport with the browser chrome
       hidden, so with the address bar showing the dialog ran past the
       visible area and hid its bottom (often the action buttons). `vh` stays
       as the fallback for browsers without dynamic viewport units. */
    max-height: 85vh;
    max-height: 85dvh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .modal-sm { max-width: 480px; }
  .modal-md { max-width: 640px; }
  .modal-lg { max-width: 900px; }
  .modal-full { max-width: min(1100px, 96vw); max-height: 92vh; max-height: 92dvh; }

  .modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-4) var(--space-6);
    border-block-end: 1px solid var(--color-border);
  }

  .modal-title {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--color-text);
  }

  .modal-close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    border: none;
    background: none;
    border-radius: var(--radius-sm);
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: background var(--transition-fast);
  }

  .modal-close:hover {
    background: var(--color-surface);
  }

  .modal-body {
    padding: var(--space-6);
    overflow-y: auto;
    /* Reaching the end of a long dialog shouldn't hand the swipe on to
       whatever is behind it. */
    overscroll-behavior: contain;
  }
</style>
