<script lang="ts">
  // Sticky Discard / Save bar, shown while a settings form has unsaved
  // changes. One save model for every settings page.
  import { fly } from 'svelte/transition';
  import { t } from '$lib/stores/i18n.js';

  let {
    dirty,
    saving = false,
    onsave,
    ondiscard,
  }: {
    dirty: boolean;
    saving?: boolean;
    onsave: () => void;
    ondiscard: () => void;
  } = $props();

  // Warn before leaving the page with unsaved changes.
  function onBeforeUnload(e: BeforeUnloadEvent) {
    if (dirty) e.preventDefault();
  }
</script>

<svelte:window onbeforeunload={onBeforeUnload} />

{#if dirty || saving}
  <div class="save-bar" role="region" aria-label={$t('admin_shell.unsaved_changes')} transition:fly={{ y: 16, duration: 150 }}>
    <span class="save-bar-text">{$t('admin_shell.unsaved_changes')}</span>
    <div class="save-bar-actions">
      <button type="button" class="btn btn-ghost" onclick={ondiscard} disabled={saving}>
        {$t('admin_shell.discard')}
      </button>
      <button type="button" class="btn btn-primary" onclick={onsave} disabled={saving}>
        {saving ? $t('admin_shell.saving') : $t('admin_shell.save')}
      </button>
    </div>
  </div>
{/if}

<style>
  .save-bar {
    position: sticky;
    bottom: var(--space-4);
    z-index: var(--z-sticky);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    flex-wrap: wrap;
    padding: var(--space-3) var(--space-4);
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    box-shadow: var(--shadow-lg);
  }

  .save-bar-text {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .save-bar-actions {
    display: flex;
    gap: var(--space-2);
  }

  @media (prefers-reduced-motion: reduce) {
    .save-bar {
      transition: none;
    }
  }
</style>
