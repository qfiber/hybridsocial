<script lang="ts">
  import Sparkline from './Sparkline.svelte';
  import { api } from '$lib/api/client.js';

  type SeriesPoint = { t: string; v: number };
  type SummaryRow = {
    service: string;
    metric: string;
    latest: { t: string; v: number };
    sparkline: SeriesPoint[];
  };

  type ServiceHealth = {
    status?: string;
    version?: string;
    uptime_seconds?: number;
    error?: string;
    cluster_health?: string;
    backend?: string;
  };

  let {
    title,
    icon,
    service,
    metrics,
    rows,
    health,
    noChart = false,
  }: {
    title: string;
    icon: string;
    service: string;
    /** Display rows: which metric keys to show, in what order, and how to format. */
    metrics: { key: string; label: string; format: (v: number) => string }[];
    rows: SummaryRow[];
    health?: ServiceHealth | null;
    /** true: render metrics as static value rows — no sparkline, no
     *  click-to-expand chart. For services whose values change on the
     *  order of days/weeks (e.g. OpenSearch), a time-series is noise. */
    noChart?: boolean;
  } = $props();

  function formatUptime(seconds: number | undefined): string {
    if (!seconds) return '';
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    if (days > 0) return `${days}d ${hours}h`;
    if (hours > 0) return `${hours}h ${mins}m`;
    return `${mins}m`;
  }

  let byMetric = $derived.by(() => {
    const m: Record<string, SummaryRow> = {};
    for (const r of rows) {
      if (r.service === service) m[r.metric] = r;
    }
    return m;
  });

  // Show "no data yet" if the collector hasn't run, or if every metric
  // for this service is missing. Probes that intentionally skip (e.g.
  // OpenSearch on a Postgres-search instance) hit this path.
  let hasAnyData = $derived(metrics.some((m) => byMetric[m.key]));

  // Headline status, derived from the live dashboard probe + presence
  // of collector samples. The dashboard probe is authoritative for
  // up/down — the collector lags it by up to one tick — so a freshly
  // dead service stays correct without waiting for the next sweep.
  type StatusKind = 'operational' | 'degraded' | 'offline' | 'not_configured' | 'no_data';
  let statusKind = $derived.by<StatusKind>(() => {
    const s = health?.status;
    if (s === 'not_configured') return 'not_configured';
    if (s === 'down') return 'offline';
    if (s === 'degraded') return 'degraded';
    if (hasAnyData) return 'operational';
    return 'no_data';
  });

  let statusLabel = $derived(
    {
      operational: 'operational',
      degraded: 'degraded',
      offline: 'offline',
      not_configured: 'not configured',
      no_data: 'collecting',
    }[statusKind],
  );

  let expanded = $state<{ key: string; label: string; format: (v: number) => string } | null>(
    null,
  );
  let expandedSeries = $state<SeriesPoint[] | null>(null);
  let expandedWindow = $state<'1h' | '6h' | '24h' | '7d' | '30d'>('1h');
  let expandedLoading = $state(false);

  // Axis scaffolding for the expanded chart: the value range (Y) and the
  // time span (X) so the curve is actually readable. Without these the
  // modal was just a bare line with no idea of scale or when.
  let chartStats = $derived.by(() => {
    const s = expandedSeries;
    if (!s || s.length === 0 || !expanded) return null;
    let min = Infinity;
    let max = -Infinity;
    for (const p of s) {
      if (p.v < min) min = p.v;
      if (p.v > max) max = p.v;
    }
    const fmt = expanded.format;
    const first = s[0]?.t;
    const last = s[s.length - 1]?.t;
    return {
      maxLabel: fmt(max),
      midLabel: fmt((min + max) / 2),
      minLabel: fmt(min),
      latestLabel: fmt(s[s.length - 1]?.v ?? 0),
      startLabel: fmtAxisTime(first, expandedWindow),
      endLabel: fmtAxisTime(last, expandedWindow),
      flat: max === min,
    };
  });

  function fmtAxisTime(iso: string | undefined, window: string): string {
    if (!iso) return '';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    // Longer windows read by day; short windows by clock time.
    if (window === '7d' || window === '30d') {
      return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
    }
    return d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
  }

  async function loadExpandedSeries() {
    if (!expanded) return;
    expandedLoading = true;
    try {
      const res = await api.get<{ samples: SeriesPoint[] }>('/api/v1/admin/metrics/series', {
        service,
        metric: expanded.key,
        window: expandedWindow,
      });
      expandedSeries = res.samples;
    } catch {
      expandedSeries = [];
    } finally {
      expandedLoading = false;
    }
  }

  function openExpanded(key: string, label: string, format: (v: number) => string) {
    if (noChart) return;
    expanded = { key, label, format };
    expandedSeries = null;
    expandedWindow = '1h';
    loadExpandedSeries();
  }

  function closeExpanded() {
    expanded = null;
    expandedSeries = null;
  }

  function changeWindow(w: typeof expandedWindow) {
    expandedWindow = w;
    loadExpandedSeries();
  }
