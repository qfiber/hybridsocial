<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface ChartPoint { date: string; count: number; }
  interface Summary { total_users: number; total_posts: number; federated_posts: number; total_reactions: number; posts_today: number; registrations_today: number; storage: { media_count: number; total_bytes: number }; federation: { remote_actors: number; remote_identities: number }; }
  interface QueueStats { nats: { connected: boolean }; tasks: { active: number }; workers: { name: string; alive: boolean }[]; system: { uptime_seconds: number; memory_total_mb: number; process_count: number; scheduler_count: number }; }

  let summary = $state<Summary | null>(null);
  let userGrowth = $state<ChartPoint[]>([]);
  let postVolume = $state<ChartPoint[]>([]);
  let federatedVolume = $state<ChartPoint[]>([]);
  let activeUsers = $state<ChartPoint[]>([]);
  // Distinct accounts across the whole window, computed server-side.
  // Summing the daily buckets would count a user once per active day.
  let activeUsersTotal = $state(0);
  let queueStats = $state<QueueStats | null>(null);
  let loading = $state(true);
  let days = $state(30);

  // Tooltip state — one shared instance positioned next to whichever
  // bar is being hovered, so bar width can stay tight without losing
  // access to the value behind it.
  let tooltip = $state<{ x: number; y: number; label: string; value: number } | null>(null);

  async function loadData() {
    loading = true;
    try {
      const [s, ug, pv, fv, au, qs] = await Promise.all([
        api.get<Summary>('/api/v1/admin/analytics/summary'),
        api.get<{ data: ChartPoint[] }>(`/api/v1/admin/analytics/user_growth?days=${days}`),
        api.get<{ data: ChartPoint[] }>(`/api/v1/admin/analytics/post_volume?days=${days}`),
        api.get<{ data: ChartPoint[] }>(`/api/v1/admin/analytics/federated_post_volume?days=${days}`),
        api.get<{ data: ChartPoint[]; total: number }>(`/api/v1/admin/analytics/active_users?days=${days}`),
        api.get<QueueStats>('/api/v1/admin/queue_stats'),
      ]);
      summary = s;
      userGrowth = ug.data || [];
      postVolume = pv.data || [];
      federatedVolume = fv.data || [];
      activeUsers = au.data || [];
      activeUsersTotal = au.total ?? 0;
      queueStats = qs;
    } catch { /* */ }
    finally { loading = false; }
  }

  onMount(loadData);

  function maxVal(data: ChartPoint[]): number {
    return Math.max(1, ...data.map(d => d.count));
  }

  function total(data: ChartPoint[]): number {
    return data.reduce((acc, d) => acc + d.count, 0);
  }

  function formatShortDate(iso: string): string {
    // ChartPoint.date comes back as "YYYY-MM-DD"; render as "Apr 3"
    // without timezone drift — parsing as local would bump entries
    // near midnight into the wrong day.
    const [y, m, d] = iso.split('-').map(Number);
    return new Date(y, m - 1, d).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  }

  function formatBytes(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)} MB`;
    return `${(bytes / 1073741824).toFixed(2)} GB`;
  }

  function formatUptime(s: number): string {
    const d = Math.floor(s / 86400);
    const h = Math.floor((s % 86400) / 3600);
    const m = Math.floor((s % 3600) / 60);
    if (d > 0) return `${d}d ${h}h`;
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
  }

  function handleBarEnter(e: MouseEvent, point: ChartPoint) {
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    tooltip = {
      x: rect.left + rect.width / 2 + window.scrollX,
      y: rect.top + window.scrollY,
      label: formatShortDate(point.date),
      value: point.count,
    };
  }

  function handleBarLeave() {
    tooltip = null;
  }
</script>

<svelte:head><title>Analytics - Admin</title></svelte:head>

<div class="analytics-page">
  <div class="page-header">
    <h1 class="page-title">Analytics</h1>
    <select class="days-select" bind:value={days} onchange={loadData}>
      <option value={7}>Last 7 days</option>
      <option value={30}>Last 30 days</option>
      <option value={90}>Last 90 days</option>
    </select>
  </div>

  {#if loading}
    <div style="display:flex;justify-content:center;padding:48px"><Spinner /></div>
  {:else}
    <!-- Summary cards -->
    {#if summary}
      <div class="stat-cards">
        <div class="stat-card">
          <span class="stat-value">{summary.total_users.toLocaleString()}</span>
          <span class="stat-label">Total Users</span>
          <span class="stat-sub">+{summary.registrations_today} today</span>
        </div>
        <div class="stat-card">
          <span class="stat-value">{summary.total_posts.toLocaleString()}</span>
          <span class="stat-label">Total Posts</span>
          <span class="stat-sub">+{summary.posts_today} today · local</span>
        </div>
        <div class="stat-card">
          <span class="stat-value">{summary.total_reactions.toLocaleString()}</span>
          <span class="stat-label">Total Reactions</span>
        </div>
        <div class="stat-card">
          <span class="stat-value">{formatBytes(summary.storage.total_bytes || 0)}</span>
          <span class="stat-label">Storage Used</span>
          <span class="stat-sub">{summary.storage.media_count} files</span>
        </div>
        <div class="stat-card">
          <span class="stat-value">{summary.federation.remote_identities.toLocaleString()}</span>
          <span class="stat-label">Remote Users</span>
          <span class="stat-sub">{summary.federated_posts.toLocaleString()} posts ingested</span>
        </div>
      </div>
    {/if}

    {#snippet chart(title: string, data: ChartPoint[], unit: string, colorClass: string, headline?: number)}
      <div class="chart-card">
        <div class="chart-header">
          <h3 class="chart-title">{title}</h3>
          <span class="chart-total">
            {(headline ?? total(data)).toLocaleString()}
            <span class="chart-total-label">{unit} · last {days} days</span>
          </span>
        </div>

        {#if data.length === 0}
          <p class="chart-empty">No data for this period.</p>
        {:else}
          {@const mx = maxVal(data)}
          <div class="chart-body">
            <div class="chart-yaxis" aria-hidden="true">
              <span>{mx.toLocaleString()}</span>
              <span>0</span>
            </div>
            <div class="chart-plot">
              <div class="chart-gridline" style="top: 0"></div>
              <div class="chart-gridline" style="top: 50%"></div>
              <div class="chart-gridline" style="top: 100%"></div>
              <div class="chart-bars">
                {#each data as point (point.date)}
                  <div
                    class="bar-col"
                    role="img"
                    aria-label="{formatShortDate(point.date)}: {point.count} {unit}"
                    onmouseenter={(e) => handleBarEnter(e, point)}
                    onmouseleave={handleBarLeave}
                    onfocus={(e) => handleBarEnter(e as unknown as MouseEvent, point)}
                    onblur={handleBarLeave}
                    tabindex="0"
                  >
                    <div class="bar {colorClass}" style="height: {Math.max(2, (point.count / mx) * 100)}%"></div>
                  </div>
                {/each}
              </div>
            </div>
          </div>
          <div class="chart-xaxis">
            <span>{formatShortDate(data[0].date)}</span>
            <span>{formatShortDate(data[data.length - 1].date)}</span>
          </div>
        {/if}
      </div>
    {/snippet}

    <!-- Charts -->
    <div class="charts-grid">
      {@render chart('New user registrations per day', userGrowth, 'users', 'bar-primary')}
      {@render chart('Posts per day', postVolume, 'posts', 'bar-blue')}
      {@render chart('Users active per day', activeUsers, 'distinct users', 'bar-green', activeUsersTotal)}
      {@render chart('Federated posts ingested per day', federatedVolume, 'posts', 'bar-amber')}
    </div>

    <!-- System / Queue Stats -->
    {#if queueStats}
      <div class="system-section">
        <h2 class="section-title">System & Workers</h2>
        <div class="system-grid">
          <div class="sys-card">
            <span class="sys-label">Uptime</span>
            <span class="sys-value">{formatUptime(queueStats.system.uptime_seconds)}</span>
          </div>
          <div class="sys-card">
            <span class="sys-label">Memory</span>
            <span class="sys-value">{queueStats.system.memory_total_mb} MB</span>
          </div>
          <div class="sys-card">
            <span class="sys-label">Processes</span>
            <span class="sys-value">{queueStats.system.process_count.toLocaleString()}</span>
          </div>
          <div class="sys-card">
            <span class="sys-label">Schedulers</span>
            <span class="sys-value">{queueStats.system.scheduler_count}</span>
          </div>
          <div class="sys-card">
            <span class="sys-label">NATS</span>
            <span class="sys-value" class:text-up={queueStats.nats.connected} class:text-down={!queueStats.nats.connected}>
              {queueStats.nats.connected ? 'Connected' : 'Disconnected'}
            </span>
          </div>
          <div class="sys-card">
            <span class="sys-label">Active Tasks</span>
            <span class="sys-value">{queueStats.tasks.active}</span>
          </div>
        </div>

        <h3 class="subsection-title">Background Workers</h3>
        <div class="workers-list">
          {#each queueStats.workers as w (w.name)}
            <div class="worker-row">
              <span class="worker-dot" class:dot-up={w.alive} class:dot-down={!w.alive}></span>
              <span class="worker-name">{w.name}</span>
              <span class="worker-status">{w.alive ? 'Running' : 'Stopped'}</span>
            </div>
          {/each}
        </div>
      </div>
    {/if}
  {/if}

  {#if tooltip}
    <div class="chart-tooltip" style="left: {tooltip.x}px; top: {tooltip.y}px">
      <strong>{tooltip.value.toLocaleString()}</strong>
      <span>{tooltip.label}</span>
    </div>
  {/if}
</div>

<style>
  .analytics-page { max-width: 1100px; position: relative; }
  .page-header { display: flex; align-items: center; justify-content: space-between; margin-block-end: var(--space-6); }
  .page-title { font-size: var(--text-2xl); font-weight: 700; }
  .days-select { padding: 6px 12px; border: 1px solid var(--color-border); border-radius: 8px; font-size: 0.875rem; background: var(--color-surface); }

  .stat-cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: var(--space-3); margin-block-end: var(--space-6); }
  .stat-card { background: var(--color-surface-raised); border: 1px solid var(--color-border); border-radius: 14px; padding: 16px; display: flex; flex-direction: column; }
  .stat-value { font-size: 1.5rem; font-weight: 800; color: var(--color-text); }
  .stat-label { font-size: 0.75rem; font-weight: 600; color: var(--color-text-secondary); text-transform: uppercase; letter-spacing: 0.04em; }
  .stat-sub { font-size: 0.7rem; color: var(--color-primary); font-weight: 500; margin-top: 2px; }

  .charts-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: var(--space-4); margin-block-end: var(--space-6); }
  .chart-card { background: var(--color-surface-raised); border: 1px solid var(--color-border); border-radius: 14px; padding: 20px; }
  .chart-header { display: flex; align-items: baseline; justify-content: space-between; gap: var(--space-2); margin-block-end: 12px; }
  .chart-title { font-size: 0.875rem; font-weight: 600; }
  .chart-total { font-size: 1.125rem; font-weight: 700; color: var(--color-text); }
  .chart-total-label { font-size: 0.7rem; font-weight: 500; color: var(--color-text-tertiary); margin-inline-start: 4px; }
  .chart-empty { font-size: 0.8125rem; color: var(--color-text-tertiary); padding: 24px 0; text-align: center; }

  .chart-body { display: flex; gap: 8px; }

  .chart-yaxis {
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    font-size: 0.65rem;
    color: var(--color-text-tertiary);
    font-variant-numeric: tabular-nums;
    padding-block: 2px;
    min-width: 28px;
    text-align: end;
  }

  .chart-plot { flex: 1; position: relative; height: 120px; }
  .chart-gridline {
    position: absolute;
    inset-inline: 0;
    height: 1px;
    background: var(--color-border);
    opacity: 0.5;
  }

  .chart-bars {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: flex-end;
    gap: 2px;
  }
  .bar-col { flex: 1; height: 100%; display: flex; align-items: flex-end; cursor: default; outline: none; }
  .bar {
    width: 100%;
    border-radius: 2px 2px 0 0;
    min-height: 2px;
    transition: height 0.3s ease, opacity 0.15s ease;
  }
  .bar-primary { background: var(--color-primary); }
  .bar-blue { background: var(--color-info); }
  .bar-green { background: var(--color-success); }
  /* Inbound federation — deliberately a different hue from the local
     series so the two post charts don't read as the same measure. */
  .bar-amber { background: var(--color-warning); }
  .bar-col:hover .bar,
  .bar-col:focus-visible .bar { opacity: 0.75; outline: 2px solid var(--color-primary); outline-offset: 2px; }

  .chart-xaxis {
    display: flex;
    justify-content: space-between;
    font-size: 0.65rem;
    color: var(--color-text-tertiary);
    padding-inline-start: 36px;
    margin-block-start: 6px;
  }

  .chart-tooltip {
    position: absolute;
    transform: translate(-50%, calc(-100% - 8px));
    pointer-events: none;
    background: var(--color-text);
    color: var(--color-surface-raised);
    padding: 6px 10px;
    border-radius: 6px;
    font-size: 0.75rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1px;
    white-space: nowrap;
    box-shadow: var(--shadow-sm);
    z-index: 100;
  }
  .chart-tooltip strong { font-size: 0.875rem; font-weight: 700; }
  .chart-tooltip span { opacity: 0.7; }

  .system-section { background: var(--color-surface-raised); border: 1px solid var(--color-border); border-radius: 14px; padding: 20px; }
  .section-title { font-size: var(--text-base); font-weight: 600; margin-block-end: 12px; }
  .subsection-title { font-size: 0.8125rem; font-weight: 600; color: var(--color-text-secondary); margin-top: 16px; margin-bottom: 8px; }

  .system-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 8px; }
  .sys-card { padding: 10px 14px; background: var(--color-surface); border-radius: 10px; }
  .sys-label { display: block; font-size: 0.65rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--color-text-tertiary); }
  .sys-value { font-size: 0.875rem; font-weight: 600; color: var(--color-text); }

  .text-up { color: var(--color-success); }
  .text-down { color: var(--color-danger); }

  .workers-list { display: flex; flex-direction: column; gap: 6px; }
  .worker-row { display: flex; align-items: center; gap: 8px; padding: 6px 10px; background: var(--color-surface); border-radius: 8px; }
  .worker-dot { width: 8px; height: 8px; border-radius: 50%; }
  .dot-up { background: var(--color-success); box-shadow: 0 0 4px var(--color-success); }
  .dot-down { background: var(--color-danger); box-shadow: 0 0 4px var(--color-danger); }
  .worker-name { font-size: 0.8125rem; font-weight: 500; flex: 1; }
  .worker-status { font-size: 0.75rem; color: var(--color-text-secondary); }
</style>
