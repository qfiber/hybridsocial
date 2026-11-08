<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import StatsCard from '$lib/components/admin/StatsCard.svelte';
  import ServicePanel from '$lib/components/admin/ServicePanel.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { api } from '$lib/api/client.js';
  import { getDashboardStats } from '$lib/api/admin.js';
  import type { AdminDashboardStats } from '$lib/api/types.js';
  import { adminSections, type AdminItem } from '$lib/admin-nav.js';
  import { hasPermission, hasAnyPermission } from '$lib/stores/auth.js';

  // Card hub: the same catalog the sidebar renders, filtered to what this
  // staffer can reach. Every admin page — including the ones that used to
  // have no link at all — is one click from here.
  function itemVisible(item: AdminItem): boolean {
    if (item.permission) return hasPermission(item.permission);
    if (item.anyPermission) return hasAnyPermission(...item.anyPermission);
    return true;
  }
  const hubSections = adminSections
    .map((s) => ({ ...s, items: s.items.filter((i) => i.href !== '/admin' && itemVisible(i)) }))
    .filter((s) => s.items.length > 0);

  let stats: AdminDashboardStats | null = $state(null);
  let pendingApprovalsCount = $state(0);
  let pendingAppealsCount = $state(0);
  let loading = $state(true);

  // Historical service metrics (1h sparklines + latest values).
  // Polled separately from the dashboard summary so a slow probe
  // doesn't delay the rest of the page.
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

  let metricsTimer: ReturnType<typeof setInterval> | null = null;

  onMount(async () => {
    try {
      const [s, pa, ap] = await Promise.all([
        getDashboardStats(),
        // Account-registration approvals are surfaced as a stats card
        // and link to /admin/user-management/approvals. We only need
        // the count, but the endpoint returns the full pending list —
        // the page is the authoritative actor view.
        api
          .get<{ data: { id: string }[] }>('/api/v1/admin/pending_accounts')
          .then((res) => (res.data || []).length)
          .catch(() => 0),
        // Pending suspension appeals — same dashboard pattern.
        api
          .get<{ data: { id: string }[] }>('/api/v1/admin/appeals', { status: 'pending' })
          .then((res) => (res.data || []).length)
          .catch(() => 0),
      ]);
      stats = s;
      pendingApprovalsCount = pa;
      pendingAppealsCount = ap;
    } catch (e) {
      addToast('Failed to load dashboard data', 'error');
    } finally {
      loading = false;
    }

    // Metrics summary is loaded after the main payload. The collector
    // ticks every 60s, so refreshing the dashboard at the same cadence
    // keeps the sparklines moving without piling on load.
    loadMetrics();
    metricsTimer = setInterval(loadMetrics, 60_000);
  });

  onDestroy(() => {
    if (metricsTimer) clearInterval(metricsTimer);
  });
</script>

<svelte:head>
  <title>Admin Dashboard</title>
</svelte:head>

