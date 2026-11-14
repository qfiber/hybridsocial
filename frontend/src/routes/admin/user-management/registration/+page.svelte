<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import Modal from '$lib/components/ui/Modal.svelte';
  import { getInvites, createInvite, deleteInvite, getAdminSettings } from '$lib/api/admin.js';
  import { t } from '$lib/stores/i18n.js';
  import type { InviteCode } from '$lib/api/types.js';

  // Registration mode is a config-backed setting: open | invite_only |
  // approval | closed. Lives on this page because invite_only is the
  // only mode where the codes below are mandatory — putting the toggle
  // anywhere else leaves admins hunting for it.
  type RegMode = 'open' | 'invite_only' | 'approval' | 'closed';
  let registrationMode = $state<RegMode>('open');
  let regModeLoading = $state(true);

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
    await Promise.all([loadInvites(), loadRegistrationMode()]);
  });

  async function loadRegistrationMode() {
    regModeLoading = true;
    try {
      const all = await getAdminSettings();
      const setting = all.find((s) => s.key === 'registration_mode');
      const v = (setting?.value ?? 'open') as RegMode;
      if (['open', 'invite_only', 'approval', 'closed'].includes(v)) registrationMode = v;
    } catch {
      // Non-fatal: default to "open" so the UI still renders.
    } finally {
      regModeLoading = false;
    }
  }

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

  function inviteLink(code: string): string {
    const base = typeof window !== 'undefined' ? window.location.origin : '';
    return `${base}/register?invite=${encodeURIComponent(code)}`;
  }

  async function copyCode(code: string) {
    try {
      await navigator.clipboard.writeText(inviteLink(code));
      addToast('Invite link copied', 'success');
    } catch {
      addToast('Failed to copy link', 'error');
    }
  }

  async function copyRawCode(code: string, e: MouseEvent) {
    e.stopPropagation();
    try {
      await navigator.clipboard.writeText(code);
      addToast('Raw code copied', 'success');
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
  <title>{$t('admin_invites.title')} - Admin</title>
</svelte:head>

<div class="invites-page">
  <div class="page-header">
    <h1 class="page-title">{$t('admin_invites.title')}</h1>
    {#if registrationMode === 'invite_only'}
      <button class="btn btn-primary" type="button" onclick={openCreateModal}>
        Create invite code
      </button>
    {/if}
  </div>

  {#if registrationMode !== 'invite_only'}
    <!-- Invite codes are only meaningful when registration is gated by
         them. In open / approval / closed modes the list is hidden and
         a one-line note explains why, instead of showing a dead UI. -->
    <section class="card invite-mode-note">
      <p>
        {$t('admin_invites.mode_note')}
        <a href="/admin/settings/access">{$t('admin_invites.mode_link')}</a>
      </p>
    </section>
  {:else if loading}
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
              <code class="invite-code" title="Raw code — click icon to copy" onclick={(e) => copyRawCode(invite.code, e)}>{invite.code}</code>
              <button
                class="btn btn-sm btn-ghost copy-btn"
                type="button"
                onclick={() => copyCode(invite.code)}
                title="Copy registration link — share this with the invitee"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"></path>
                  <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"></path>
                </svg>
                Copy link
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

  .invite-mode-note {
    padding: var(--space-4);
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
    line-height: 1.5;
  }

  .invite-mode-note p {
    margin: 0;
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
    color: var(--color-on-success-soft);
  }

  .status-expired {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }

  .status-disabled {
    background: var(--color-danger-soft);
    color: var(--color-on-danger-soft);
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
