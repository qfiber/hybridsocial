<script lang="ts">
  import { t } from '$lib/stores/i18n.js';
  import { instanceName } from '$lib/stores/instance.js';
</script>

<svelte:head>
  <title>Messages - {$instanceName}</title>
</svelte:head>

<div class="no-selection">
  <svg
    width="48"
    height="48"
    viewBox="0 0 24 24"
    fill="none"
    stroke="var(--color-text-tertiary)"
    stroke-width="1.5"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
  >
    <path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z" />
  </svg>
  <p class="no-selection-text">{$t('dm.select_conversation')}</p>
  <p class="no-selection-hint">{$t('dm.select_conversation_hint')}</p>
</div>

<style>
  .no-selection {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--space-3);
    padding: var(--space-8);
  }

  .no-selection-text {
    font-size: var(--text-base);
    font-weight: 600;
    color: var(--color-text-secondary);
  }

  .no-selection-hint {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }
</style>