</script>

<section class="service-panel">
  <header class="service-panel-header">
    <span class="material-symbols-outlined service-panel-icon" aria-hidden="true">{icon}</span>
    <h3 class="service-panel-title">{title}</h3>
    <span
      class="service-panel-status"
      class:status-up={statusKind === 'operational'}
      class:status-degraded={statusKind === 'degraded'}
      class:status-down={statusKind === 'offline'}
      class:status-stale={statusKind === 'no_data' || statusKind === 'not_configured'}
    >
      {statusLabel}
    </span>
  </header>
  {#if health?.version || health?.uptime_seconds}
    <div class="service-panel-meta">
      {#if health.version}<span class="service-panel-version">v{health.version}</span>{/if}
      {#if health.uptime_seconds}<span class="service-panel-uptime">up {formatUptime(health.uptime_seconds)}</span>{/if}
    </div>
  {/if}
  {#if health?.error && statusKind !== 'operational'}
    <div class="service-panel-error">{health.error}</div>
  {/if}
  {#if statusKind === 'not_configured'}
    <p class="service-panel-note">
      Not running on this instance. Search currently uses PostgreSQL.
    </p>
  {/if}
  <div class="service-panel-rows">
    {#each metrics as m (m.key)}
      {@const row = byMetric[m.key]}
      {#if noChart}
        <div class="service-panel-row service-panel-row-static">
          <span class="row-label">{m.label}</span>
          <span class="row-value">{row ? m.format(row.latest.v) : '—'}</span>
        </div>
      {:else}
        <button
          type="button"
          class="service-panel-row"
          onclick={() => openExpanded(m.key, m.label, m.format)}
          disabled={!row}
        >
          <span class="row-label">{m.label}</span>
          <span class="row-value">{row ? m.format(row.latest.v) : '—'}</span>
          <span class="row-spark">
            {#if row && row.sparkline && row.sparkline.length > 1}
              <Sparkline points={row.sparkline} width={100} height={24} />
            {/if}
          </span>
        </button>
      {/if}
    {/each}
  </div>
</section>

{#if expanded}
  <div class="metric-modal-overlay" role="dialog" aria-modal="true" onclick={closeExpanded}>
    <div class="metric-modal" onclick={(e) => e.stopPropagation()}>
      <header class="metric-modal-header">
        <h3 class="metric-modal-title">{title} · {expanded.label}</h3>
        <button class="metric-modal-close" onclick={closeExpanded} aria-label="Close">
          <span class="material-symbols-outlined">close</span>
        </button>
      </header>
      <nav class="metric-modal-windows" aria-label="Time window">
        {#each ['1h', '6h', '24h', '7d', '30d'] as const as w (w)}
          <button
            type="button"
            class="window-btn"
            class:window-btn-active={expandedWindow === w}
            onclick={() => changeWindow(w)}
          >
            {w}
          </button>
        {/each}
      </nav>
      <div class="metric-modal-chart">
        {#if expandedLoading}
          <p class="metric-modal-loading">Loading…</p>
        {:else if !expandedSeries || expandedSeries.length === 0}
          <p class="metric-modal-empty">No data for this window yet.</p>
        {:else if chartStats}
          <div class="metric-chart">
            {#if chartStats.latestLabel}
              <p class="metric-chart-latest">
                <span class="metric-chart-latest-value">{chartStats.latestLabel}</span>
                <span class="metric-chart-latest-caption">current</span>
              </p>
            {/if}
            <div class="metric-chart-plot">
              <div class="metric-chart-yaxis" aria-hidden="true">
                <span>{chartStats.maxLabel}</span>
                <span>{chartStats.midLabel}</span>
                <span>{chartStats.minLabel}</span>
              </div>
              <div class="metric-chart-canvas">
                <div class="metric-chart-grid" aria-hidden="true">
                  <span></span><span></span><span></span>
                </div>
                <Sparkline points={expandedSeries} width={620} height={200} padded={false} />
              </div>
            </div>
            <div class="metric-chart-xaxis" aria-hidden="true">
              <span class="metric-chart-xaxis-spacer"></span>
              <span class="metric-chart-xaxis-times">
                <span>{chartStats.startLabel}</span>
                <span>{chartStats.endLabel}</span>
              </span>
            </div>
          </div>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .service-panel {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl, 16px);
    padding: 16px 18px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .service-panel-header {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .service-panel-icon {
    font-size: 22px;
    color: var(--color-primary);
  }

  .service-panel-title {
    margin: 0;
    font-size: 1rem;
    font-weight: 700;
    flex: 1;
    color: var(--color-text);
  }

  .service-panel-status {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    font-weight: 700;
    padding: 2px 8px;
    border-radius: 9999px;
  }

  .status-up {
    background: var(--color-success-soft);
    color: var(--color-success);
  }

  .status-degraded {
    background: var(--color-warning-soft);
    color: var(--color-on-warning-soft);
  }

  .status-down {
    background: var(--color-danger-soft);
    color: var(--color-danger);
  }

  .status-stale {
    background: var(--color-surface-container-high);
    color: var(--color-text-tertiary);
  }

  .service-panel-meta {
    display: flex;
    gap: 10px;
    font-size: 0.75rem;
    color: var(--color-text-tertiary);
    margin-block-start: -4px;
  }

  .service-panel-version,
  .service-panel-uptime {
    font-variant-numeric: tabular-nums;
  }

  .service-panel-error {
    font-size: 0.75rem;
    color: var(--color-danger);
    background: var(--color-danger-soft);
    padding: 6px 10px;
    border-radius: 8px;
  }

  .service-panel-note {
    font-size: 0.8125rem;
    color: var(--color-text-secondary);
    margin: 0;
    line-height: 1.4;
  }

  .service-panel-rows {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .service-panel-row {
    display: grid;
    /* Sparkline column collapses to 0 when there's no time-series (e.g.
       OpenSearch snapshot metrics), so the value gets the full width
       instead of being crowded by an empty/placeholder chart. */
    grid-template-columns: 1fr auto minmax(0, 100px);
    align-items: center;
    gap: 12px;
    padding: 8px 10px;
    background: transparent;
    border: 1px solid transparent;
    border-radius: 10px;
    cursor: pointer;
    color: inherit;
    text-align: start;
    font: inherit;
  }

  .service-panel-row:hover:not(:disabled) {
    background: var(--color-surface-hover);
    border-color: var(--color-border);
  }

  .service-panel-row:disabled {
    cursor: default;
    opacity: 0.5;
  }

  /* Static (no-chart) rows: just label + value, no sparkline column,
     no pointer affordance — the value is the whole story. */
  .service-panel-row-static {
    grid-template-columns: 1fr auto;
    cursor: default;
  }

  .row-label {
    font-size: 0.8125rem;
    color: var(--color-text-secondary);
  }

  .row-value {
    font-size: 0.95rem;
    font-weight: 700;
    color: var(--color-text);
    font-variant-numeric: tabular-nums;
  }

  .row-spark {
    display: inline-flex;
    align-items: center;
  }

  .metric-modal-overlay {
    position: fixed;
    inset: 0;
    background: var(--scrim-medium);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1100;
    padding: 16px;
  }

  .metric-modal {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl, 16px);
    padding: 20px;
    max-width: 760px;
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .metric-modal-header {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .metric-modal-title {
    margin: 0;
    font-size: 1.05rem;
    font-weight: 700;
    flex: 1;
  }

  .metric-modal-close {
    background: transparent;
    border: none;
    color: var(--color-text-secondary);
    cursor: pointer;
    border-radius: 9999px;
    width: 32px;
    height: 32px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  .metric-modal-close:hover {
    background: var(--color-surface-hover);
    color: var(--color-text);
  }

  .metric-modal-windows {
    display: flex;
    gap: 6px;
  }

  .window-btn {
    background: transparent;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    padding: 4px 12px;
    font-size: 0.8125rem;
    cursor: pointer;
    color: var(--color-text-secondary);
    font: inherit;
  }

  .window-btn-active {
    background: var(--color-primary);
    border-color: var(--color-primary);
    color: white;
  }

  .metric-modal-chart {
    min-height: 240px;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .metric-modal-loading,
  .metric-modal-empty {
    color: var(--color-text-tertiary);
    font-size: 0.875rem;
  }

  .metric-chart {
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .metric-chart-latest {
    margin: 0;
    display: flex;
    align-items: baseline;
    gap: 8px;
  }

  .metric-chart-latest-value {
    font-size: 1.5rem;
    font-weight: 800;
    color: var(--color-text);
    font-variant-numeric: tabular-nums;
  }

  .metric-chart-latest-caption {
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--color-text-tertiary);
  }

  .metric-chart-plot {
    display: grid;
    grid-template-columns: 52px 1fr;
    gap: 10px;
  }

  .metric-chart-yaxis {
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    text-align: end;
    height: 200px;
    font-size: 0.7rem;
    color: var(--color-text-tertiary);
    font-variant-numeric: tabular-nums;
    /* Nudge labels so they sit on the gridline rather than below it. */
    transform: translateY(-0.5em);
  }

  .metric-chart-canvas {
    position: relative;
    height: 200px;
  }

  .metric-chart-grid {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    pointer-events: none;
  }

  .metric-chart-grid span {
    display: block;
    height: 0;
    border-top: 1px dashed var(--color-border);
  }

  .metric-chart-canvas :global(svg.sparkline) {
    position: relative;
    display: block;
    width: 100%;
    height: 100%;
  }

  .metric-chart-xaxis {
    display: grid;
    grid-template-columns: 52px 1fr;
    gap: 10px;
  }

  .metric-chart-xaxis-times {
    display: flex;
    justify-content: space-between;
    font-size: 0.7rem;
    color: var(--color-text-tertiary);
    font-variant-numeric: tabular-nums;
  }
</style>
