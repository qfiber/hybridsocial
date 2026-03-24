<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import Modal from '$lib/components/ui/Modal.svelte';
  import {
    getModerationQueue, getModerationQueueStats,
    approveQueueItem, rejectQueueItem, escalateQueueItem
  } from '$lib/api/admin.js';
  import type { ModerationQueueItem, ModerationQueueStats } from '$lib/api/types.js';

  let items: ModerationQueueItem[] = $state([]);
  let stats: ModerationQueueStats | null = $state(null);
  let loading = $state(true);

  // Filters
  let statusFilter = $state('pending');
  let typeFilter = $state('all');
  let severityFilter = $state('all');

  let filteredItems = $derived(
    items.filter((item) => {
      const matchesStatus = statusFilter === 'all' || item.status === statusFilter;
      const matchesType = typeFilter === 'all' || item.type === typeFilter;
      const matchesSeverity = severityFilter === 'all' || item.severity === severityFilter;
      return matchesStatus && matchesType && matchesSeverity;
    })
  );

  // Reject modal
  let rejectModalOpen = $state(false);
  let rejectTarget: ModerationQueueItem | null = $state(null);
  let rejectReason = $state('');

  onMount(async () => {
    await Promise.all([loadItems(), loadStats()]);
  });

  async function loadItems() {
    loading = true;
    try {
      items = await getModerationQueue();
    } catch {
      addToast('Failed to load moderation queue', 'error');
    } finally {
      loading = false;
    }
  }

  async function loadStats() {
    try {
      stats = await getModerationQueueStats();
    } catch {
      // Stats are non-critical
    }
  }

  async function handleApprove(item: ModerationQueueItem) {
    try {
      const updated = await approveQueueItem(item.id);
      items = items.map((i) => (i.id === updated.id ? updated : i));
      loadStats();
      addToast('Item approved', 'success');
    } catch {
      addToast('Failed to approve item', 'error');
    }
  }

  function openRejectModal(item: ModerationQueueItem) {
    rejectTarget = item;
    rejectReason = '';
    rejectModalOpen = true;
  }

  async function handleReject() {
    if (!rejectTarget) return;
    try {
      const updated = await rejectQueueItem(rejectTarget.id, rejectReason || undefined);
      items = items.map((i) => (i.id === updated.id ? updated : i));
      rejectModalOpen = false;
      loadStats();
      addToast('Item rejected', 'success');
    } catch {
      addToast('Failed to reject item', 'error');
    }
  }

  async function handleEscalate(item: ModerationQueueItem) {
    try {
      const updated = await escalateQueueItem(item.id);
      items = items.map((i) => (i.id === updated.id ? updated : i));
      loadStats();
      addToast('Item escalated', 'success');
    } catch {
      addToast('Failed to escalate item', 'error');
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

  function severityClass(severity: string): string {
    switch (severity) {
      case 'critical': return 'severity-critical';
      case 'high': return 'severity-high';
      case 'medium': return 'severity-medium';
      case 'low': return 'severity-low';
      default: return '';
    }
  }
</script>

<svelte:head>
  <title>Moderation Queue - Admin</title>
</svelte:head>

<div class="queue-page">
  <h1 class="page-title">Moderation Queue</h1>

  {#if stats}
    <div class="stats-bar">
      <div class="stat-item card">
        <div class="stat-label">Pending</div>
        <div class="stat-value">{stats.pending.toLocaleString()}</div>
      </div>
      <div class="stat-item card">
        <div class="stat-label">Approved</div>
        <div class="stat-value stat-success">{stats.approved.toLocaleString()}</div>
      </div>
      <div class="stat-item card">
        <div class="stat-label">Rejected</div>
        <div class="stat-value stat-danger">{stats.rejected.toLocaleString()}</div>
      </div>
      <div class="stat-item card">
        <div class="stat-label">Escalated</div>
        <div class="stat-value stat-warning">{stats.escalated.toLocaleString()}</div>
      </div>
    </div>
  {/if}

  <div class="toolbar">
    <select class="input" style="width: 140px" bind:value={statusFilter}>
      <option value="all">All Status</option>
      <option value="pending">Pending</option>
      <option value="approved">Approved</option>
      <option value="rejected">Rejected</option>
      <option value="escalated">Escalated</option>
    </select>
    <select class="input" style="width: 140px" bind:value={typeFilter}>
      <option value="all">All Types</option>
      <option value="post">Post</option>
      <option value="media">Media</option>
      <option value="account">Account</option>
      <option value="report">Report</option>
    </select>
    <select class="input" style="width: 140px" bind:value={severityFilter}>
      <option value="all">All Severity</option>
      <option value="critical">Critical</option>
      <option value="high">High</option>
      <option value="medium">Medium</option>
      <option value="low">Low</option>
    </select>
    <button class="btn btn-outline" type="button" onclick={loadItems}>Refresh</button>
  </div>

  {#if loading}
    <div class="loading-area">
      <div class="skeleton" style="height: 80px"></div>
      <div class="skeleton" style="height: 80px"></div>
      <div class="skeleton" style="height: 80px"></div>
    </div>
  {:else}
    <div class="list-items">
      {#each filteredItems as item (item.id)}
        <div class="queue-item card">
          <div class="queue-item-header">
            <div class="queue-item-meta">
              <span class="badge-type">{item.type}</span>
              <span class="severity-badge {severityClass(item.severity)}">{item.severity}</span>
              <span class="status-badge status-{item.status}">{item.status}</span>
            </div>
            <span class="queue-item-date text-secondary">{formatDate(item.created_at)}</span>
          </div>
          <div class="queue-item-content">
            <p class="content-preview">{item.content_preview}</p>
            <span class="queue-item-source text-secondary">Source: {item.source}</span>
          </div>
          {#if item.reason}
            <div class="queue-item-reason text-secondary">
              Reason: {item.reason}
            </div>
          {/if}
          {#if item.status === 'pending'}
            <div class="action-buttons">
              <button class="btn btn-sm btn-primary" type="button" onclick={() => handleApprove(item)}>
                Approve
              </button>
              <button class="btn btn-sm btn-danger" type="button" onclick={() => openRejectModal(item)}>
                Reject
              </button>
              <button class="btn btn-sm btn-outline" type="button" onclick={() => handleEscalate(item)}>
                Escalate
              </button>
            </div>
          {/if}
        </div>
      {:else}
        <p class="empty-text">No items in the moderation queue</p>
      {/each}
    </div>
  {/if}
</div>

<Modal bind:open={rejectModalOpen} title="Reject Item">
  {#if rejectTarget}
    <p class="confirm-text">Reject this {rejectTarget.type} item?</p>
    <div class="form-group">
      <label class="form-label" for="reject-reason">Reason (optional)</label>
      <textarea
        id="reject-reason"
        class="textarea"
        bind:value={rejectReason}
        placeholder="Reason for rejection..."
        rows="3"
      ></textarea>
    </div>
    <div class="modal-actions">
      <button class="btn btn-ghost" type="button" onclick={() => (rejectModalOpen = false)}>Cancel</button>
      <button class="btn btn-danger" type="button" onclick={handleReject}>Reject</button>
    </div>
  {/if}
</Modal>

<style>
  .queue-page {
    max-width: 1100px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-6);
  }

  .stats-bar {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: var(--space-4);
    margin-block-end: var(--space-6);
  }

  .stat-item {
    text-align: center;
    padding: var(--space-4);
  }

  .stat-label {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-1);
  }

  .stat-value {
    font-size: var(--text-2xl);
    font-weight: 700;
  }

  .stat-success { color: var(--color-success); }
  .stat-danger { color: var(--color-danger); }
  .stat-warning { color: var(--color-warning); }

  .toolbar {
    display: flex;
    gap: var(--space-2);
    margin-block-end: var(--space-4);
    flex-wrap: wrap;
  }

  .loading-area {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .list-items {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .queue-item {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .queue-item-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: var(--space-2);
  }

  .queue-item-meta {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .queue-item-date {
    font-size: var(--text-xs);
  }

  .queue-item-content {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .content-preview {
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: 1.5;
  }

  .queue-item-source {
    font-size: var(--text-xs);
  }

  .queue-item-reason {
    font-size: var(--text-xs);
    font-style: italic;
  }

  .badge-type {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    background: var(--color-info-soft);
    color: #1e40af;
    text-transform: capitalize;
  }

  .severity-badge {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    text-transform: capitalize;
  }

  .severity-critical {
    background: var(--color-danger-soft);
    color: #991b1b;
  }

  .severity-high {
    background: var(--color-warning-soft);
    color: #92400e;
  }

  .severity-medium {
    background: var(--color-info-soft);
    color: #1e40af;
  }

  .severity-low {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }

  .status-badge {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    text-transform: capitalize;
  }

  .status-pending {
    background: var(--color-warning-soft);
    color: #92400e;
  }

  .status-approved {
    background: var(--color-success-soft);
    color: #166534;
  }

  .status-rejected {
    background: var(--color-danger-soft);
    color: #991b1b;
  }

  .status-escalated {
    background: var(--color-info-soft);
    color: #1e40af;
  }

  .action-buttons {
    display: flex;
    gap: var(--space-2);
  }

  .form-group {
    margin-block-end: var(--space-4);
  }

  .form-label {
    display: block;
    font-size: var(--text-sm);
    font-weight: 600;
    margin-block-end: var(--space-1);
    color: var(--color-text);
  }

  .modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    margin-block-start: var(--space-4);
  }

  .confirm-text {
    font-size: var(--text-sm);
    margin-block-end: var(--space-3);
  }

  .empty-text {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    text-align: center;
    padding: var(--space-6) 0;
  }

  @media (max-width: 768px) {
    .stats-bar {
      grid-template-columns: repeat(2, 1fr);
    }

    .toolbar {
      flex-direction: column;
    }

    .toolbar .input {
      width: 100% !important;
    }
  }
</style>
