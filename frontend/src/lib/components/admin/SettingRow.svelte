<script lang="ts">
  // One setting: label + help on the start side, the control on the end side.
  // `layout="stacked"` puts wide controls (text fields, textareas) under the
  // label instead. Pass `labelFor` so the label targets the control.
  import type { Snippet } from 'svelte';

  let {
    label,
    help = '',
    labelFor = undefined,
    layout = 'inline',
    children,
  }: {
    label: string;
    help?: string;
    labelFor?: string;
    layout?: 'inline' | 'stacked';
    children: Snippet;
  } = $props();
</script>

<div class="setting-row" class:stacked={layout === 'stacked'}>
  <div class="setting-row-text">
    {#if labelFor}
      <label class="setting-row-label" for={labelFor}>{label}</label>
    {:else}
      <span class="setting-row-label">{label}</span>
    {/if}
    {#if help}
      <p class="setting-row-help">{help}</p>
    {/if}
  </div>
  <div class="setting-row-control">
    {@render children()}
  </div>
</div>

<style>
  .setting-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-4);
    padding: var(--space-4) var(--space-5);
  }

  .setting-row.stacked {
    flex-direction: column;
    align-items: stretch;
    gap: var(--space-2);
  }

  .setting-row-text {
    min-width: 0;
    flex: 1;
  }

  .setting-row-label {
    display: block;
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .setting-row-help {
    margin: 2px 0 0;
    font-size: var(--text-xs);
    line-height: 1.45;
    color: var(--color-text-tertiary);
  }

  .setting-row-control {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .setting-row.stacked .setting-row-control {
    flex-shrink: 1;
  }

  .setting-row.stacked .setting-row-control > :global(*) {
    flex: 1;
    min-width: 0;
  }

  @media (max-width: 560px) {
    .setting-row {
      flex-direction: column;
      align-items: stretch;
      gap: var(--space-2);
    }
  }
</style>
