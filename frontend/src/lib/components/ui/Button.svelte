<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    variant = 'primary',
    size = 'md',
    disabled = false,
    loading = false,
    href = undefined,
    onclick,
    children
  }: {
    variant?: 'primary' | 'secondary' | 'outline' | 'ghost' | 'danger';
    size?: 'sm' | 'md' | 'lg';
    disabled?: boolean;
    loading?: boolean;
    href?: string | undefined;
    onclick?: (e: MouseEvent) => void;
    children?: Snippet;
  } = $props();

  let isDisabled = $derived(disabled || loading);
</script>

{#if href && !isDisabled}
  <a {href} class="btn btn-{variant} btn-{size}" class:loading>
    {#if loading}
      <span class="btn-spinner" aria-hidden="true"></span>
    {/if}
    <span class="btn-content" class:invisible={loading}>
      {#if children}{@render children()}{/if}
    </span>
  </a>
{:else}
  <button
    class="btn btn-{variant} btn-{size}"
    class:loading
    disabled={isDisabled}
    onclick={onclick}
    type="button"
  >
    {#if loading}
      <span class="btn-spinner" aria-hidden="true"></span>
    {/if}
    <span class="btn-content" class:invisible={loading}>
      {#if children}{@render children()}{/if}
    </span>
  </button>
{/if}

<style>
  .btn {
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    border: 1px solid transparent;
    border-radius: var(--radius-md);
    font-weight: 500;
    line-height: 1;
    cursor: pointer;
    transition: background var(--transition-fast), border-color var(--transition-fast),
      color var(--transition-fast), box-shadow var(--transition-fast);
    text-decoration: none;
    white-space: nowrap;
    user-select: none;
  }

  .btn:hover {
    text-decoration: none;
  }

  .btn:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  /* Sizes */
  .btn-sm {
    padding: var(--space-1) var(--space-3);
    font-size: var(--text-xs);
    height: 32px;
  }
  .btn-md {
    padding: var(--space-2) var(--space-4);
    font-size: var(--text-sm);
    height: 40px;
  }
  .btn-lg {
    padding: var(--space-3) var(--space-6);
    font-size: var(--text-base);
    height: 48px;
  }

  /* Variants */
  .btn-primary {
    background: var(--color-primary);
    color: var(--color-text-on-primary);
    border-color: var(--color-primary);
  }
  .btn-primary:hover:not(:disabled) {
    background: var(--color-primary-hover);
    border-color: var(--color-primary-hover);
  }

  .btn-secondary {
    background: var(--color-secondary);
    color: #ffffff;
    border-color: var(--color-secondary);
  }
  .btn-secondary:hover:not(:disabled) {
    background: var(--color-secondary-hover);
    border-color: var(--color-secondary-hover);
  }

  .btn-outline {
    background: transparent;
    color: var(--color-primary);
    border-color: var(--color-border);
  }
  .btn-outline:hover:not(:disabled) {
    background: var(--color-primary-soft);
    border-color: var(--color-primary);
  }

  .btn-ghost {
    background: transparent;
    color: var(--color-text-secondary);
    border-color: transparent;
  }
  .btn-ghost:hover:not(:disabled) {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .btn-danger {
    background: var(--color-danger);
    color: #ffffff;
    border-color: var(--color-danger);
  }
  .btn-danger:hover:not(:disabled) {
    background: #dc2626;
    border-color: #dc2626;
  }

  /* Loading */
  .btn-spinner {
    position: absolute;
    inset-inline-start: 50%;
    top: 50%;
    transform: translate(-50%, -50%);
    width: 16px;
    height: 16px;
    border: 2px solid currentColor;
    border-inline-end-color: transparent;
    border-radius: var(--radius-full);
    animation: spin 0.6s linear infinite;
  }

  .btn-content.invisible {
    visibility: hidden;
  }

  @keyframes spin {
    to {
      transform: translate(-50%, -50%) rotate(360deg);
    }
  }
</style>
