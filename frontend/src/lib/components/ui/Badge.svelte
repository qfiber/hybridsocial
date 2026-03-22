<script lang="ts">
  let {
    count,
    variant = 'default',
    dot = false
  }: {
    count?: number;
    variant?: 'default' | 'primary' | 'success' | 'danger';
    dot?: boolean;
  } = $props();

  let displayCount = $derived(
    count !== undefined ? (count > 99 ? '99+' : String(count)) : ''
  );
</script>

{#if dot}
  <span class="badge-dot badge-{variant}" aria-hidden="true"></span>
{:else if count !== undefined && count > 0}
  <span class="badge badge-{variant}" aria-label="{count} notifications">{displayCount}</span>
{/if}

<style>
  .badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 20px;
    height: 20px;
    padding: 0 var(--space-1);
    border-radius: var(--radius-full);
    font-size: 11px;
    font-weight: 700;
    line-height: 1;
    white-space: nowrap;
  }

  .badge-dot {
    width: 8px;
    height: 8px;
    border-radius: var(--radius-full);
  }

  .badge-default {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }

  .badge-primary {
    background: var(--color-primary);
    color: var(--color-text-on-primary);
  }

  .badge-success {
    background: var(--color-success);
    color: white;
  }

  .badge-danger {
    background: var(--color-danger);
    color: white;
  }
</style>
