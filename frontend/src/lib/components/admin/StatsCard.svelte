<script lang="ts">
  let {
    label,
    value,
    icon = '',
    trend = undefined,
    href = undefined,
    alert = false,
    alertLabel = 'Needs attention',
  }: {
    label: string;
    value: string | number;
    icon?: string;
    trend?: { direction: 'up' | 'down'; value: string } | undefined;
    href?: string | undefined;
    /** Show a blinking red indicator in the top-right (e.g. open reports). */
    alert?: boolean;
    alertLabel?: string;
  } = $props();
</script>

{#snippet body()}
  {#if alert}
    <span class="stats-alert" role="img" aria-label={alertLabel}>
      <span class="stats-alert-pulse" aria-hidden="true"></span>
      <span class="stats-alert-dot" aria-hidden="true"></span>
    </span>
  {/if}
  <div class="stats-header">
    {#if icon}
      <span class="stats-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d={icon} />
        </svg>
      </span>
    {/if}
    <span class="stats-label">{label}</span>
  </div>
  <div class="stats-value">{value}</div>
  {#if trend}
    <div class="stats-trend trend-{trend.direction}">
      {trend.direction === 'up' ? '+' : '-'}{trend.value}
    </div>
  {/if}
{/snippet}

{#if href}
  <a {href} class="stats-card card card-hover" class:stats-card-alert={alert}>
    {@render body()}
  </a>
{:else}
  <div class="stats-card card" class:stats-card-alert={alert}>
    {@render body()}
  </div>
{/if}

<style>
  .stats-card {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    text-decoration: none;
    color: inherit;
    position: relative;
  }

  .stats-alert {
    position: absolute;
    inset-block-start: 12px;
    inset-inline-end: 12px;
    width: 12px;
    height: 12px;
  }

  .stats-alert-dot {
    position: absolute;
    inset: 0;
    background: var(--color-danger);
    border-radius: 50%;
  }

  /* The pulse halo lives behind the dot and animates outward; using a
     second element rather than ::before keeps it independent of the
     parent's `position: relative`/`overflow` constraints. */
  .stats-alert-pulse {
    position: absolute;
    inset: 0;
    background: var(--color-danger);
    border-radius: 50%;
    opacity: 0.6;
    animation: stats-alert-pulse 1.4s ease-out infinite;
  }

  @keyframes stats-alert-pulse {
    0% { transform: scale(1); opacity: 0.6; }
    70% { transform: scale(2.2); opacity: 0; }
    100% { transform: scale(2.2); opacity: 0; }
  }

  @media (prefers-reduced-motion: reduce) {
    .stats-alert-pulse { animation: none; }
  }

  .stats-card:hover {
    text-decoration: none;
  }

  .stats-header {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .stats-icon {
    display: flex;
    color: var(--color-primary);
  }

  .stats-label {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    font-weight: 500;
  }

  .stats-value {
    font-size: var(--text-3xl);
    font-weight: 700;
    color: var(--color-text);
    line-height: 1.2;
  }

  .stats-trend {
    font-size: var(--text-xs);
    font-weight: 600;
  }

  .trend-up {
    color: var(--color-success);
  }

  .trend-down {
    color: var(--color-danger);
  }
</style>
