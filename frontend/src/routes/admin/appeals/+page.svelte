<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import Modal from '$lib/components/ui/Modal.svelte';
  import { getAppeals, approveAppeal, rejectAppeal } from '$lib/api/admin.js';
  import type { Appeal } from '$lib/api/types.js';

  const statusTabs = [
    { id: 'pending', label: 'Pending' },
    { id: 'approved', label: 'Approved' },
    { id: 'rejected', label: 'Rejected' }
  ];

  let appeals: Appeal[] = $state([]);
  let loading = $state(true);
  let activeStatus = $state('pending');

  let filteredAppeals = $derived(
    appeals.filter((a) => a.status === activeStatus)
  );

  // Response modal
  let responseModalOpen = $state(false);
  let responseAction = $state<'approve' | 'reject'>('approve');
  let responseTarget: Appeal | null = $state(null);
  let responseText = $state('');
  let submitting = $state(false);

  onMount(async () => {
    await loadAppeals();
  });

  async function loadAppeals() {
    loading = true;
    try {
      appeals = await getAppeals();
    } catch {
      addToast('Failed to load appeals', 'error');
    } finally {
      loading = false;
    }
  }

  function openResponseModal(appeal: Appeal, action: 'approve' | 'reject') {
    responseTarget = appeal;
    responseAction = action;
    responseText = '';
    responseModalOpen = true;
  }

  async function handleSubmitResponse() {
    if (!responseTarget) return;
    submitting = true;
    try {
      let updated: Appeal;
      if (responseAction === 'approve') {
        updated = await approveAppeal(responseTarget.id, responseText || undefined);
      } else {
        updated = await rejectAppeal(responseTarget.id, responseText || undefined);
      }
      appeals = appeals.map((a) => (a.id === updated.id ? updated : a));
      responseModalOpen = false;
      addToast(`Appeal ${responseAction === 'approve' ? 'approved' : 'rejected'}`, 'success');
    } catch {
      addToast(`Failed to ${responseAction} appeal`, 'error');
    } finally {
      submitting = false;
    }
  }

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  }
</script>

<svelte:head>
  <title>Appeals - Admin</title>
</svelte:head>

<div class="appeals-page">
  <h1 class="page-title">Appeals</h1>

  <div class="tabs-list" role="tablist">
    {#each statusTabs as tab (tab.id)}
      <button
        class="tab-item"
        class:active={activeStatus === tab.id}
        role="tab"
        aria-selected={activeStatus === tab.id}
        onclick={() => (activeStatus = tab.id)}
        type="button"
      >
        {tab.label}
        {#if tab.id === 'pending'}
          {@const count = appeals.filter((a) => a.status === 'pending').length}
          {#if count > 0}
            <span class="tab-count">{count}</span>
          {/if}
        {/if}
      </button>
    {/each}
  </div>

  {#if loading}
    <div class="loading-area">
      <div class="skeleton" style="height: 80px"></div>
      <div class="skeleton" style="height: 80px"></div>
    </div>
  {:else}
    <div class="list-items">
      {#each filteredAppeals as appeal (appeal.id)}
        <div class="appeal-card card">
          <div class="appeal-header">
            <div class="appeal-user">
              <strong>@{appeal.user.handle}</strong>
              <span class="badge-type">{appeal.action_type.replace(/_/g, ' ')}</span>
              <span class="status-badge status-{appeal.status}">{appeal.status}</span>
            </div>
            <span class="appeal-date text-secondary">{formatDate(appeal.submitted_at)}</span>
          </div>
          <div class="appeal-reason">
            <p>{appeal.reason}</p>
          </div>
          {#if appeal.response}
            <div class="appeal-response">
              <strong>Response:</strong> {appeal.response}
            </div>
          {/if}
          {#if appeal.status === 'pending'}
            <div class="action-buttons">
              <button
                class="btn btn-sm btn-primary"
                type="button"
                onclick={() => openResponseModal(appeal, 'approve')}
              >Approve</button>
              <button
                class="btn btn-sm btn-danger"
                type="button"
                onclick={() => openResponseModal(appeal, 'reject')}
              >Reject</button>
            </div>
          {/if}
        </div>
      {:else}
        <p class="empty-text">No {activeStatus} appeals</p>
      {/each}
    </div>
  {/if}
</div>

<Modal bind:open={responseModalOpen} title="{responseAction === 'approve' ? 'Approve' : 'Reject'} Appeal">
  {#if responseTarget}
    <p class="confirm-text">
      {responseAction === 'approve' ? 'Approve' : 'Reject'} appeal from <strong>@{responseTarget.user.handle}</strong>
    </p>
    <div class="form-group">
      <label class="form-label" for="response-text">Response (optional)</label>
      <textarea
        id="response-text"
        class="textarea"
        bind:value={responseText}
        placeholder="Provide a response to the user..."
        rows="4"
      ></textarea>
    </div>
    <div class="modal-actions">
      <button class="btn btn-ghost" type="button" onclick={() => (responseModalOpen = false)}>Cancel</button>
      <button
        class="btn {responseAction === 'approve' ? 'btn-primary' : 'btn-danger'}"
        type="button"
        disabled={submitting}
        onclick={handleSubmitResponse}
      >
        {submitting ? 'Submitting...' : responseAction === 'approve' ? 'Approve' : 'Reject'}
      </button>
    </div>
  {/if}
</Modal>

<style>
  .appeals-page {
    max-width: 1100px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-6);
  }

  .tabs-list {
    display: flex;
    border-block-end: 1px solid var(--color-border);
    gap: 0;
    margin-block-end: var(--space-4);
  }

  .tab-item {
    position: relative;
    padding: var(--space-3) var(--space-4);
    border: none;
    background: none;
    font-size: var(--text-sm);
    font-weight: var(--font-medium);
    color: var(--color-text-secondary);
    cursor: pointer;
    white-space: nowrap;
    display: flex;
    align-items: center;
    gap: var(--space-2);
    transition: color var(--transition-fast);
  }

  .tab-item:hover {
    color: var(--color-text);
  }

  .tab-item.active {
    color: var(--color-primary);
  }

  .tab-item.active::after {
    content: '';
    position: absolute;
    inset-inline: 0;
    bottom: -1px;
    height: 2px;
    background-color: var(--color-primary);
    border-radius: var(--radius-full) var(--radius-full) 0 0;
  }

  .tab-count {
    font-size: var(--text-xs);
    font-weight: 700;
    background: var(--color-danger);
    color: white;
    padding: 0 6px;
    border-radius: var(--radius-full);
    min-width: 18px;
    text-align: center;
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

  .appeal-card {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .appeal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: var(--space-2);
  }

  .appeal-user {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-wrap: wrap;
  }

  .appeal-date {
    font-size: var(--text-xs);
  }

  .appeal-reason {
    font-size: var(--text-sm);
    color: var(--color-text);
    background: var(--color-surface);
    padding: var(--space-3);
    border-radius: var(--radius-md);
  }

  .appeal-response {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    padding: var(--space-3);
    border-inline-start: 3px solid var(--color-border);
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

  .badge-type {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    background: var(--color-info-soft);
    color: #1e40af;
    text-transform: capitalize;
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
</style>
