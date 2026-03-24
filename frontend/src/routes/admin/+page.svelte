<script lang="ts">
  import { onMount } from 'svelte';
  import StatsCard from '$lib/components/admin/StatsCard.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getDashboardStats, getRecentReports, getVerifications, approveVerification, rejectVerification } from '$lib/api/admin.js';
  import type { AdminDashboardStats, AdminReport, ServiceHealth } from '$lib/api/types.js';
  import type { VerificationRequest } from '$lib/api/admin.js';

  let stats: AdminDashboardStats | null = $state(null);
  let recentReports: AdminReport[] = $state([]);
  let pendingVerifications: VerificationRequest[] = $state([]);
  let loading = $state(true);

  function formatUptime(seconds: number | undefined): string {
    if (!seconds) return '';
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    if (days > 0) return `${days}d ${hours}h`;
    if (hours > 0) return `${hours}h ${mins}m`;
    return `${mins}m`;
  }

  onMount(async () => {
    try {
      const [s, r, v] = await Promise.all([
        getDashboardStats(),
        getRecentReports(),
        getVerifications({ status: 'pending', limit: '10' }).catch(() => [])
      ]);
      stats = s;
      recentReports = r;
      pendingVerifications = v;
    } catch (e) {
      addToast('Failed to load dashboard data', 'error');
    } finally {
      loading = false;
    }
  });

  async function handleApproveVerification(id: string) {
    try {
      await approveVerification(id);
      pendingVerifications = pendingVerifications.filter(v => v.id !== id);
      addToast('Verification approved', 'success');
    } catch {
      addToast('Failed to approve verification', 'error');
    }
  }

  async function handleRejectVerification(id: string) {
    try {
      await rejectVerification(id);
      pendingVerifications = pendingVerifications.filter(v => v.id !== id);
      addToast('Verification rejected', 'success');
    } catch {
      addToast('Failed to reject verification', 'error');
    }
  }

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  }

  function statusClass(status: string): string {
    switch (status) {
      case 'pending': return 'status-pending';
      case 'resolved': return 'status-resolved';
      case 'dismissed': return 'status-dismissed';
      default: return '';
    }
  }
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
        label="Total Users"
        value={stats.total_users.toLocaleString()}
        icon="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"
        href="/admin/users"
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
      />
    {/if}
  </div>

  {#if stats?.services}
    <section class="services-section">
      <h2 class="section-heading">Services</h2>
      <div class="services-grid">
        {#each [
          { key: 'database', label: 'PostgreSQL', icon: 'M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4' },
          { key: 'valkey', label: 'Valkey', icon: 'M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01' },
          { key: 'opensearch', label: 'OpenSearch', icon: 'M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z' },
          { key: 'nats', label: 'NATS JetStream', icon: 'M13 10V3L4 14h7v7l9-11h-7z' }
        ] as svc (svc.key)}
          {@const health = stats.services[svc.key as keyof typeof stats.services]}
          <div class="service-card" class:service-up={health.status === 'up'} class:service-down={health.status === 'down'} class:service-degraded={health.status === 'degraded'}>
            <div class="service-header">
              <div class="service-icon">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <path d={svc.icon} />
                </svg>
              </div>
              <div class="service-status-dot"></div>
            </div>
            <div class="service-name">{svc.label}</div>
            <div class="service-status-text">
              {#if health.status === 'up'}
                Operational
              {:else if health.status === 'degraded'}
                Degraded
              {:else}
                Offline
              {/if}
            </div>

            <!-- Common fields -->
            {#if health.version}
              <div class="service-detail">v{health.version}</div>
            {/if}
            {#if health.uptime_seconds}
              <div class="service-detail">Up {formatUptime(health.uptime_seconds)}</div>
            {/if}

            <!-- Valkey details -->
            {#if svc.key === 'valkey' && health.status === 'up'}
              <div class="service-details-grid">
                <div class="detail-item">
                  <span class="detail-label">Memory</span>
                  <span class="detail-value">{health.memory || '?'}</span>
                </div>
                <div class="detail-item">
                  <span class="detail-label">Peak</span>
                  <span class="detail-value">{health.memory_peak || '?'}</span>
                </div>
                <div class="detail-item">
                  <span class="detail-label">Keys</span>
                  <span class="detail-value">{health.total_keys?.toLocaleString() || '0'}</span>
                </div>
                <div class="detail-item">
                  <span class="detail-label">Clients</span>
                  <span class="detail-value">{health.connected_clients || '0'}</span>
                </div>
              </div>
            {/if}

            <!-- OpenSearch details -->
            {#if svc.key === 'opensearch' && health.status !== 'down'}
              <div class="service-details-grid">
                <div class="detail-item">
                  <span class="detail-label">Cluster</span>
                  <span class="detail-value">{health.cluster_name || '?'}</span>
                </div>
                <div class="detail-item">
                  <span class="detail-label">Health</span>
                  <span class="detail-value" class:text-success={health.cluster_health === 'green'} class:text-warning={health.cluster_health === 'yellow'} class:text-danger={health.cluster_health === 'red'}>{health.cluster_health || '?'}</span>
                </div>
                <div class="detail-item">
                  <span class="detail-label">Nodes</span>
                  <span class="detail-value">{health.node_count || '0'}</span>
                </div>
                <div class="detail-item">
                  <span class="detail-label">Shards</span>
                  <span class="detail-value">{health.active_shards || '0'}</span>
                </div>
              </div>
              {#if health.indices && health.indices.length > 0}
                <div class="service-indices">
                  <div class="indices-title">Indices</div>
                  {#each health.indices as idx}
                    <div class="index-row">
                      <span class="index-name">{idx.name}</span>
                      <span class="index-docs">{idx.docs_count} docs</span>
                      <span class="index-size">{idx.store_size}</span>
                    </div>
                  {/each}
                </div>
              {/if}
            {/if}

            <!-- NATS details -->
            {#if svc.key === 'nats' && health.status === 'up'}
              {#if health.integration === 'pending'}
                <div class="service-detail integration-note">{health.note}</div>
              {/if}
              {#if health.connections !== undefined}
                <div class="service-details-grid">
                  <div class="detail-item">
                    <span class="detail-label">Connections</span>
                    <span class="detail-value">{health.connections}</span>
                  </div>
                  <div class="detail-item">
                    <span class="detail-label">Messages</span>
                    <span class="detail-value">{health.total_messages?.toLocaleString() || '0'}</span>
                  </div>
                  {#if health.jetstream_enabled}
                    <div class="detail-item">
                      <span class="detail-label">JS Streams</span>
                      <span class="detail-value">{health.js_streams || '0'}</span>
                    </div>
                    <div class="detail-item">
                      <span class="detail-label">JS Consumers</span>
                      <span class="detail-value">{health.js_consumers || '0'}</span>
                    </div>
                  {/if}
                </div>
              {/if}
            {/if}

            {#if health.error}
              <div class="service-error">{health.error}</div>
            {/if}
          </div>
        {/each}
      </div>
    </section>
  {/if}

  <div class="dashboard-panels">
    <section class="panel card">
      <h2 class="panel-title">Recent Reports</h2>
      {#if loading}
        <div class="panel-loading">
          {#each Array(3) as _}
            <div class="skeleton" style="height: 48px; margin-bottom: 8px"></div>
          {/each}
        </div>
      {:else if recentReports.length === 0}
        <p class="panel-empty">No open reports</p>
      {:else}
        <ul class="report-list">
          {#each recentReports as report (report.id)}
            <li class="report-item">
              <div class="report-info">
                <span class="report-category">{report.category}</span>
                <span class="report-target">@{report.target_account.handle}</span>
              </div>
              <div class="report-meta">
                <span class="report-status {statusClass(report.status)}">{report.status}</span>
                <span class="report-date">{formatDate(report.created_at)}</span>
              </div>
            </li>
          {/each}
        </ul>
        <a href="/admin/moderation" class="panel-link">View all reports</a>
      {/if}
    </section>

    <section class="panel card">
      <h2 class="panel-title">Quick Actions</h2>
      <div class="quick-actions">
        <a href="/admin/users" class="quick-action-btn btn btn-outline">Manage Users</a>
        <a href="/admin/moderation" class="quick-action-btn btn btn-outline">Review Reports</a>
        <a href="/admin/federation" class="quick-action-btn btn btn-outline">Federation Status</a>
        <a href="/admin/settings" class="quick-action-btn btn btn-outline">Instance Settings</a>
        <a href="/admin/theme" class="quick-action-btn btn btn-outline">Customize Theme</a>
        <a href="/admin/announcements" class="quick-action-btn btn btn-outline">Announcements</a>
      </div>
    </section>
  </div>

  <!-- Pending Verification Requests -->
  {#if pendingVerifications.length > 0}
    <section class="panel card verification-panel">
      <h2 class="panel-title">Pending Verification Requests</h2>
      <div class="verification-list">
        {#each pendingVerifications as req (req.id)}
          <div class="verification-item">
            <div class="verification-user">
              <div class="verification-avatar">
                {#if req.account?.avatar_url}
                  <img src={req.account.avatar_url} alt="" class="verification-img" />
                {:else}
                  <span class="verification-initial">{(req.account?.display_name || req.account?.handle || '?').charAt(0).toUpperCase()}</span>
                {/if}
              </div>
              <div class="verification-info">
                <span class="verification-name">{req.account?.display_name || req.account?.handle}</span>
                <span class="verification-handle">@{req.account?.handle}</span>
              </div>
            </div>
            <div class="verification-details">
              <span class="verification-type">{req.type}</span>
              {#if req.metadata?.reason}
                <p class="verification-reason">{req.metadata.reason}</p>
              {/if}
              {#if req.metadata?.domain}
                <p class="verification-reason">Domain: {req.metadata.domain}</p>
              {/if}
              <span class="verification-date">{formatDate(req.created_at)}</span>
            </div>
            <div class="verification-actions">
              <button class="btn btn-sm btn-primary" onclick={() => handleApproveVerification(req.id)}>Approve</button>
              <button class="btn btn-sm btn-outline" onclick={() => handleRejectVerification(req.id)}>Reject</button>
            </div>
          </div>
        {/each}
      </div>
    </section>
  {/if}
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

  .dashboard-panels {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--space-4);
  }

  .panel-title {
    font-size: var(--text-lg);
    font-weight: 600;
    margin-block-end: var(--space-4);
  }

  .panel-empty {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    text-align: center;
    padding: var(--space-6) 0;
  }

  .panel-loading {
    padding: var(--space-2) 0;
  }

  .report-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .report-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-2) var(--space-3);
    background: var(--color-surface);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  .report-info {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .report-category {
    font-weight: 600;
  }

  .report-target {
    color: var(--color-text-secondary);
  }

  .report-meta {
    display: flex;
    align-items: center;
    gap: var(--space-3);
  }

  .report-status {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
  }

  .status-pending {
    background: var(--color-warning-soft);
    color: #92400e;
  }

  .status-resolved {
    background: var(--color-success-soft);
    color: #166534;
  }

  .status-dismissed {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }

  .report-date {
    color: var(--color-text-tertiary);
    font-size: var(--text-xs);
  }

  .panel-link {
    display: block;
    text-align: center;
    margin-block-start: var(--space-3);
    font-size: var(--text-sm);
    color: var(--color-primary);
  }

  .quick-actions {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  /* Verification requests */
  .verification-panel {
    margin-block-start: var(--space-4);
  }

  .verification-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .verification-item {
    display: flex;
    align-items: flex-start;
    gap: var(--space-3);
    padding: var(--space-3);
    background: var(--color-surface);
    border-radius: var(--radius-lg);
  }

  .verification-user {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-shrink: 0;
  }

  .verification-avatar {
    width: 36px;
    height: 36px;
    border-radius: var(--radius-full);
    background: var(--color-primary-soft);
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    flex-shrink: 0;
  }

  .verification-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .verification-initial {
    font-weight: 600;
    font-size: var(--text-sm);
    color: var(--color-primary);
  }

  .verification-info {
    display: flex;
    flex-direction: column;
  }

  .verification-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .verification-handle {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .verification-details {
    flex: 1;
    min-width: 0;
  }

  .verification-type {
    font-size: var(--text-xs);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.03em;
    color: var(--color-primary);
    background: var(--color-primary-soft);
    padding: 1px 6px;
    border-radius: var(--radius-full);
  }

  .verification-reason {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-start: var(--space-1);
    line-height: 1.4;
  }

  .verification-date {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .verification-actions {
    display: flex;
    gap: var(--space-2);
    flex-shrink: 0;
  }

  .btn-sm {
    padding: var(--space-1) var(--space-3);
    font-size: var(--text-xs);
    border-radius: var(--radius-md);
  }

  .btn-primary {
    background: var(--color-primary);
    color: var(--color-text-on-primary);
    border: none;
    font-weight: 600;
    cursor: pointer;
  }

  .btn-primary:hover {
    background: var(--color-primary-hover);
  }

  .quick-action-btn {
    text-align: center;
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

  .service-card {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-4);
  }

  .service-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-end: var(--space-3);
  }

  .service-icon {
    color: var(--color-text-secondary);
  }

  .service-status-dot {
    width: 10px;
    height: 10px;
    border-radius: var(--radius-full);
    background: var(--color-text-tertiary);
  }

  .service-up .service-status-dot {
    background: var(--color-success);
    box-shadow: 0 0 6px var(--color-success);
  }

  .service-down .service-status-dot {
    background: var(--color-danger);
    box-shadow: 0 0 6px var(--color-danger);
  }

  .service-degraded .service-status-dot {
    background: var(--color-warning);
    box-shadow: 0 0 6px var(--color-warning);
  }

  .service-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
    margin-block-end: 2px;
  }

  .service-status-text {
    font-size: var(--text-xs);
    font-weight: 500;
    margin-block-end: var(--space-2);
  }

  .service-up .service-status-text {
    color: var(--color-success);
  }

  .service-down .service-status-text {
    color: var(--color-danger);
  }

  .service-degraded .service-status-text {
    color: var(--color-warning);
  }

  .service-detail {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    line-height: 1.5;
  }

  .service-error {
    font-size: var(--text-xs);
    color: var(--color-danger);
    margin-block-start: var(--space-1);
  }

  .service-details-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 2px var(--space-3);
    margin-block-start: var(--space-2);
    padding-block-start: var(--space-2);
    border-block-start: 1px solid var(--color-border);
  }

  .detail-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 2px 0;
  }

  .detail-label {
    font-size: 0.65rem;
    color: var(--color-text-tertiary);
    text-transform: uppercase;
    letter-spacing: 0.03em;
  }

  .detail-value {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text);
  }

  .text-success { color: var(--color-success); }
  .text-warning { color: var(--color-warning); }
  .text-danger { color: var(--color-danger); }

  .service-indices {
    margin-block-start: var(--space-2);
    padding-block-start: var(--space-2);
    border-block-start: 1px solid var(--color-border);
  }

  .indices-title {
    font-size: 0.65rem;
    font-weight: 600;
    color: var(--color-text-tertiary);
    text-transform: uppercase;
    letter-spacing: 0.03em;
    margin-block-end: var(--space-1);
  }

  .index-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-xs);
    padding: 2px 0;
  }

  .index-name {
    font-weight: 500;
    color: var(--color-text);
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .index-docs,
  .index-size {
    color: var(--color-text-tertiary);
    white-space: nowrap;
  }

  .integration-note {
    font-style: italic;
    line-height: 1.4;
  }

  @media (max-width: 768px) {
    .dashboard-panels {
      grid-template-columns: 1fr;
    }

    .stats-grid {
      grid-template-columns: repeat(2, 1fr);
    }

    .services-grid {
      grid-template-columns: repeat(2, 1fr);
    }
  }
</style>
