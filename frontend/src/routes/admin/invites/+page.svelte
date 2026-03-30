<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import Modal from '$lib/components/ui/Modal.svelte';
  import { getInvites, createInvite, deleteInvite } from '$lib/api/admin.js';
  import type { InviteCode } from '$lib/api/types.js';

  let invites: InviteCode[] = $state([]);
  let loading = $state(true);

  // Create form
  let createModalOpen = $state(false);
  let newMaxUses = $state('');
  let newExpiresAt = $state('');
  let creating = $state(false);

  // Delete confirmation
  let deleteTarget: InviteCode | null = $state(null);
  let deleteModalOpen = $state(false);

  onMount(async () => {
    await loadInvites();
  });

  async function loadInvites() {
    loading = true;
    try {
      invites = await getInvites();
    } catch {
      addToast('Failed to load invite codes', 'error');
    } finally {
      loading = false;
    }
  }

  function openCreateModal() {
    newMaxUses = '';
    newExpiresAt = '';
    createModalOpen = true;
  }

  async function handleCreate() {
    creating = true;
    try {
      const params: { max_uses?: number; expires_at?: string } = {};
      if (newMaxUses) params.max_uses = parseInt(newMaxUses, 10);
      if (newExpiresAt) params.expires_at = new Date(newExpiresAt).toISOString();
      const invite = await createInvite(params);
      invites = [invite, ...invites];
      createModalOpen = false;
      addToast('Invite code created', 'success');
    } catch {
      addToast('Failed to create invite code', 'error');
    } finally {
      creating = false;
    }
  }

  function confirmDelete(invite: InviteCode) {
    deleteTarget = invite;
    deleteModalOpen = true;
  }

  async function handleDelete() {
    if (!deleteTarget) return;
    try {
      await deleteInvite(deleteTarget.id);
      invites = invites.filter((i) => i.id !== deleteTarget!.id);
      deleteModalOpen = false;
      addToast('Invite code deleted', 'success');
    } catch {
      addToast('Failed to delete invite code', 'error');
    }
  }

  async function copyCode(code: string) {
    try {
      await navigator.clipboard.writeText(code);
      addToast('Code copied to clipboard', 'success');
    } catch {
      addToast('Failed to copy code', 'error');
    }
  }

  function formatDate(iso: string | null): string {
    if (!iso) return 'Never';
    return new Date(iso).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  }

  function statusClass(status: string): string {
    switch (status) {
      case 'active': return 'status-active';
      case 'expired': return 'status-expired';
      case 'disabled': return 'status-disabled';
      default: return '';
    }
  }
</script>

<svelte:head>
  <title>Invite Codes - Admin</title>
</svelte:head>

<div class="invites-page">
  <div class="page-header">
    <h1 class="page-title">Invite Codes</h1>
    <button class="btn btn-primary" type="button" onclick={openCreateModal}>
      Create Invite
    </button>
  </div>

  {#if loading}
    <div class="loading-area">
      <div class="skeleton" style="height: 60px"></div>
      <div class="skeleton" style="height: 60px"></div>
    </div>
  {:else}
    <div class="list-items">
      {#each invites as invite (invite.id)}
        <div class="list-item card">
          <div class="invite-info">
            <div class="invite-code-row">
              <code class="invite-code">{invite.code}</code>
              <button
                class="btn btn-sm btn-ghost copy-btn"
                type="button"
                onclick={() => copyCode(invite.code)}
                title="Copy to clipboard"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
                  <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"></path>
                </svg>
              </button>
              <span class="status-badge {statusClass(invite.status)}">{invite.status}</span>
            </div>
            <div class="invite-meta text-secondary">
              <span>Uses: {invite.uses}{invite.max_uses ? `/${invite.max_uses}` : ' (unlimited)'}</span>
              <span>Expires: {invite.expires_at ? formatDate(invite.expires_at) : 'Never'}</span>
              <span>Created: {formatDate(invite.created_at)}</span>
              {#if invite.created_by}
                <span>By: @{typeof invite.created_by === 'string' ? invite.created_by : invite.created_by.handle || invite.created_by}</span>
              {/if}
            </div>
          </div>
          <button
            class="btn btn-sm btn-danger"
            type="button"
            onclick={() => confirmDelete(invite)}
          >Delete</button>
        </div>
      {:else}
        <p class="empty-text">No invite codes</p>
      {/each}
    </div>
  {/if}
</div>

<Modal bind:open={createModalOpen} title="Create Invite Code">
  <form onsubmit={(e) => { e.preventDefault(); handleCreate(); }}>
    <div class="form-group">
      <label class="form-label" for="invite-max-uses">Max Uses (optional)</label>
      <input
        id="invite-max-uses"
        class="input"
        type="number"
        min="1"
        bind:value={newMaxUses}
        placeholder="Unlimited"
      />
    </div>
    <div class="form-group">
      <label class="form-label" for="invite-expires">Expires At (optional)</label>
      <input
        id="invite-expires"
        class="input"
        type="datetime-local"
        bind:value={newExpiresAt}
      />
    </div>
    <div class="modal-actions">
      <button class="btn btn-ghost" type="button" onclick={() => (createModalOpen = false)}>Cancel</button>
      <button class="btn btn-primary" type="submit" disabled={creating}>
        {creating ? 'Creating...' : 'Create'}
      </button>
    </div>
  </form>
</Modal>

<Modal bind:open={deleteModalOpen} title="Delete Invite Code">
  {#if deleteTarget}
    <p class="confirm-text">Are you sure you want to delete invite code <code>{deleteTarget.code}</code>?</p>
    <div class="modal-actions">
      <button class="btn btn-ghost" type="button" onclick={() => (deleteModalOpen = false)}>Cancel</button>
      <button class="btn btn-danger" type="button" onclick={handleDelete}>Delete</button>
    </div>
  {/if}
</Modal>

<style>
  .invites-page {
    max-width: 1100px;
  }

  .page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-end: var(--space-6);
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
  }

  .loading-area {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .list-items {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .list-item {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-3);
  }

  .invite-info {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    min-width: 0;
  }

  .invite-code-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .invite-code {
    font-size: var(--text-sm);
    font-weight: 600;
    background: var(--color-surface);
    padding: 2px var(--space-2);
    border-radius: var(--radius-sm);
    letter-spacing: 0.05em;
  }

  .copy-btn {
    padding: var(--space-1);
  }

  .invite-meta {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-3);
    font-size: var(--text-xs);
  }

  .status-badge {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    text-transform: capitalize;
  }

  .status-active {
    background: var(--color-success-soft);
    color: #166534;
  }

  .status-expired {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }

  .status-disabled {
    background: var(--color-danger-soft);
    color: #991b1b;
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
    margin-block-end: var(--space-2);
  }

  .empty-text {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    text-align: center;
    padding: var(--space-6) 0;
  }
</style>
