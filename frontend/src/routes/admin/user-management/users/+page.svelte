<script lang="ts">
  import { onMount } from 'svelte';
  import DataTable from '$lib/components/admin/DataTable.svelte';
  import { t } from '$lib/stores/i18n.js';
  import Modal from '$lib/components/ui/Modal.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import {
    getAdminUsers, suspendUser, unsuspendUser, getRoles, createAdminUser
  } from '$lib/api/admin.js';
  import type { AdminUser, AdminRole } from '$lib/api/types.js';

  let users: AdminUser[] = $state([]);
  let loading = $state(true);
  let search = $state('');
  // When the URL carries `?id=<identity_id>` the list is pinned to
  // exactly that one row — no substring fuzziness, no risk of also
  // matching other users whose handles happen to share a prefix.
  // Cleared as soon as the admin edits the search box.
  let exactIdFilter: string | null = $state(null);
  let statusFilter = $state('all');
  let locationFilter = $state<'all' | 'local' | 'remote'>('all');
  // Email-verification filter only applies to local accounts — remote
  // users go through their origin instance's verification flow.
  let emailFilter = $state<'all' | 'verified' | 'unverified'>('all');
  // Pages and groups are Identity rows, so they were always in this list —
  // just indistinguishable from users.
  let typeFilter = $state<'all' | 'user' | 'page' | 'group' | 'bot'>('all');
  let sortKey = $state('created_at');
  let sortDir = $state<'asc' | 'desc'>('desc');

  // Paged, filtered and sorted by the server: an instance can hold tens of
  // thousands of identities, far too many to fetch and slice in the browser.
  // The endpoint caps a page at 40.
  const PAGE_SIZE = 40;
  let currentPage = $state(1);
  let totalUsers = $state(0);

  // Create user modal — admin-driven account creation. Bypasses the
  // public signup gates (turnstile / PoW / invite) on the backend, so
  // owners/admins can seed staff or replace lost accounts directly.
  let createModalOpen = $state(false);
  let createSubmitting = $state(false);
  let createHandle = $state('');
  let createEmail = $state('');
  let createPassword = $state('');
  let createDisplayName = $state('');
  let createAutoConfirm = $state(true);
  let createRoles: string[] = $state([]);
  let createError = $state('');
  // Role catalog for the create-user multi-select (lazily loaded).
  let allRoles: AdminRole[] = $state([]);

  function openCreateModal() {
    createHandle = '';
    createEmail = '';
    createPassword = '';
    createDisplayName = '';
    createAutoConfirm = true;
    createRoles = [];
    createError = '';
    createModalOpen = true;
    // Lazily pull the role catalog the first time the modal opens so
    // the multi-select has options. Reuses the same cache the "Manage
    // Roles" modal populates.
    if (allRoles.length === 0) {
      getRoles().then((roles) => { allRoles = roles; }).catch(() => {});
    }
  }

  function toggleCreateRole(name: string) {
    if (createRoles.includes(name)) {
      createRoles = createRoles.filter((r) => r !== name);
    } else {
      createRoles = [...createRoles, name];
    }
  }

  function generatePassword() {
    // 16 random base64url chars — strong enough that the admin doesn't
    // have to think one up, easy to read aloud if they have to.
    const bytes = new Uint8Array(12);
    crypto.getRandomValues(bytes);
    createPassword = btoa(String.fromCharCode(...bytes))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  async function handleCreateUser() {
    createError = '';
    const handle = createHandle.trim();
    const email = createEmail.trim();
    const password = createPassword;
    if (!handle || !email || !password) {
      createError = 'Handle, email, and password are required.';
      return;
    }
    createSubmitting = true;
    try {
      await createAdminUser({
        handle,
        email,
        password,
        display_name: createDisplayName.trim() || undefined,
        auto_confirm: createAutoConfirm,
        roles: createRoles,
      });
      addToast(`Created @${handle}`, 'success');
      createModalOpen = false;
      await loadUsers();
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to create user';
      createError = msg;
      addToast(msg, 'error');
    } finally {
      createSubmitting = false;
    }
  }

  const columns = [
    { key: 'handle', label: 'Handle', sortable: true },
    // Not sortable: emails are encrypted at rest.
    { key: 'email', label: 'Email' },
    { key: 'created_at', label: 'Created', sortable: true },
    { key: 'status', label: 'Status', sortable: true },
    { key: 'flags', label: 'Flags' },
    { key: 'trust_level', label: 'Trust', sortable: true },
    { key: 'actions', label: 'Actions', width: '220px' }
  ];

  // Nest subaccounts under their parent. Each parent is followed
  // immediately by its child rows (in the same sort order), so the
  // table reads like a tree. If the parent isn't on this page (filtered
  // out, sorted onto another page), orphan children fall back to
  // rendering as top-level rows — no surprise empty gaps.
  let groupedUsers = $derived.by(() => {
    const byId = new Map(users.map((u) => [u.id, u]));
    const childrenOf = new Map<string, AdminUser[]>();
    for (const u of users) {
      if (u.parent_identity_id && byId.has(u.parent_identity_id)) {
        const list = childrenOf.get(u.parent_identity_id) ?? [];
        list.push(u);
        childrenOf.set(u.parent_identity_id, list);
      }
    }

    const out: AdminUser[] = [];
    const seen = new Set<string>();
    for (const u of users) {
      if (u.parent_identity_id && byId.has(u.parent_identity_id)) continue;
      if (seen.has(u.id)) continue;
      out.push(u);
      seen.add(u.id);
      for (const child of childrenOf.get(u.id) ?? []) {
        if (!seen.has(child.id)) {
          out.push(child);
          seen.add(child.id);
        }
      }
    }
    return out;
  });

  let tableRows = $derived(
    groupedUsers.map((u) => ({
      ...u,
      is_subaccount: !!(u.parent_identity_id && groupedUsers.some((p) => p.id === u.parent_identity_id)),
    } as Record<string, unknown>))
  );

  let totalPages = $derived(Math.max(1, Math.ceil(totalUsers / PAGE_SIZE)));

  // Paint local rows whose email isn't confirmed in a warning tint so
  // an admin scanning the table can spot stalled signups at a glance.
  // Remote rows are excluded — we don't own their email confirmation
  // state and would otherwise tint half the federated table.
  // Subaccounts (bots, groups, pages owned by another user) inherit
  // their parent's verification, so they never carry their own email
  // and shouldn't show the unverified marker either.
  function isSubaccount(row: Record<string, unknown>): boolean {
    return !!row['parent_identity_id'];
  }

  function shouldFlagUnverified(row: Record<string, unknown>): boolean {
    const isLocal = row['is_local'] !== false;
    return isLocal && !isSubaccount(row) && row['email_confirmed'] === false;
  }

  function rowClassFor(row: Record<string, unknown>): string {
    return shouldFlagUnverified(row) ? 'row-email-unverified' : '';
  }

  onMount(async () => {
    // Deep-link params:
    //   ?id=<identity_id>  — pin to exactly that user
    //   ?search=<text>     — pre-fill the search box with substring match
    // `id` wins when both are set (used by "View author in admin"
    // which has the precise id). Search is the older shape we keep
    // for bookmarks and for cases where only a handle is known.
    if (typeof window !== 'undefined') {
      const url = new URL(window.location.href);
      const exactId = url.searchParams.get('id');
      const q = url.searchParams.get('search');
      if (exactId) exactIdFilter = exactId;
      if (q) search = q.replace(/^@/, '');
    }

  });

  // Reload from the first page whenever a filter or the sort changes. Debounced
  // so typing in the search box doesn't send a request per keystroke. Also does
  // the initial load, picking up any deep-link params set in onMount.
  $effect(() => {
    void search; void statusFilter; void locationFilter; void emailFilter; void typeFilter;
    void exactIdFilter; void sortKey; void sortDir;

    const timer = setTimeout(() => {
      currentPage = 1;
      loadUsers();
    }, 250);
    return () => clearTimeout(timer);
  });

  function goToPage(page: number) {
    currentPage = page;
    loadUsers();
  }

  // Any manual edit to search/status/location drops the pinned
  // single-user filter, so the admin can broaden the view without
  // having to reload the page.
  function clearExactFilter() {
    if (exactIdFilter) exactIdFilter = null;
  }

  // Responses can arrive out of order while filters change, so only the latest
  // request is allowed to update the table.
  let latestRequest = 0;

  async function loadUsers() {
    const request = ++latestRequest;
    loading = true;

    const params: Record<string, string> = {
      limit: String(PAGE_SIZE),
      offset: String((currentPage - 1) * PAGE_SIZE),
      sort: sortKey,
      dir: sortDir
    };

    if (exactIdFilter) {
      // Pins the list to one identity, regardless of the other filters.
      params.id = exactIdFilter;
    } else {
      if (search.trim()) params.search = search.trim();
      if (statusFilter !== 'all') params.status = statusFilter;
      if (emailFilter !== 'all') params.email = emailFilter;
      if (typeFilter !== 'all') params.type = typeFilter;
      if (locationFilter !== 'all') params.local = String(locationFilter === 'local');
    }

    try {
      const result = await getAdminUsers(params);
      if (request !== latestRequest) return;
      users = result.data;
      totalUsers = result.total;
    } catch {
      if (request === latestRequest) addToast('Failed to load users', 'error');
    } finally {
      if (request === latestRequest) loading = false;
    }
  }

  async function handleSuspend(user: AdminUser) {
    try {
      await suspendUser(user.id);
      users = users.map((u) => (u.id === user.id ? { ...u, is_suspended: true } : u));
      addToast(`Suspended @${user.handle}`, 'success');
    } catch {
      addToast('Failed to suspend user', 'error');
    }
  }

  async function handleUnsuspend(user: AdminUser) {
    try {
      await unsuspendUser(user.id);
      users = users.map((u) => (u.id === user.id ? { ...u, is_suspended: false } : u));
      addToast(`Unsuspended @${user.handle}`, 'success');
    } catch {
      addToast('Failed to unsuspend user', 'error');
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
  <div class="page-header">
    <h1 class="page-title">Users</h1>
    <button class="btn btn-primary" type="button" onclick={openCreateModal}>
      <span class="material-symbols-outlined" style="font-size: 18px">person_add</span>
      New user
    </button>
  </div>

  <div class="location-tabs" role="tablist">
    <button type="button" role="tab" class="loc-tab" class:loc-tab-active={locationFilter === 'all'} onclick={() => locationFilter = 'all'}>All</button>
    <button type="button" role="tab" class="loc-tab" class:loc-tab-active={locationFilter === 'local'} onclick={() => locationFilter = 'local'}>Local</button>
    <button type="button" role="tab" class="loc-tab" class:loc-tab-active={locationFilter === 'remote'} onclick={() => locationFilter = 'remote'}>Remote</button>
  </div>

  {#if exactIdFilter}
    <div class="pinned-banner">
      <span>Pinned to one user from a deep link.</span>
      <button type="button" class="pinned-banner-btn" onclick={clearExactFilter}>
        Show all users
      </button>
    </div>
  {/if}

  <div class="toolbar">
    <div class="search-bar">
      <input
        type="search"
        class="input"
        placeholder={$t('admin.users.search_placeholder')}
        aria-label={$t('admin.users.search_placeholder')}
        bind:value={search}
        oninput={clearExactFilter}
      />
    </div>
    <select class="input status-select" bind:value={statusFilter}>
      <option value="all">All Statuses</option>
      <option value="active">Active</option>
      <option value="suspended">Suspended</option>
    </select>
    <select class="input status-select" bind:value={emailFilter} aria-label="Filter by email verification">
      <option value="all">All emails</option>
      <option value="verified">Verified email</option>
      <option value="unverified">Unverified email</option>
    </select>
    <select class="input status-select" bind:value={typeFilter} aria-label="Filter by account type">
      <option value="all">All types</option>
      <option value="user">Users</option>
      <option value="page">Pages</option>
      <option value="group">Groups</option>
      <option value="bot">Bots</option>
    </select>
  </div>

  <DataTable
    {columns}
    rows={tableRows}
    bind:sortKey
    bind:sortDir
    {loading}
    rowClass={rowClassFor}
    emptyMessage="No users found"
  >
    {#snippet rowContent(row)}
      <td class:subaccount-row={row['is_subaccount']}>
        <div class="user-identity">
          {#if row['is_subaccount']}
            <!-- Angle marker indicating this row belongs to the
                 account above it (bot/page/group attached to a user). -->
            <span class="subaccount-angle" aria-hidden="true">&#x2937;</span>
          {/if}
          {#if row['avatar_url']}
            <img src={row['avatar_url'] as string} alt="" class="user-avatar" />
          {:else}
            <div class="user-avatar user-avatar-placeholder">
              {((row['display_name'] as string) || (row['handle'] as string) || '?').charAt(0).toUpperCase()}
            </div>
          {/if}
          <div class="user-info-col">
            {#if row['display_name']}
              <span class="user-display-name">{row['display_name']}</span>
            {/if}
            <span class="user-handle">@{row['acct'] || row['handle']}</span>
            {#if row['domain']}
              <span class="user-domain-badge">
                <span class="material-symbols-outlined" style="font-size: 12px">public</span>
                {row['domain']}
              </span>
            {:else if isSubaccount(row)}
              <span class="user-local-badge user-subaccount-badge">Sub-Account</span>
            {:else}
              <span class="user-local-badge">Local</span>
            {/if}
          </div>
        </div>
      </td>
      <td>
        <div class="email-cell">
          <span>{row['email'] || ''}</span>
          {#if shouldFlagUnverified(row)}
            <span class="email-unverified-pill" title="Email not confirmed">unverified</span>
          {/if}
        </div>
      </td>
      <td>{formatDate(row['created_at'] as string)}</td>
      <td>
        <span class="status-badge {statusClass(row['is_suspended'] ? 'suspended' : 'active')}">
          {row['is_suspended'] ? 'suspended' : 'active'}
        </span>
      </td>
      <td>
        <div class="flag-badges">
          {#if row['is_silenced']}
            <span class="flag-badge flag-silenced">silenced</span>
          {/if}
          {#if row['is_shadow_banned']}
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
          {#if row['is_suspended']}
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
          <a class="btn btn-sm btn-outline" href="/admin/user-management/users/{row['id']}">Manage</a>
        </div>
      </td>
    {/snippet}
  </DataTable>

  {#if totalUsers > PAGE_SIZE}
    <nav class="pagination" aria-label="User list pagination">
      <button
        type="button"
        class="page-btn"
        onclick={() => goToPage(currentPage - 1)}
        disabled={currentPage === 1 || loading}
      >
        Previous
      </button>
      <span class="page-info">
        Page {currentPage} of {totalPages}
        <span class="page-info-count">({totalUsers.toLocaleString()} users)</span>
      </span>
      <button
        type="button"
        class="page-btn"
        onclick={() => goToPage(currentPage + 1)}
        disabled={currentPage >= totalPages || loading}
      >
        Next
      </button>
    </nav>
  {/if}
</div>

<!-- Create User Modal — admin-driven account creation -->
<Modal bind:open={createModalOpen} title="Create user">
  <p class="modal-text">
    Create a local account directly. Public signup gates (turnstile, invite codes) are bypassed.
  </p>
  <form onsubmit={(e) => { e.preventDefault(); handleCreateUser(); }}>
    <div class="form-group">
      <label class="form-label" for="create-handle">Handle</label>
      <input
        id="create-handle"
        class="input"
        type="text"
        bind:value={createHandle}
        placeholder="alice"
        autocomplete="off"
        required
      />
    </div>
    <div class="form-group">
      <label class="form-label" for="create-email">Email</label>
      <input
        id="create-email"
        class="input"
        type="email"
        bind:value={createEmail}
        placeholder="user@example.com"
        autocomplete="off"
        required
      />
    </div>
    <div class="form-group">
      <label class="form-label" for="create-password">Password</label>
      <div class="password-row">
        <input
          id="create-password"
          class="input"
          type="text"
          bind:value={createPassword}
          autocomplete="new-password"
          required
        />
        <button class="btn btn-sm btn-outline" type="button" onclick={generatePassword}>
          Generate
        </button>
      </div>
    </div>
    <div class="form-group">
      <label class="form-label" for="create-display-name">Display name (optional)</label>
      <input
        id="create-display-name"
        class="input"
        type="text"
        bind:value={createDisplayName}
        maxlength="50"
      />
    </div>
    <div class="form-group">
      <label class="checkbox-row">
        <input type="checkbox" bind:checked={createAutoConfirm} />
        <span>Mark email confirmed (no confirmation email is sent)</span>
      </label>
    </div>
    {#if allRoles.length > 0}
      <div class="form-group">
        <span class="form-label">Roles (optional)</span>
        <div class="role-checkbox-list">
          {#each allRoles as role (role.id)}
            <label class="checkbox-row">
              <input
                type="checkbox"
                checked={createRoles.includes(role.name)}
                onchange={() => toggleCreateRole(role.name)}
              />
              <span>
                <strong>{role.name}</strong>
                {#if role.description}<span class="role-description"> — {role.description}</span>{/if}
              </span>
            </label>
          {/each}
        </div>
      </div>
    {/if}
    {#if createError}
      <p class="form-error">{createError}</p>
    {/if}
    <div class="modal-actions">
      <button class="btn btn-ghost" type="button" onclick={() => (createModalOpen = false)}>Cancel</button>
      <button
        class="btn btn-primary"
        type="submit"
        disabled={createSubmitting || !createHandle.trim() || !createEmail.trim() || !createPassword}
      >
        {createSubmitting ? 'Creating...' : 'Create user'}
      </button>
    </div>
  </form>
</Modal>

<style>
  /* Clear-avatar / clear-banner rows in the Edit Profile modal. */
  .media-clear-row {
    display: flex;
    align-items: center;
    gap: var(--space-3, 0.75rem);
    padding: var(--space-2, 0.5rem) 0;
  }

  .media-clear-thumb {
    object-fit: cover;
    background: var(--color-bg-tertiary);
    border: 1px solid var(--color-border);
    flex-shrink: 0;
  }

  .media-clear-avatar {
    width: 40px;
    height: 40px;
    border-radius: var(--radius-full, 999px);
  }

  .media-clear-header {
    width: 72px;
    height: 40px;
    border-radius: var(--radius-md, 0.5rem);
  }

  .media-clear-empty {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    border-radius: var(--radius-md, 0.5rem);
    background: var(--color-bg-tertiary);
    border: 1px dashed var(--color-border);
    color: var(--color-text-tertiary);
    font-size: var(--text-xs, 0.75rem);
    flex-shrink: 0;
  }

  .media-clear-label {
    flex: 1;
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text-secondary);
  }

  .page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    margin-block-end: var(--space-6);
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin: 0;
  }

  .page-header .btn {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
  }

  .password-row {
    display: flex;
    gap: var(--space-2);
    align-items: stretch;
  }

  .password-row .input {
    flex: 1;
  }

  .checkbox-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    cursor: pointer;
  }

  .role-checkbox-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin-block-start: var(--space-2);
    max-height: 240px;
    overflow-y: auto;
    padding: var(--space-2);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
  }

  .form-error {
    color: var(--danger);
    font-size: var(--text-sm);
    margin-block-start: var(--space-2);
  }

  .toolbar {
    display: flex;
    gap: var(--space-3);
    margin-block-end: var(--space-4);
  }

  .pinned-banner {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-2) var(--space-3);
    margin-block-end: var(--space-3);
    background: var(--color-secondary-container);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    color: var(--color-primary);
  }

  .pinned-banner-btn {
    background: transparent;
    border: 1px solid var(--color-primary);
    color: var(--color-primary);
    padding: 4px 10px;
    border-radius: var(--radius-full);
    font-size: var(--text-xs);
    font-weight: 600;
    cursor: pointer;
  }

  .pinned-banner-btn:hover {
    background: var(--color-primary);
    color: var(--color-on-primary);
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
    color: var(--color-on-success-soft);
  }

  .status-suspended {
    background: var(--color-danger-soft);
    color: var(--color-on-danger-soft);
  }

  .status-pending {
    background: var(--color-warning-soft);
    color: var(--color-on-warning-soft);
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
    color: var(--color-on-warning-soft);
  }

  .flag-shadow {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }

  .flag-sensitive {
    background: var(--color-info-soft);
    color: var(--color-on-info-soft);
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
    /* Size the column to its buttons, so a narrow screen scrolls the table
       sideways instead of cutting them off. */
    width: max-content;
  }

  .dropdown {
    position: relative;
  }

  .dropdown-menu {
    position: fixed;
    z-index: 9999;
    min-width: 180px;
    background: var(--color-surface-raised, white);
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

  .password-display {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-3);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    margin-block: var(--space-3);
  }

  .password-code {
    flex: 1;
    font-family: var(--font-mono, monospace);
    font-size: var(--text-base);
    font-weight: 600;
    color: var(--color-text);
    word-break: break-all;
    user-select: all;
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

  /* Location tabs */
  .location-tabs {
    display: flex;
    gap: 2px;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: 10px;
    padding: 3px;
    margin-block-end: var(--space-4);
    max-width: 300px;
  }

  .loc-tab {
    flex: 1;
    padding: 6px 14px;
    border: none;
    border-radius: 8px;
    background: transparent;
    font-size: 0.8125rem;
    font-weight: 600;
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: all 150ms ease;
  }

  .loc-tab:hover { color: var(--color-text); }

  .loc-tab-active {
    background: var(--color-primary);
    color: white;
  }

  .loc-tab-active:hover { color: white; }

  /* User identity cell */
  .user-identity {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 4px 0;
  }

  .subaccount-row {
    padding-inline-start: 28px;
    position: relative;
  }

  .subaccount-row::before {
    content: '';
    position: absolute;
    inset-block: 0;
    inset-inline-start: 14px;
    width: 2px;
    background: var(--color-border);
  }

  .subaccount-angle {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 18px;
    font-size: 1.05rem;
    color: var(--color-text-tertiary);
    margin-inline-end: -4px;
    flex-shrink: 0;
    line-height: 1;
  }

  .user-avatar {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    object-fit: cover;
    flex-shrink: 0;
  }

  .user-avatar-placeholder {
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--color-primary-soft);
    color: var(--color-primary);
    font-size: 0.875rem;
    font-weight: 700;
  }

  .user-info-col {
    display: flex;
    flex-direction: column;
    gap: 1px;
    min-width: 0;
  }

  .user-display-name {
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text);
    line-height: 1.3;
  }

  .user-handle {
    font-size: 0.8125rem;
    color: var(--color-text-secondary);
    font-weight: 400;
  }

  .user-domain-badge {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    font-size: 0.65rem;
    color: var(--color-text-tertiary);
    background: var(--color-surface);
    padding: 1px 6px;
    border-radius: 4px;
    width: fit-content;
    margin-block-start: 2px;
  }

  .user-local-badge {
    display: inline-block;
    font-size: 0.6rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.03em;
    color: var(--color-success);
    background: var(--color-success-tint);
    padding: 1px 6px;
    border-radius: 4px;
    width: fit-content;
    margin-block-start: 2px;
  }

  /* Sub-accounts (bots / groups / pages owned by a parent user)
     deserve their own pill so the row isn't visually conflated with
     a top-level local account. */
  .user-subaccount-badge {
    color: var(--color-primary);
    background: var(--color-primary-soft);
  }

  .email-cell {
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }

  .email-unverified-pill {
    font-size: 0.65rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.03em;
    color: var(--color-on-warning-soft);
    background: rgba(var(--color-warning-rgb), 0.18);
    padding: 1px 6px;
    border-radius: 4px;
  }

  /* Highlight local accounts that haven't confirmed their email yet —
     applied to the <tr> via DataTable's rowClass hook so it overrides
     both the zebra striping and the row hover background. */
  :global(.data-table tbody tr.row-email-unverified) {
    background: rgba(var(--color-warning-rgb), 0.1);
  }

  :global(.data-table tbody tr.row-email-unverified:hover) {
    background: rgba(var(--color-warning-rgb), 0.18);
  }

  :global(.data-table tbody tr.row-email-unverified:nth-child(even)) {
    background: rgba(var(--color-warning-rgb), 0.13);
  }

  /* Pagination footer below the user table. */
  .pagination {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-3);
    margin-block-start: var(--space-4);
    padding: var(--space-2);
  }

  .page-btn {
    padding: 6px 14px;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    background: var(--color-surface);
    color: var(--color-text);
    font-size: var(--text-sm);
    font-weight: 600;
    cursor: pointer;
  }

  .page-btn:hover:not(:disabled) {
    border-color: var(--color-primary);
    color: var(--color-primary);
  }

  .page-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .page-info {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    font-variant-numeric: tabular-nums;
  }

  .page-info-count {
    color: var(--color-text-tertiary);
    margin-inline-start: 6px;
  }

  /* Manage Roles modal */
  .roles-list {
    list-style: none;
    padding: 0;
    margin: var(--space-3) 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    max-height: 420px;
    overflow-y: auto;
  }

  .role-row {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    transition: border-color var(--transition-fast), background var(--transition-fast);
  }

  .role-row.role-assigned {
    border-color: var(--color-primary);
    background: var(--color-secondary-container);
  }

  .role-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
    flex: 1;
  }

  .role-name-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .role-name {
    font-weight: 600;
    font-size: var(--text-sm);
    text-transform: capitalize;
  }

  .role-system-badge {
    font-size: 0.65rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-secondary);
    background: var(--color-surface);
    padding: 1px 6px;
    border-radius: var(--radius-full);
  }

  .role-description {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    line-height: 1.4;
  }

  .role-permissions-summary {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-start: 2px;
  }

  .role-granted {
    font-size: var(--text-xs);
    color: var(--color-primary);
    margin-block-start: 2px;
  }

  .tier-options {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin-block: var(--space-3);
  }

  .tier-option {
    display: flex;
    align-items: flex-start;
    gap: var(--space-3);
    padding: var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    cursor: pointer;
    transition: background 120ms ease, border-color 120ms ease;
  }

  .tier-option:hover {
    background: var(--color-surface);
  }

  .tier-option-active {
    border-color: var(--color-primary);
    background: var(--color-primary-soft, var(--color-surface));
  }

  .tier-option input[type='radio'] {
    margin-block-start: 4px;
  }

  .tier-option-body {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .tier-option-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .tier-option-desc {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }
</style>