<div class="dashboard">
  <h1 class="page-title">Dashboard</h1>

  <div class="stats-grid">
    {#if loading}
      {#each Array(4) as _}
        <div class="card">
          <div class="skeleton" style="height: 16px; width: 60%; margin-bottom: 8px"></div>
          <div class="skeleton" style="height: 32px; width: 40%"></div>
        </div>
      {/each}
    {:else if stats}
      <StatsCard
        label="Local Users"
        value={stats.total_users.toLocaleString()}
        icon="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"
        href="/admin/user-management/users"
      />
      <StatsCard
        label="Total Posts"
        value={stats.total_posts.toLocaleString()}
        icon="M7 8h10M7 12h4m1 8l-4-4H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-3l-4 4z"
      />
      <StatsCard
        label="Known Instances"
        value={stats.known_instances.toLocaleString()}
        icon="M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
        href="/admin/federation"
      />
      <StatsCard
        label="Open Reports"
        value={stats.open_reports.toLocaleString()}
        icon="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.34 16.5c-.77.833.192 2.5 1.732 2.5z"
        href="/admin/moderation"
        alert={stats.open_reports > 0}
        alertLabel={`${stats.open_reports} open reports — needs attention`}
      />
      <StatsCard
        label="Approvals"
        value={pendingApprovalsCount.toLocaleString()}
        icon="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
        href="/admin/user-management/approvals"
        alert={pendingApprovalsCount > 0}
        alertLabel={`${pendingApprovalsCount} pending approvals — needs attention`}
      />
      <StatsCard
        label="Appeals"
        value={pendingAppealsCount.toLocaleString()}
        icon="M3 6l3 1m0 0l-3 9a5.002 5.002 0 006.001 0M6 7l3 9M6 7l6-2m6 2l3-1m-3 1l-3 9a5.002 5.002 0 006.001 0M18 7l3 9m-3-9l-6-2m0-2v2m0 16V5m0 16H9m3 0h3"
        href="/admin/user-management/appeals"
        alert={pendingAppealsCount > 0}
        alertLabel={`${pendingAppealsCount} pending appeals — needs attention`}
      />
      <StatsCard
        label="Verifications"
        value={(stats.pending_verifications ?? 0).toLocaleString()}
        icon="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
        href="/admin/moderation?tab=verifications"
        alert={(stats.pending_verifications ?? 0) > 0}
        alertLabel={`${stats.pending_verifications ?? 0} pending verification requests — needs attention`}
      />
    {/if}
  </div>

  {#each hubSections as section (section.title)}
    <section class="hub-section">
      <div class="hub-section-head">
        <h2 class="section-heading">{section.title}</h2>
        <p class="hub-section-blurb">{section.blurb}</p>
      </div>
      <div class="hub-grid">
        {#each section.items as item (item.href)}
          <a href={item.href} class="hub-card card card-hover">
            <span class="hub-card-icon" aria-hidden="true">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d={item.icon} />
              </svg>
            </span>
            <span class="hub-card-text">
              <span class="hub-card-label">{item.label}</span>
              <span class="hub-card-desc">{item.description}</span>
            </span>
            <svg class="rtl-mirror hub-card-chevron" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="9 18 15 12 9 6" /></svg>
          </a>
        {/each}
      </div>
    </section>
  {/each}

  <section class="services-section metrics-section">
    <h2 class="section-heading">Service metrics</h2>
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

</div>

<style>
  .dashboard {
    max-width: 1100px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-6);
  }

  .stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
    gap: var(--space-4);
    margin-block-end: var(--space-6);
  }

  /* Card hub: grouped, description-led cards — the admin mirror of the
     member settings index. Every section from the nav catalog renders
     here so nothing is more than one click away. */
  .hub-section {
    margin-block-end: var(--space-6);
  }

  .hub-section-head {
    display: flex;
    align-items: baseline;
    gap: var(--space-3);
    margin-block-end: var(--space-3);
    flex-wrap: wrap;
  }

  .hub-section-blurb {
    margin: 0;
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  .hub-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
    gap: var(--space-3);
  }

  .hub-card {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-4);
    text-decoration: none;
    color: inherit;
  }

  .hub-card:hover {
    text-decoration: none;
  }

  .hub-card-icon {
    flex-shrink: 0;
    width: 40px;
    height: 40px;
    border-radius: var(--radius-lg, 12px);
    display: grid;
    place-items: center;
    background: var(--color-primary-soft);
    color: var(--color-primary);
  }

  .hub-card-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
  }

  .hub-card-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .hub-card-desc {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    line-height: 1.35;
  }

  .hub-card-chevron {
    flex-shrink: 0;
    color: var(--color-text-tertiary);
  }

  /* Services */
  .services-section {
    margin-block-end: var(--space-6);
  }

  .section-heading {
    font-size: var(--text-lg);
    font-weight: 600;
    margin-block-end: var(--space-4);
  }

  .services-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: var(--space-3);
  }

  .metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
    gap: var(--space-3);
  }


  .integration-note {
    font-style: italic;
    line-height: 1.4;
  }

  @media (max-width: 768px) {
    .stats-grid {
      grid-template-columns: repeat(2, 1fr);
    }

    .services-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
