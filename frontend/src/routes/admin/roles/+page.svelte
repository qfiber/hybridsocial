<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { hasPermission } from '$lib/stores/auth.js';
  import { addToast } from '$lib/stores/toast.js';
  import type { AdminRole, AdminPermission, PermissionCategory } from '$lib/api/types.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let roles: AdminRole[] = $state([]);
  let allPermissions: PermissionCategory[] = $state([]);
  let loading = $state(true);
  let editingRole: AdminRole | null = $state(null);
  let showCreateForm = $state(false);
  let newRoleName = $state('');
  let newRoleDescription = $state('');
  let savingPermissions = $state(false);

  const canManage = $derived(hasPermission('roles.manage'));

  const roleColors: Record<string, string> = {
    owner: '#d97706',
    admin: 'var(--color-primary)',
    moderator: '#6366f1',
  };

  onMount(async () => {
    await loadData();
  });

  async function loadData() {
    loading = true;
    try {
      const [rolesRes, permsRes] = await Promise.all([
        api.get<{ data: AdminRole[] }>('/api/v1/admin/roles'),
        api.get<{ data: PermissionCategory[] }>('/api/v1/admin/permissions')
      ]);
      roles = rolesRes.data;
      allPermissions = permsRes.data;
    } catch {
      addToast('Failed to load roles', 'error');
    } finally {
      loading = false;
    }
  }

  async function createRole() {
    if (!newRoleName.trim()) return;
    try {
      await api.post('/api/v1/admin/roles', {
        name: newRoleName.trim(),
        description: newRoleDescription.trim() || null
      });
      addToast('Role created', 'success');
      newRoleName = '';
      newRoleDescription = '';
      showCreateForm = false;
      await loadData();
    } catch {
      addToast('Failed to create role', 'error');
    }
  }

  async function deleteRole(role: AdminRole) {
    if (role.is_system) {
      addToast('System roles cannot be deleted', 'error');
      return;
    }
    if (!confirm(`Delete role "${role.name}"? This cannot be undone.`)) return;
    try {
      await api.delete(`/api/v1/admin/roles/${role.id}`);
      addToast('Role deleted', 'success');
      if (editingRole?.id === role.id) editingRole = null;
      await loadData();
    } catch {
      addToast('Failed to delete role', 'error');
    }
  }

  function roleHasPermission(role: AdminRole, permId: string): boolean {
    return role.permissions.some((p) => p.id === permId);
  }

  async function togglePermission(role: AdminRole, perm: AdminPermission) {
    savingPermissions = true;
    try {
      if (roleHasPermission(role, perm.id)) {
        await api.delete(`/api/v1/admin/roles/${role.id}/permissions/${perm.id}`);
      } else {
        await api.post(`/api/v1/admin/roles/${role.id}/permissions`, {
          permission_id: perm.id
        });
      }
      await loadData();
      if (editingRole) {
        editingRole = roles.find((r) => r.id === editingRole!.id) ?? null;
      }
    } catch {
      addToast('Failed to update permission', 'error');
    } finally {
      savingPermissions = false;
    }
  }

  function permCount(role: AdminRole): number {
    return role.permissions.length;
  }

  function totalPerms(): number {
    return allPermissions.reduce((sum, cat) => sum + cat.permissions.length, 0);
  }
</script>

<svelte:head>
  <title>Roles & Permissions - Admin</title>
</svelte:head>

