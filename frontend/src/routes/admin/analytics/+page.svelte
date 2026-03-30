<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface ChartPoint { date: string; count: number; }
  interface Summary { total_users: number; total_posts: number; total_reactions: number; posts_today: number; registrations_today: number; storage: { media_count: number; total_bytes: number }; federation: { remote_actors: number; remote_identities: number }; }
  interface QueueStats { nats: { connected: boolean }; tasks: { active: number }; workers: { name: string; alive: boolean }[]; system: { uptime_seconds: number; memory_total_mb: number; process_count: number; scheduler_count: number }; }

  let summary = $state<Summary | null>(null);
  let userGrowth = $state<ChartPoint[]>([]);
  let postVolume = $state<ChartPoint[]>([]);
  let activeUsers = $state<ChartPoint[]>([]);
  let queueStats = $state<QueueStats | null>(null);
  let loading = $state(true);
  let days = $state(30);

  async function loadData() {
    loading = true;
    try {
      const [s, ug, pv, au, qs] = await Promise.all([
        api.get<Summary>('/api/v1/admin/analytics/summary'),
        api.get<{ data: ChartPoint[] }>(`/api/v1/admin/analytics/user_growth?days=${days}`),
        api.get<{ data: ChartPoint[] }>(`/api/v1/admin/analytics/post_volume?days=${days}`),
        api.get<{ data: ChartPoint[] }>(`/api/v1/admin/analytics/active_users?days=${days}`),
        api.get<QueueStats>('/api/v1/admin/queue_stats'),
      ]);
      summary = s;
      userGrowth = ug.data || [];
      postVolume = pv.data || [];
      activeUsers = au.data || [];
      queueStats = qs;
    } catch { /* */ }
    finally { loading = false; }
  }

  onMount(loadData);

  function maxVal(data: ChartPoint[]): number {
    return Math.max(1, ...data.map(d => d.count));
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
          <span class="stat-sub">+{summary.posts_today} today</span>
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
          <span class="stat-value">{summary.federation.remote_identities}</span>
          <span class="stat-label">Remote Users</span>
        </div>
      </div>
    {/if}

    <!-- Charts -->
    <div class="charts-grid">
      <div class="chart-card">
        <h3 class="chart-title">User Registrations</h3>
        <div class="chart-bars">
          {#each userGrowth as point (point.date)}
            <div class="bar-col" title="{point.date}: {point.count}">
              <div class="bar" style="height: {Math.max(2, (point.count / maxVal(userGrowth)) * 100)}%"></div>
            </div>
          {/each}
        </div>
      </div>

      <div class="chart-card">
        <h3 class="chart-title">Post Volume</h3>
        <div class="chart-bars">
          {#each postVolume as point (point.date)}
            <div class="bar-col" title="{point.date}: {point.count}">
              <div class="bar bar-blue" style="height: {Math.max(2, (point.count / maxVal(postVolume)) * 100)}%"></div>
            </div>
          {/each}
        </div>
      </div>

      <div class="chart-card">
        <h3 class="chart-title">Active Users (daily)</h3>
        <div class="chart-bars">
          {#each activeUsers as point (point.date)}
            <div class="bar-col" title="{point.date}: {point.count}">
              <div class="bar bar-green" style="height: {Math.max(2, (point.count / maxVal(activeUsers)) * 100)}%"></div>
            </div>
          {/each}
        </div>
      </div>
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
</div>

<style>
  .analytics-page { max-width: 1100px; }
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
  .chart-title { font-size: 0.875rem; font-weight: 600; margin-block-end: 12px; }

  .chart-bars { display: flex; align-items: flex-end; gap: 2px; height: 120px; }
  .bar-col { flex: 1; height: 100%; display: flex; align-items: flex-end; cursor: default; }
  .bar { width: 100%; background: var(--color-primary); border-radius: 2px 2px 0 0; min-height: 2px; transition: height 0.3s ease; }
  .bar-blue { background: #3b82f6; }
  .bar-green { background: #22c55e; }
  .bar-col:hover .bar { opacity: 0.8; }

  .system-section { background: var(--color-surface-raised); border: 1px solid var(--color-border); border-radius: 14px; padding: 20px; }
  .section-title { font-size: var(--text-base); font-weight: 600; margin-block-end: 12px; }
  .subsection-title { font-size: 0.8125rem; font-weight: 600; color: var(--color-text-secondary); margin-top: 16px; margin-bottom: 8px; }

  .system-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 8px; }
  .sys-card { padding: 10px 14px; background: var(--color-surface); border-radius: 10px; }
  .sys-label { display: block; font-size: 0.65rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--color-text-tertiary); }
  .sys-value { font-size: 0.875rem; font-weight: 600; color: var(--color-text); }

  .text-up { color: var(--color-success, #22c55e); }
  .text-down { color: var(--color-danger, #ef4444); }

  .workers-list { display: flex; flex-direction: column; gap: 6px; }
  .worker-row { display: flex; align-items: center; gap: 8px; padding: 6px 10px; background: var(--color-surface); border-radius: 8px; }
  .worker-dot { width: 8px; height: 8px; border-radius: 50%; }
  .dot-up { background: var(--color-success, #22c55e); box-shadow: 0 0 4px var(--color-success, #22c55e); }
  .dot-down { background: var(--color-danger, #ef4444); box-shadow: 0 0 4px var(--color-danger, #ef4444); }
  .worker-name { font-size: 0.8125rem; font-weight: 500; flex: 1; }
  .worker-status { font-size: 0.75rem; color: var(--color-text-secondary); }
</style>
