<script lang="ts">
  import { onMount } from 'svelte';
  import DataTable from '$lib/components/admin/DataTable.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import {
    getAdminUsers, suspendUser, unsuspendUser, warnUser,
    silenceUser, unsilenceUser, shadowBanUser, unshadowBanUser,
    forceSensitiveUser, unforceSensitiveUser, revokeAllSessions,
    setTrustLevel, getModerationNotes, createModerationNote, deleteModerationNote
  } from '$lib/api/admin.js';
  import type { AdminUser, ModerationNote } from '$lib/api/types.js';

  let users: AdminUser[] = $state([]);
  let loading = $state(true);
  let search = $state('');
  let statusFilter = $state('all');
  let sortKey = $state('created_at');
  let sortDir = $state<'asc' | 'desc'>('desc');

  // Warn modal
  let warnModalOpen = $state(false);
  let warnTarget: AdminUser | null = $state(null);
  let warnMessage = $state('');

  // Action confirmation modal
  let actionModalOpen = $state(false);
  let actionTarget: AdminUser | null = $state(null);
  let actionType = $state('');
  let actionReason = $state('');
  let actionSubmitting = $state(false);

  // Trust level modal
  let trustModalOpen = $state(false);
  let trustTarget: AdminUser | null = $state(null);
  let trustLevel = $state(0);

  // Moderation notes modal
  let notesModalOpen = $state(false);
  let notesTarget: AdminUser | null = $state(null);
  let notes: ModerationNote[] = $state([]);
  let notesLoading = $state(false);
  let newNote = $state('');

  // Actions dropdown
  let openDropdownId: string | null = $state(null);

  const columns = [
    { key: 'handle', label: 'Handle', sortable: true },
    { key: 'email', label: 'Email', sortable: true },
    { key: 'created_at', label: 'Created', sortable: true },
    { key: 'status', label: 'Status', sortable: true },
    { key: 'flags', label: 'Flags' },
    { key: 'trust_level', label: 'Trust', sortable: true },
    { key: 'actions', label: 'Actions', width: '220px' }
  ];

  let filteredUsers = $derived(
    users.filter((u) => {
      const matchesSearch =
        !search ||
        u.handle.toLowerCase().includes(search.toLowerCase()) ||
        u.email.toLowerCase().includes(search.toLowerCase());
      const matchesStatus = statusFilter === 'all' || u.status === statusFilter;
      return matchesSearch && matchesStatus;
    })
  );

  let sortedUsers = $derived(
    [...filteredUsers].sort((a, b) => {
      const aVal = a[sortKey as keyof AdminUser] ?? '';
      const bVal = b[sortKey as keyof AdminUser] ?? '';
      const cmp = String(aVal).localeCompare(String(bVal));
      return sortDir === 'asc' ? cmp : -cmp;
    })
  );

  let tableRows = $derived(
    sortedUsers.map((u) => ({ ...u } as Record<string, unknown>))
  );

  onMount(async () => {
    await loadUsers();
  });

  async function loadUsers() {
    loading = true;
    try {
      const result = await getAdminUsers();
      users = result.data;
    } catch {
      addToast('Failed to load users', 'error');
    } finally {
      loading = false;
    }
  }

  async function handleSuspend(user: AdminUser) {
    try {
      await suspendUser(user.id);
      user.status = 'suspended';
      users = [...users];
      addToast(`Suspended @${user.handle}`, 'success');
    } catch {
      addToast('Failed to suspend user', 'error');
    }
  }

  async function handleUnsuspend(user: AdminUser) {
    try {
      await unsuspendUser(user.id);
      user.status = 'active';
      users = [...users];
      addToast(`Unsuspended @${user.handle}`, 'success');
    } catch {
      addToast('Failed to unsuspend user', 'error');
    }
  }

  function openWarnModal(user: AdminUser) {
    warnTarget = user;
    warnMessage = '';
    warnModalOpen = true;
    openDropdownId = null;
  }

  async function handleWarn() {
    if (!warnTarget || !warnMessage.trim()) return;
    try {
      await warnUser(warnTarget.id, warnMessage);
      addToast(`Warning sent to @${warnTarget.handle}`, 'success');
      warnModalOpen = false;
    } catch {
      addToast('Failed to send warning', 'error');
    }
  }

  function openActionModal(user: AdminUser, type: string) {
    actionTarget = user;
    actionType = type;
    actionReason = '';
    actionModalOpen = true;
    openDropdownId = null;
  }

  async function handleAction() {
    if (!actionTarget) return;
    actionSubmitting = true;
    try {
      let updated: AdminUser;
      switch (actionType) {
        case 'silence':
          updated = await silenceUser(actionTarget.id, { reason: actionReason || undefined });
          updated.silenced = true;
          break;
        case 'unsilence':
          updated = await unsilenceUser(actionTarget.id);
          updated.silenced = false;
          break;
        case 'shadow_ban':
          updated = await shadowBanUser(actionTarget.id);
          updated.shadow_banned = true;
          break;
        case 'unshadow_ban':
          updated = await unshadowBanUser(actionTarget.id);
          updated.shadow_banned = false;
          break;
        case 'force_sensitive':
          updated = await forceSensitiveUser(actionTarget.id);
          updated.force_sensitive = true;
          break;
        case 'unforce_sensitive':
          updated = await unforceSensitiveUser(actionTarget.id);
          updated.force_sensitive = false;
          break;
        case 'revoke_sessions':
          await revokeAllSessions(actionTarget.id);
          updated = actionTarget;
          break;
        default:
          return;
      }
      users = users.map((u) => (u.id === actionTarget!.id ? { ...u, ...updated } : u));
      actionModalOpen = false;
      addToast(`${actionLabel(actionType)} applied to @${actionTarget.handle}`, 'success');
    } catch {
      addToast(`Failed to ${actionType.replace(/_/g, ' ')} user`, 'error');
    } finally {
      actionSubmitting = false;
    }
  }

  function actionLabel(type: string): string {
    switch (type) {
      case 'silence': return 'Silence';
      case 'unsilence': return 'Unsilence';
      case 'shadow_ban': return 'Shadow Ban';
      case 'unshadow_ban': return 'Unshadow Ban';
      case 'force_sensitive': return 'Force Sensitive';
      case 'unforce_sensitive': return 'Unforce Sensitive';
      case 'revoke_sessions': return 'Revoke Sessions';
      default: return type;
    }
  }

  function openTrustModal(user: AdminUser) {
    trustTarget = user;
    trustLevel = user.trust_level ?? 0;
    trustModalOpen = true;
    openDropdownId = null;
  }

  async function handleSetTrustLevel() {
    if (!trustTarget) return;
    try {
      const updated = await setTrustLevel(trustTarget.id, trustLevel);
      users = users.map((u) => (u.id === trustTarget!.id ? { ...u, trust_level: updated.trust_level } : u));
      trustModalOpen = false;
      addToast(`Trust level set to ${trustLevel} for @${trustTarget.handle}`, 'success');
    } catch {
      addToast('Failed to set trust level', 'error');
    }
  }

  async function openNotesModal(user: AdminUser) {
    notesTarget = user;
    notes = [];
    newNote = '';
    notesModalOpen = true;
    openDropdownId = null;
    notesLoading = true;
    try {
      notes = await getModerationNotes(user.id);
    } catch {
      addToast('Failed to load notes', 'error');
    } finally {
      notesLoading = false;
    }
  }

  async function handleAddNote() {
    if (!notesTarget || !newNote.trim()) return;
    try {
      const note = await createModerationNote(notesTarget.id, newNote);
      notes = [...notes, note];
      newNote = '';
      addToast('Note added', 'success');
    } catch {
      addToast('Failed to add note', 'error');
    }
  }

  async function handleDeleteNote(id: string) {
    try {
      await deleteModerationNote(id);
      notes = notes.filter((n) => n.id !== id);
      addToast('Note deleted', 'success');
    } catch {
      addToast('Failed to delete note', 'error');
    }
  }

  function toggleDropdown(userId: string) {
    openDropdownId = openDropdownId === userId ? null : userId;
  }

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    });
  }

  function statusClass(status: string): string {
    switch (status) {
      case 'active': return 'status-active';
      case 'suspended': return 'status-suspended';
      case 'pending': return 'status-pending';
      default: return '';
    }
  }
