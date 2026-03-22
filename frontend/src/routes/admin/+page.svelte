<script lang="ts">
  import { onMount } from 'svelte';
  import StatsCard from '$lib/components/admin/StatsCard.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getDashboardStats, getRecentReports } from '$lib/api/admin.js';
  import type { AdminDashboardStats, AdminReport } from '$lib/api/types.js';

  let stats: AdminDashboardStats | null = $state(null);
  let recentReports: AdminReport[] = $state([]);
  let loading = $state(true);

  onMount(async () => {
    try {
      const [s, r] = await Promise.all([getDashboardStats(), getRecentReports()]);
      stats = s;
      recentReports = r;
    } catch (e) {
      addToast('Failed to load dashboard data', 'error');
    } finally {
      loading = false;
    }
  });

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

  .quick-action-btn {
    text-align: center;
  }

  @media (max-width: 768px) {
    .dashboard-panels {
      grid-template-columns: 1fr;
    }

    .stats-grid {
      grid-template-columns: repeat(2, 1fr);
    }
  }
</style>