<div class="roles-page">
  <div class="page-header">
    <div>
      <h1 class="page-title">Roles & Permissions</h1>
      <p class="page-desc">Manage staff roles and what each role can do.</p>
    </div>
    {#if canManage}
      <button class="btn-create" onclick={() => (showCreateForm = !showCreateForm)}>
        <span class="material-symbols-outlined" style="font-size: 18px">{showCreateForm ? 'close' : 'add'}</span>
        {showCreateForm ? 'Cancel' : 'New Role'}
      </button>
    {/if}
  </div>

  {#if showCreateForm && canManage}
    <div class="create-card">
      <div class="create-fields">
        <div class="create-field">
          <label for="role-name">Role name</label>
          <input id="role-name" type="text" class="input" bind:value={newRoleName} placeholder="e.g. content_reviewer" />
        </div>
        <div class="create-field">
          <label for="role-desc">Description</label>
          <input id="role-desc" type="text" class="input" bind:value={newRoleDescription} placeholder="What can this role do?" />
        </div>
        <button class="btn-primary" onclick={createRole} disabled={!newRoleName.trim()}>Create Role</button>
      </div>
    </div>
  {/if}

  {#if loading}
    <div class="loading"><Spinner /></div>
  {:else}
    <div class="layout">
      <!-- Roles sidebar -->
      <div class="roles-sidebar">
        {#each roles as role (role.id)}
          <button
            class="role-card"
            class:active={editingRole?.id === role.id}
            onclick={() => (editingRole = role)}
            type="button"
          >
            <div class="role-indicator" style="background: {roleColors[role.name] || 'var(--color-text-tertiary)'}"></div>
            <div class="role-info">
              <div class="role-name-row">
                <span class="role-name">{role.name}</span>
                {#if role.is_system}
                  <span class="system-tag">System</span>
                {/if}
              </div>
              {#if role.description}
                <span class="role-desc">{role.description}</span>
              {/if}
              <span class="role-meta">{permCount(role)} / {totalPerms()} permissions</span>
            </div>
            {#if canManage && !role.is_system}
              <button
                class="role-delete"
                onclick={(e) => { e.stopPropagation(); deleteRole(role); }}
                title="Delete role"
                type="button"
              >
                <span class="material-symbols-outlined" style="font-size: 16px">delete</span>
              </button>
            {/if}
          </button>
        {/each}
      </div>

      <!-- Permissions panel -->
      <div class="perms-panel">
        {#if editingRole}
          <div class="perms-header">
            <div class="perms-header-dot" style="background: {roleColors[editingRole.name] || 'var(--color-text-tertiary)'}"></div>
            <h2>{editingRole.name}</h2>
            <span class="perms-count">{permCount(editingRole)} permissions enabled</span>
          </div>

          {#if editingRole.is_system && !canManage}
            <p class="perms-readonly">System role — permissions are read-only.</p>
          {/if}

          <div class="perms-grid">
            {#each allPermissions as category (category.category)}
              <div class="perm-group">
                <div class="perm-group-header">
                  <span class="perm-group-name">{category.category}</span>
                  <span class="perm-group-count">
                    {category.permissions.filter(p => roleHasPermission(editingRole!, p.id)).length} / {category.permissions.length}
                  </span>
                </div>
                <div class="perm-items">
                  {#each category.permissions as perm (perm.id)}
                    <label class="perm-row" class:checked={roleHasPermission(editingRole, perm.id)}>
                      <input
                        type="checkbox"
                        checked={roleHasPermission(editingRole, perm.id)}
                        onchange={() => togglePermission(editingRole!, perm)}
                        disabled={savingPermissions || !canManage}
                      />
                      <div class="perm-text">
                        <span class="perm-label">{perm.name}</span>
                        {#if perm.description}
                          <span class="perm-hint">{perm.description}</span>
                        {/if}
                      </div>
                    </label>
                  {/each}
                </div>
              </div>
            {/each}
          </div>
        {:else}
          <div class="perms-empty">
            <span class="material-symbols-outlined" style="font-size: 48px; color: var(--color-text-tertiary)">shield</span>
            <p>Select a role to view its permissions</p>
          </div>
        {/if}
      </div>
    </div>
  {/if}
</div>

<style>
  .roles-page { max-width: 1100px; }

  .page-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    margin-block-end: var(--space-6);
  }

  .page-title { font-size: var(--text-2xl); font-weight: 700; }
  .page-desc { font-size: var(--text-sm); color: var(--color-text-secondary); margin-block-start: 2px; }

  .btn-create {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 8px 16px;
    background: var(--color-primary);
    color: var(--color-on-primary);
    border: none;
    border-radius: 9999px;
    font-size: 0.8125rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.15s ease;
  }

  .btn-create:hover { opacity: 0.9; }

  /* Create form */
  .create-card {
    background: var(--color-surface-raised, white);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-5);
    margin-block-end: var(--space-4);
  }

  .create-fields { display: flex; gap: var(--space-3); align-items: flex-end; }
  .create-field { flex: 1; display: flex; flex-direction: column; gap: 4px; }
  .create-field label { font-size: 0.7rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: var(--color-text-secondary); }

  .btn-primary {
    padding: 10px 20px;
    background: var(--color-primary);
    color: var(--color-on-primary);
    border: none;
    border-radius: 10px;
    font-size: 0.8125rem;
    font-weight: 600;
    cursor: pointer;
    white-space: nowrap;
  }

  .btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }

  .loading { text-align: center; padding: var(--space-10); }

  /* Two-panel layout */
  .layout {
    display: grid;
    grid-template-columns: 280px 1fr;
    gap: var(--space-4);
    align-items: start;
  }

  /* Roles sidebar */
  .roles-sidebar {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .role-card {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    background: var(--color-surface-raised, white);
    cursor: pointer;
    transition: all 0.15s ease;
    text-align: start;
    width: 100%;
  }

  .role-card:hover { border-color: var(--color-primary-soft, rgba(0,128,128,0.3)); }
  .role-card.active { border-color: var(--color-primary); background: var(--color-primary-soft, rgba(0,128,128,0.06)); }

  .role-indicator {
    width: 4px;
    height: 32px;
    border-radius: 2px;
    flex-shrink: 0;
  }

  .role-info { flex: 1; min-width: 0; }

  .role-name-row { display: flex; align-items: center; gap: 6px; }
  .role-name { font-size: 0.8125rem; font-weight: 600; color: var(--color-text); }

  .system-tag {
    font-size: 0.6rem;
    font-weight: 700;
    text-transform: uppercase;
    padding: 1px 5px;
    border-radius: var(--radius-full);
    background: var(--color-info-soft, #dbeafe);
    color: var(--color-info, #2563eb);
  }

  .role-desc { font-size: 0.7rem; color: var(--color-text-tertiary); display: block; margin-block-start: 1px; }
  .role-meta { font-size: 0.65rem; color: var(--color-text-tertiary); display: block; margin-block-start: 2px; }

  .role-delete {
    background: none;
    border: none;
    color: var(--color-text-tertiary);
    cursor: pointer;
    padding: 4px;
    border-radius: 50%;
    opacity: 0;
    transition: all 0.15s ease;
    flex-shrink: 0;
  }

  .role-card:hover .role-delete { opacity: 1; }
  .role-delete:hover { color: var(--color-danger); background: var(--color-danger-soft, rgba(239,68,68,0.1)); }

  /* Permissions panel */
  .perms-panel {
    background: var(--color-surface-raised, white);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-5);
    min-height: 400px;
  }

  .perms-header {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    margin-block-end: var(--space-4);
    padding-block-end: var(--space-3);
    border-block-end: 1px solid var(--color-border);
  }

  .perms-header-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .perms-header h2 { font-size: var(--text-lg); font-weight: 700; flex: 1; }
  .perms-count { font-size: 0.75rem; color: var(--color-text-tertiary); }

  .perms-readonly {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    background: var(--color-surface-container-low, #f5f5f5);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    margin-block-end: var(--space-4);
  }

  .perms-grid { display: flex; flex-direction: column; gap: var(--space-4); }

  .perm-group-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-end: var(--space-2);
  }

  .perm-group-name {
    font-size: 0.75rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--color-text-secondary);
  }

  .perm-group-count { font-size: 0.65rem; color: var(--color-text-tertiary); }

  .perm-items { display: flex; flex-direction: column; gap: 2px; }

  .perm-row {
    display: flex;
    align-items: flex-start;
    gap: var(--space-2);
    padding: 6px 8px;
    border-radius: var(--radius-md);
    cursor: pointer;
    transition: background 0.1s ease;
  }

  .perm-row:hover { background: var(--color-surface-container-low, #f5f5f5); }
  .perm-row.checked { background: var(--color-primary-soft, rgba(0,128,128,0.04)); }

  .perm-row input[type='checkbox'] {
    margin-block-start: 2px;
    flex-shrink: 0;
    accent-color: var(--color-primary);
  }

  .perm-text { display: flex; flex-direction: column; }
  .perm-label { font-size: 0.8125rem; font-weight: 500; color: var(--color-text); }
  .perm-hint { font-size: 0.7rem; color: var(--color-text-tertiary); line-height: 1.3; }

  .perms-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--space-3);
    min-height: 300px;
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
  }

  @media (max-width: 768px) {
    .layout { grid-template-columns: 1fr; }
    .create-fields { flex-direction: column; }
  }
</style>
