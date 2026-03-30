<script lang="ts">
  import { fly } from 'svelte/transition';
  import { toasts, removeToast } from '$lib/stores/toast.js';

  let toastList: import('$lib/stores/toast').Toast[] = $state([]);

  toasts.subscribe((v) => {
    toastList = v;
  });
</script>

{#if toastList.length > 0}
  <div class="toast-container" aria-live="polite">
    {#each toastList as toast (toast.id)}
      <div
        class="toast toast-{toast.type}"
        role="status"
        transition:fly={{ x: 300, duration: 300 }}
      >
        <span class="toast-icon" aria-hidden="true">
          {#if toast.type === 'success'}
            <svg width="18" height="18" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
            </svg>
          {:else if toast.type === 'error'}
            <svg width="18" height="18" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
            </svg>
          {:else if toast.type === 'warning'}
            <svg width="18" height="18" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
            </svg>
          {:else}
            <svg width="18" height="18" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
            </svg>
          {/if}
        </span>
        <div class="toast-text">
          <span class="toast-message">{toast.message}</span>
          {#if toast.description}
            <span class="toast-description">{toast.description}</span>
          {/if}
        </div>
        <button class="toast-close" onclick={() => removeToast(toast.id)} aria-label="Dismiss" type="button">
          <svg width="14" height="14" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.5">
            <line x1="4" y1="4" x2="16" y2="16" />
            <line x1="16" y1="4" x2="4" y2="16" />
          </svg>
        </button>
      </div>
    {/each}
  </div>
{/if}

<style>
  .toast-container {
    position: fixed;
    top: var(--space-4);
    inset-inline-end: var(--space-4);
    z-index: var(--z-toast);
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    max-width: 400px;
    width: 100%;
    pointer-events: none;
  }

  .toast {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-lg);
    font-size: var(--text-sm);
    pointer-events: auto;
    border: 1px solid transparent;
  }

  .toast-success {
    background: var(--color-success-soft);
    color: #166534;
    border-color: #bbf7d0;
  }

  .toast-error {
    background: var(--color-danger-soft);
    color: #991b1b;
    border-color: #fecaca;
  }

  .toast-info {
    background: var(--color-info-soft);
    color: #1e40af;
    border-color: #bfdbfe;
  }

  .toast-warning {
    background: #fef3c7;
    color: #92400e;
    border-color: #fde68a;
  }

  .toast-icon {
    display: flex;
    flex-shrink: 0;
  }

  .toast-text {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .toast-message {
    line-height: 1.4;
  }

  .toast-description {
    font-size: 0.75rem;
    opacity: 0.75;
    line-height: 1.3;
  }

  .toast-close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    border: none;
    background: none;
    border-radius: var(--radius-xs);
    color: currentColor;
    opacity: 0.6;
    cursor: pointer;
    flex-shrink: 0;
    transition: opacity var(--transition-fast);
  }

  .toast-close:hover {
    opacity: 1;
  }
</style>