</script>

<svelte:head>
  <title>Users - Admin</title>
</svelte:head>

<div class="users-page">
  <h1 class="page-title">Users</h1>

  <div class="toolbar">
    <div class="search-bar">
      <input
        type="search"
        class="input"
        placeholder="Search users..."
        bind:value={search}
      />
    </div>
    <select class="input status-select" bind:value={statusFilter}>
      <option value="all">All Statuses</option>
      <option value="active">Active</option>
      <option value="suspended">Suspended</option>
      <option value="pending">Pending</option>
    </select>
  </div>

  <DataTable
    {columns}
    rows={tableRows}
    bind:sortKey
    bind:sortDir
    {loading}
    emptyMessage="No users found"
  >
    {#snippet rowContent(row)}
      <td>
        <div class="user-cell">
          <span class="user-handle">@{row['handle']}</span>
          {#if row['display_name']}
            <span class="user-display">{row['display_name']}</span>
          {/if}
        </div>
      </td>
      <td>{row['email']}</td>
      <td>{formatDate(row['created_at'] as string)}</td>
      <td>
        <span class="status-badge {statusClass(row['status'] as string)}">
          {row['status']}
        </span>
      </td>
      <td>
        <div class="flag-badges">
          {#if row['silenced']}
            <span class="flag-badge flag-silenced">silenced</span>
          {/if}
          {#if row['shadow_banned']}
            <span class="flag-badge flag-shadow">shadow banned</span>
          {/if}
          {#if row['force_sensitive']}
            <span class="flag-badge flag-sensitive">force sensitive</span>
          {/if}
        </div>
      </td>
      <td>
        <span class="trust-level">Lv {row['trust_level'] ?? 0}</span>
      </td>
      <td>
        <div class="action-buttons">
          {#if row['status'] === 'suspended'}
            <button
              class="btn btn-sm btn-outline"
              type="button"
              onclick={() => handleUnsuspend(row as unknown as AdminUser)}
            >Unsuspend</button>
          {:else}
            <button
              class="btn btn-sm btn-danger"
              type="button"
              onclick={() => handleSuspend(row as unknown as AdminUser)}
            >Suspend</button>
          {/if}
          <div class="dropdown">
            <button
              class="btn btn-sm btn-ghost"
              type="button"
              onclick={() => toggleDropdown(row['id'] as string)}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                <circle cx="12" cy="5" r="2" />
                <circle cx="12" cy="12" r="2" />
                <circle cx="12" cy="19" r="2" />
              </svg>
            </button>
            {#if openDropdownId === row['id']}
              <div class="dropdown-menu">
                <button class="dropdown-item" type="button" onclick={() => openWarnModal(row as unknown as AdminUser)}>
                  Warn
                </button>
                {#if row['silenced']}
                  <button class="dropdown-item" type="button" onclick={() => openActionModal(row as unknown as AdminUser, 'unsilence')}>
                    Unsilence
                  </button>
                {:else}
                  <button class="dropdown-item" type="button" onclick={() => openActionModal(row as unknown as AdminUser, 'silence')}>
                    Silence
                  </button>
                {/if}
                {#if row['shadow_banned']}
                  <button class="dropdown-item" type="button" onclick={() => openActionModal(row as unknown as AdminUser, 'unshadow_ban')}>
                    Unshadow Ban
                  </button>
                {:else}
                  <button class="dropdown-item" type="button" onclick={() => openActionModal(row as unknown as AdminUser, 'shadow_ban')}>
                    Shadow Ban
                  </button>
                {/if}
                {#if row['force_sensitive']}
                  <button class="dropdown-item" type="button" onclick={() => openActionModal(row as unknown as AdminUser, 'unforce_sensitive')}>
                    Unforce Sensitive
                  </button>
                {:else}
                  <button class="dropdown-item" type="button" onclick={() => openActionModal(row as unknown as AdminUser, 'force_sensitive')}>
                    Force Sensitive
                  </button>
                {/if}
                <button class="dropdown-item" type="button" onclick={() => openActionModal(row as unknown as AdminUser, 'revoke_sessions')}>
                  Revoke Sessions
                </button>
                <button class="dropdown-item" type="button" onclick={() => openTrustModal(row as unknown as AdminUser)}>
                  Set Trust Level
                </button>
                <hr class="dropdown-divider" />
                <button class="dropdown-item" type="button" onclick={() => openNotesModal(row as unknown as AdminUser)}>
                  Moderation Notes
                </button>
              </div>
            {/if}
          </div>
        </div>
      </td>
    {/snippet}
  </DataTable>
</div>

<!-- Warn Modal -->
<Modal bind:open={warnModalOpen} title="Warn User">
  {#if warnTarget}
    <p class="modal-text">Send a warning to <strong>@{warnTarget.handle}</strong></p>
    <textarea
      class="textarea"
      bind:value={warnMessage}
      placeholder="Warning message..."
      rows="4"
    ></textarea>
    <div class="modal-actions">
      <button class="btn btn-ghost" type="button" onclick={() => (warnModalOpen = false)}>Cancel</button>
      <button
        class="btn btn-primary"
        type="button"
        disabled={!warnMessage.trim()}
        onclick={handleWarn}
      >Send Warning</button>
    </div>
  {/if}
</Modal>

<!-- Action Confirmation Modal -->
<Modal bind:open={actionModalOpen} title="{actionLabel(actionType)} User">
  {#if actionTarget}
    <p class="modal-text">
      Apply <strong>{actionLabel(actionType)}</strong> to <strong>@{actionTarget.handle}</strong>?
    </p>
    {#if actionType === 'silence' || actionType === 'shadow_ban' || actionType === 'force_sensitive'}
      <div class="form-group">
        <label class="form-label" for="action-reason">Reason (optional)</label>
        <textarea
          id="action-reason"
          class="textarea"
          bind:value={actionReason}
          placeholder="Reason..."
          rows="3"
        ></textarea>
      </div>
    {/if}
    <div class="modal-actions">
      <button class="btn btn-ghost" type="button" onclick={() => (actionModalOpen = false)}>Cancel</button>
      <button
        class="btn btn-primary"
        type="button"
        disabled={actionSubmitting}
        onclick={handleAction}
      >
        {actionSubmitting ? 'Applying...' : 'Confirm'}
      </button>
    </div>
  {/if}
</Modal>

<!-- Trust Level Modal -->
<Modal bind:open={trustModalOpen} title="Set Trust Level">
  {#if trustTarget}
    <p class="modal-text">Set trust level for <strong>@{trustTarget.handle}</strong></p>
    <div class="form-group">
      <label class="form-label" for="trust-level">Trust Level (0-4)</label>
      <input
        id="trust-level"
        class="input"
        type="number"
        min="0"
        max="4"
        bind:value={trustLevel}
      />
    </div>
    <div class="modal-actions">
      <button class="btn btn-ghost" type="button" onclick={() => (trustModalOpen = false)}>Cancel</button>
      <button class="btn btn-primary" type="button" onclick={handleSetTrustLevel}>Set Level</button>
    </div>
  {/if}
</Modal>

<!-- Moderation Notes Modal -->
<Modal bind:open={notesModalOpen} title="Moderation Notes">
  {#if notesTarget}
    <p class="modal-text">Notes for <strong>@{notesTarget.handle}</strong></p>

    <form class="notes-add-form" onsubmit={(e) => { e.preventDefault(); handleAddNote(); }}>
      <textarea
        class="textarea"
        bind:value={newNote}
        placeholder="Add a moderation note..."
        rows="2"
      ></textarea>
      <button class="btn btn-sm btn-primary" type="submit" disabled={!newNote.trim()}>Add Note</button>
    </form>

    {#if notesLoading}
      <div class="skeleton" style="height: 40px; margin-top: var(--space-3)"></div>
    {:else}
      <div class="notes-list">
        {#each notes as note (note.id)}
          <div class="note-item">
            <div class="note-content">{note.content}</div>
            <div class="note-meta">
              <span class="text-secondary">@{note.author.handle} - {formatDate(note.created_at)}</span>
              <button
                class="btn btn-sm btn-ghost btn-danger-text"
                type="button"
                onclick={() => handleDeleteNote(note.id)}
              >Delete</button>
            </div>
          </div>
        {:else}
          <p class="empty-text">No moderation notes</p>
        {/each}
      </div>
    {/if}
  {/if}
</Modal>

<style>
  .users-page {
    max-width: 1200px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-6);
  }

  .toolbar {
    display: flex;
    gap: var(--space-3);
    margin-block-end: var(--space-4);
  }

  .search-bar {
    flex: 1;
    max-width: 400px;
  }

  .status-select {
    width: 160px;
  }

  .user-cell {
    display: flex;
    flex-direction: column;
  }

  .user-handle {
    font-weight: 600;
  }

  .user-display {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
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

  .status-suspended {
    background: var(--color-danger-soft);
    color: #991b1b;
  }

  .status-pending {
    background: var(--color-warning-soft);
    color: #92400e;
  }

  .flag-badges {
    display: flex;
    flex-wrap: wrap;
    gap: 2px;
  }

  .flag-badge {
    font-size: 10px;
    font-weight: 600;
    padding: 1px var(--space-1);
    border-radius: var(--radius-sm);
    text-transform: uppercase;
    white-space: nowrap;
  }

  .flag-silenced {
    background: var(--color-warning-soft);
    color: #92400e;
  }

  .flag-shadow {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }

  .flag-sensitive {
    background: var(--color-info-soft);
    color: #1e40af;
  }

  .trust-level {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
  }

  .action-buttons {
    display: flex;
    gap: var(--space-2);
    align-items: center;
  }

  .dropdown {
    position: relative;
  }

  .dropdown-menu {
    position: absolute;
    top: 100%;
    right: 0;
    z-index: var(--z-dropdown, 50);
    min-width: 180px;
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow-lg);
    padding: var(--space-1);
  }

  .dropdown-item {
    display: block;
    width: 100%;
    padding: var(--space-2) var(--space-3);
    border: none;
    background: none;
    font-size: var(--text-sm);
    color: var(--color-text);
    text-align: left;
    cursor: pointer;
    border-radius: var(--radius-sm);
    transition: background var(--transition-fast);
  }

  .dropdown-item:hover {
    background: var(--color-surface);
  }

  .dropdown-divider {
    margin: var(--space-1) 0;
    border: none;
    border-top: 1px solid var(--color-border);
  }

  .modal-text {
    margin-block-end: var(--space-3);
    font-size: var(--text-sm);
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

  .notes-add-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin-block-end: var(--space-4);
  }

  .notes-add-form .btn {
    align-self: flex-end;
  }

  .notes-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .note-item {
    border-block-end: 1px solid var(--color-border);
    padding-block-end: var(--space-3);
  }

  .note-content {
    font-size: var(--text-sm);
    margin-block-end: var(--space-1);
  }

  .note-meta {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: var(--text-xs);
  }

  .btn-danger-text {
    color: var(--color-danger);
  }

  .empty-text {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    text-align: center;
    padding: var(--space-4) 0;
  }

  @media (max-width: 768px) {
    .toolbar {
      flex-direction: column;
    }

    .search-bar {
      max-width: none;
    }

    .status-select {
      width: 100%;
    }
  }
</style>
