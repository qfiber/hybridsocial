<script lang="ts">
  // Dashboard, ordered by urgency: what needs a human now, how the server
  // is trending, whether its services are healthy, and what staff did last.
  import { onMount, onDestroy } from 'svelte';
  import ServicePanel from '$lib/components/admin/ServicePanel.svelte';
  import Sparkline from '$lib/components/admin/Sparkline.svelte';
  import StatusPill from '$lib/components/admin/StatusPill.svelte';
  import AdminPage from '$lib/components/admin/AdminPage.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { t } from '$lib/stores/i18n.js';
  import { t as ti } from '$lib/utils/i18n.js';
  import { relativeTime } from '$lib/utils/time.js';
  import { api } from '$lib/api/client.js';
  import { getDashboardStats, getAuditLog } from '$lib/api/admin.js';
  import type { AdminDashboardStats, AuditLogEntry } from '$lib/api/types.js';
  import { hasPermission, hasAnyPermission } from '$lib/stores/auth.js';

  let stats = $state<AdminDashboardStats | null>(null);
  let pendingApprovals = $state(0);
  let pendingAppeals = $state(0);
  let deadLetters = $state(0);
  let stoppedPeers = $state(0);
  let loading = $state(true);

  // Needs-attention queues. Only the non-empty ones are shown.
  type Attention = { key: string; count: number; href: string; icon: string };
  let attention = $derived<Attention[]>(
    stats
      ? [
          { key: 'reports', count: stats.open_reports, href: '/admin/moderation', icon: 'M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z' },
          { key: 'approvals', count: pendingApprovals, href: '/admin/user-management/approvals', icon: 'M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M8.5 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM17 11l2 2 4-4' },
          { key: 'appeals', count: pendingAppeals, href: '/admin/user-management/appeals', icon: 'M3 6l3 1m0 0l-3 9a5 5 0 006 0M6 7l3 9M6 7l6-2m6 2l3-1m-3 1l-3 9a5 5 0 006 0M18 7l3 9m-9-14v18' },
          { key: 'verifications', count: stats.pending_verifications ?? 0, href: '/admin/moderation?tab=verifications', icon: 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z' },
          { key: 'dead_letters', count: deadLetters, href: '/admin/federation', icon: 'M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z' },
          { key: 'stopped_peers', count: stoppedPeers, href: '/admin/federation', icon: 'M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636' },
        ].filter((a) => a.count > 0)
      : [],
  );

  // Last 14 days, from the analytics endpoints (needs settings.view).
  const TREND_DAYS = 14;
  type ChartPoint = { date: string; count: number };
  type Trend = { key: string; total: number; points: { t: string; v: number }[] };
  let trends = $state<Trend[]>([]);
  const canSeeTrends = hasPermission('settings.view');
  const canSeeAudit = hasPermission('audit_log.view');
  const canSeeFederation = hasAnyPermission('federation.view', 'federation.manage');

  let recent = $state<AuditLogEntry[]>([]);

  // Historical service metrics (1h sparklines + latest values), polled
  // separately so a slow probe doesn't delay the rest of the page.
  type MetricRow = {
    service: string;
    metric: string;
    latest: { t: string; v: number };
    sparkline: { t: string; v: number }[];
  };
  let metricRows: MetricRow[] = $state([]);

  function fmtBytes(n: number): string {
    if (!Number.isFinite(n) || n <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    let v = n;
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
    return v.toFixed(v >= 100 ? 0 : v >= 10 ? 1 : 2) + ' ' + units[i];
  }
  function fmtInt(n: number): string {
    return Math.round(n).toLocaleString();
  }
  function fmtRate(n: number, suffix = '/s'): string {
    return Math.round(n).toLocaleString() + suffix;
  }
  function fmtPct(n: number): string {
    return (n * 100).toFixed(1) + '%';
  }
  function fmtClusterStatus(n: number): string {
    return ['green', 'yellow', 'red'][Math.round(n)] ?? '?';
  }

  const pgMetrics = [
    { key: 'connections_active', label: 'Active conns', format: fmtInt },
    { key: 'connections_idle', label: 'Idle conns', format: fmtInt },
    { key: 'db_size_bytes', label: 'DB size', format: fmtBytes },
    { key: 'xact_commit', label: 'Commits/s', format: (v: number) => fmtRate(v) },
    { key: 'cache_hit_ratio', label: 'Cache hit', format: fmtPct },
  ];
  const valkeyMetrics = [
    { key: 'memory_used_bytes', label: 'Memory', format: fmtBytes },
    { key: 'memory_peak_bytes', label: 'Peak', format: fmtBytes },
    { key: 'total_keys', label: 'Keys', format: fmtInt },
    { key: 'connected_clients', label: 'Clients', format: fmtInt },
    { key: 'ops_per_sec', label: 'Ops/sec', format: (v: number) => fmtRate(v) },
    { key: 'evicted_keys', label: 'Evictions/s', format: (v: number) => fmtRate(v) },
  ];
  const natsMetrics = [
    { key: 'connections', label: 'Connections', format: fmtInt },
    { key: 'in_msgs', label: 'In msgs/s', format: (v: number) => fmtRate(v) },
    { key: 'out_msgs', label: 'Out msgs/s', format: (v: number) => fmtRate(v) },
    { key: 'jetstream_messages', label: 'JS messages', format: fmtInt },
    { key: 'jetstream_bytes', label: 'JS bytes', format: fmtBytes },
  ];
  const opensearchMetrics = [
    { key: 'cluster_status', label: 'Cluster', format: fmtClusterStatus },
    { key: 'index_count', label: 'Indices', format: fmtInt },
    { key: 'total_docs', label: 'Total docs', format: fmtInt },
    { key: 'index_size_bytes', label: 'Index size', format: fmtBytes },
    { key: 'unassigned_shards', label: 'Unassigned', format: fmtInt },
  ];

  async function loadMetrics() {
    try {
      const res = await api.poll<{ services: MetricRow[] }>('/api/v1/admin/metrics/summary');
      metricRows = res.services || [];
    } catch {
      metricRows = [];
    }
  }

  const count = <T,>(p: Promise<{ data?: T[] }>) => p.then((r) => (r.data || []).length).catch(() => 0);

  async function loadTrends() {
    if (!canSeeTrends) return;
    const series = async (key: string, path: string): Promise<Trend> => {
      const res = await api.get<{ data: ChartPoint[] }>(`/api/v1/admin/analytics/${path}?days=${TREND_DAYS}`);
      const byDate = new Map((res.data || []).map((p) => [p.date.slice(0, 10), p.count]));
      // The API only returns days with activity; quiet days are zeros.
      const points = Array.from({ length: TREND_DAYS }, (_, i) => {
        const d = new Date(Date.now() - (TREND_DAYS - 1 - i) * 86_400_000).toISOString().slice(0, 10);
        return { t: d, v: byDate.get(d) ?? 0 };
      });
      return { key, total: points.reduce((n, p) => n + p.v, 0), points };
    };
    try {
      trends = await Promise.all([
        series('new_members', 'user_growth'),
        series('posts', 'post_volume'),
        series('active_users', 'active_users'),
      ]);
    } catch {
      trends = [];
    }
  }

  async function loadRecent() {
    if (!canSeeAudit) return;
    try {
      recent = ((await getAuditLog({ limit: '6' })).data || []).slice(0, 6);
    } catch {
      recent = [];
    }
  }

  let metricsTimer: ReturnType<typeof setInterval> | null = null;

  onMount(async () => {
    try {
      const [s, pa, ap, dl, sp] = await Promise.all([
        getDashboardStats(),
        count(api.get<{ data: { id: string }[] }>('/api/v1/admin/pending_accounts')),
        count(api.get<{ data: { id: string }[] }>('/api/v1/admin/appeals', { status: 'pending' })),
        canSeeFederation
          ? api.get<{ total: number }>('/api/v1/admin/federation/dead_letters', { limit: '1' }).then((r) => r.total || 0).catch(() => 0)
          : Promise.resolve(0),
        canSeeFederation ? count(api.get<{ data: unknown[] }>('/api/v1/admin/federation/delivery_disabled')) : Promise.resolve(0),
      ]);
      stats = s;
      pendingApprovals = pa;
      pendingAppeals = ap;
      deadLetters = dl;
      stoppedPeers = sp;
    } catch {
      addToast(ti('admin_dashboard.load_error'), 'error');
    } finally {
      loading = false;
    }

    loadTrends();
    loadRecent();
    // The collector ticks every 60s; refresh the sparklines at that pace.
    loadMetrics();
    metricsTimer = setInterval(loadMetrics, 60_000);
  });

  onDestroy(() => {
    if (metricsTimer) clearInterval(metricsTimer);
  });
</script>

<AdminPage title={$t('admin_dashboard.title')}>
  <section class="dash-section" aria-labelledby="dash-attention">
    <h2 class="section-heading" id="dash-attention">{$t('admin_dashboard.attention')}</h2>
    {#if loading}
      <div class="attention-grid">
        {#each Array(3) as _, i (i)}
          <div class="card attention-skeleton"><div class="skeleton" style="height: 44px"></div></div>
        {/each}
      </div>
    {:else if attention.length === 0}
      <div class="card all-clear">
        <StatusPill tone="success" label={$t('admin_dashboard.all_clear')} />
        <span class="all-clear-text">{$t('admin_dashboard.all_clear_desc')}</span>
      </div>
    {:else}
      <div class="attention-grid">
        {#each attention as item (item.key)}
          <a class="card card-hover attention-tile" href={item.href}>
            <span class="attention-icon" aria-hidden="true">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d={item.icon} /></svg>
            </span>
            <span class="attention-count">{item.count.toLocaleString()}</span>
            <span class="attention-label">{$t(`admin_dashboard.queue.${item.key}`, { count: item.count })}</span>
          </a>
        {/each}
      </div>
    {/if}
  </section>

  {#if stats}
    <section class="dash-section" aria-labelledby="dash-glance">
      <h2 class="section-heading" id="dash-glance">
        {canSeeTrends ? $t('admin_dashboard.trends', { days: TREND_DAYS }) : $t('admin_dashboard.totals')}
      </h2>
      <div class="glance-grid">
        {#each trends as trend (trend.key)}
          <a class="card card-hover glance-card" href="/admin/analytics">
            <span class="glance-label">{$t(`admin_dashboard.trend.${trend.key}`)}</span>
            <span class="glance-value">{trend.total.toLocaleString()}</span>
            <Sparkline points={trend.points} width={180} height={36} />
          </a>
        {/each}
        <div class="card glance-card glance-totals">
          <span class="glance-label">{$t('admin_dashboard.all_time')}</span>
          <dl class="totals">
            <div><dt>{$t('admin_dashboard.total_members')}</dt><dd>{stats.total_users.toLocaleString()}</dd></div>
            <div><dt>{$t('admin_dashboard.total_posts')}</dt><dd>{stats.total_posts.toLocaleString()}</dd></div>
            <div><dt>{$t('admin_dashboard.known_instances')}</dt><dd>{stats.known_instances.toLocaleString()}</dd></div>
          </dl>
        </div>
      </div>
    </section>
  {/if}

  <section class="dash-section" aria-labelledby="dash-health">
    <h2 class="section-heading" id="dash-health">{$t('admin_dashboard.health')}</h2>
    <div class="metrics-grid">
      <ServicePanel
        title="PostgreSQL"
        icon="database"
        service="postgres"
        metrics={pgMetrics}
        rows={metricRows}
        health={stats?.services?.database ?? null}
      />
      <ServicePanel
        title="Valkey"
        icon="bolt"
        service="valkey"
        metrics={valkeyMetrics}
        rows={metricRows}
        health={stats?.services?.valkey ?? null}
      />
      <ServicePanel
        title="NATS"
        icon="hub"
        service="nats"
        metrics={natsMetrics}
        rows={metricRows}
        health={stats?.services?.nats ?? null}
      />
      <ServicePanel
        title="OpenSearch"
        icon="search"
        service="opensearch"
        metrics={opensearchMetrics}
        rows={metricRows}
        health={stats?.services?.opensearch ?? null}
        noChart
      />
    </div>
  </section>

  {#if canSeeAudit}
    <section class="dash-section" aria-labelledby="dash-recent">
      <div class="section-head-row">
        <h2 class="section-heading" id="dash-recent">{$t('admin_dashboard.recent')}</h2>
        <a class="section-link" href="/admin/audit-log">{$t('admin_dashboard.open_audit_log')}</a>
      </div>
      {#if recent.length}
        <ul class="card recent-list">
          {#each recent as entry (entry.id)}
            <li class="recent-item">
              <span class="recent-actor">{entry.actor ? '@' + entry.actor.handle : $t('admin_dashboard.system')}</span>
              <code class="recent-action">{entry.action}</code>
              {#if entry.target?.label}<span class="recent-target">{entry.target.label}</span>{/if}
              <time class="recent-time" datetime={entry.created_at}>{relativeTime(entry.created_at)}</time>
            </li>
          {/each}
        </ul>
      {:else}
        <p class="muted">{$t('admin_dashboard.no_recent')}</p>
      {/if}
    </section>
  {/if}
</AdminPage>

<style>
  .dash-section {
    margin-block-end: var(--space-2);
  }

  .section-heading {
    margin: 0 0 var(--space-3);
    font-size: var(--text-lg);
    font-weight: 600;
  }

  .section-head-row {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: var(--space-3);
  }

  .section-link {
    font-size: var(--text-sm);
  }

  .muted {
    margin: 0;
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  /* Needs attention */
  .attention-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: var(--space-3);
  }

  .attention-tile {
    display: grid;
    grid-template-columns: auto 1fr;
    grid-template-rows: auto auto;
    column-gap: var(--space-3);
    align-items: center;
    padding: var(--space-4);
    border-inline-start: 3px solid var(--color-warning);
    color: var(--color-text);
    text-decoration: none;
  }

  .attention-tile:hover {
    text-decoration: none;
  }

  .attention-icon {
    grid-row: span 2;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    border-radius: var(--radius-lg);
    background: var(--color-warning-soft);
    color: var(--color-on-warning-soft);
  }

  .attention-count {
    font-size: var(--text-2xl);
    font-weight: 700;
    line-height: 1.1;
    font-variant-numeric: tabular-nums;
  }

  .attention-label {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .attention-skeleton {
    padding: var(--space-4);
  }

  .all-clear {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: var(--space-3);
    padding: var(--space-4);
  }

  .all-clear-text {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  /* Trends and totals */
  .glance-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
    gap: var(--space-3);
  }

  .glance-card {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: var(--space-4);
    color: var(--color-text);
    text-decoration: none;
  }

  .glance-card:hover {
    text-decoration: none;
  }

  .glance-label {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .glance-value {
    font-size: var(--text-2xl);
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }

  .totals {
    display: flex;
    flex-direction: column;
    gap: 4px;
    margin: 4px 0 0;
  }

  .totals div {
    display: flex;
    justify-content: space-between;
    gap: var(--space-3);
    font-size: var(--text-sm);
  }

  .totals dt {
    color: var(--color-text-secondary);
  }

  .totals dd {
    margin: 0;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  /* Health */
  .metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
    gap: var(--space-3);
  }

  /* Recent staff actions */
  .recent-list {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .recent-item {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    gap: 4px var(--space-2);
    padding: var(--space-3) var(--space-4);
    font-size: var(--text-sm);
  }

  .recent-item + .recent-item {
    border-block-start: 1px solid var(--color-border);
  }

  .recent-actor {
    font-weight: 600;
  }

  .recent-action {
    font-size: var(--text-xs);
    padding: 1px 6px;
    border-radius: var(--radius-sm);
    background: var(--color-surface-container);
  }

  .recent-target {
    color: var(--color-text-secondary);
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .recent-time {
    margin-inline-start: auto;
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    white-space: nowrap;
  }

  @media (max-width: 400px) {
    .metrics-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
