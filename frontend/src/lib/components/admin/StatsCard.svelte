<script lang="ts">
  let {
    label,
    value,
    icon = '',
    trend = undefined,
    href = undefined
  }: {
    label: string;
    value: string | number;
    icon?: string;
    trend?: { direction: 'up' | 'down'; value: string } | undefined;
    href?: string | undefined;
  } = $props();
</script>

{#if href}
  <a {href} class="stats-card card card-hover">
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
  </a>
{:else}
  <div class="stats-card card">
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
  </div>
{/if}

<style>
  .stats-card {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    text-decoration: none;
    color: inherit;
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
