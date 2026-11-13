<script lang="ts">
  // A small status label in the theme's semantic colors.
  let {
    tone = 'neutral',
    label,
  }: { tone?: 'success' | 'warning' | 'danger' | 'info' | 'neutral'; label: string } = $props();
</script>

<span class="status-pill tone-{tone}">
  <span class="status-dot" aria-hidden="true"></span>
  {label}
</span>

<style>
  .status-pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 2px 10px;
    border-radius: var(--radius-full);
    font-size: var(--text-xs);
    font-weight: 600;
    white-space: nowrap;
  }

  .status-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: currentColor;
  }

  .tone-success { background: var(--color-success-soft); color: var(--color-on-success-soft); }
  .tone-warning { background: var(--color-warning-soft); color: var(--color-on-warning-soft); }
  .tone-danger { background: var(--color-danger-soft); color: var(--color-on-danger-soft); }
  .tone-info { background: var(--color-info-soft); color: var(--color-on-info-soft); }
  .tone-neutral { background: var(--color-surface-container); color: var(--color-text-secondary); }
</style>
