<script lang="ts">
  import { onMount } from 'svelte';
  import DataTable from '$lib/components/admin/DataTable.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getAdminUsers, suspendUser, unsuspendUser, warnUser } from '$lib/api/admin.js';
  import type { AdminUser } from '$lib/api/types.js';

  let users: AdminUser[] = $state([]);
  let loading = $state(true);
  let search = $state('');
  let statusFilter = $state('all');
  let sortKey = $state('created_at');
  let sortDir = $state<'asc' | 'desc'>('desc');

  let warnModalOpen = $state(false);
  let warnTarget: AdminUser | null = $state(null);
  let warnMessage = $state('');

  const columns = [
    { key: 'handle', label: 'Handle', sortable: true },
    { key: 'email', label: 'Email', sortable: true },
    { key: 'created_at', label: 'Created', sortable: true },
    { key: 'status', label: 'Status', sortable: true },
    { key: 'actions', label: 'Actions', width: '180px' }
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
          <button
            class="btn btn-sm btn-ghost"
            type="button"
            onclick={() => openWarnModal(row as unknown as AdminUser)}
          >Warn</button>
        </div>
      </td>
    {/snippet}
  </DataTable>
</div>

<Modal bind:open={warnModalOpen} title="Warn User">
  {#if warnTarget}
    <p class="warn-text">Send a warning to <strong>@{warnTarget.handle}</strong></p>
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

<style>
  .users-page {
    max-width: 1100px;
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

  .action-buttons {
    display: flex;
    gap: var(--space-2);
  }

  .warn-text {
    margin-block-end: var(--space-3);
    font-size: var(--text-sm);
  }

  .modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    margin-block-start: var(--space-4);
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
