<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { hasPermission } from '$lib/stores/auth.js';
  import { addToast } from '$lib/stores/toast.js';
  import type { AdminRole, AdminPermission, PermissionCategory } from '$lib/api/types.js';

  let roles: AdminRole[] = $state([]);
  let allPermissions: PermissionCategory[] = $state([]);
  let loading = $state(true);
  let editingRole: AdminRole | null = $state(null);
  let showCreateForm = $state(false);
  let newRoleName = $state('');
  let newRoleDescription = $state('');
  let savingPermissions = $state(false);

  const canManage = $derived(hasPermission('roles.manage'));

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
      // Re-select the editing role with updated data
      if (editingRole) {
        editingRole = roles.find((r) => r.id === editingRole!.id) ?? null;
      }
    } catch {
      addToast('Failed to update permission', 'error');
    } finally {
      savingPermissions = false;
    }
  }
</script>

<svelte:head>
  <title>Roles - Admin</title>
</svelte:head>

<div class="roles-page">
  <div class="page-header">
    <h1>Roles & Permissions</h1>
    {#if canManage}
      <button class="btn btn-primary" onclick={() => (showCreateForm = !showCreateForm)}>
        {showCreateForm ? 'Cancel' : 'Create Role'}
      </button>
    {/if}
  </div>

  {#if showCreateForm && canManage}
    <div class="card create-form">
      <h3>Create Custom Role</h3>
      <div class="form-group">
        <label for="role-name">Name</label>
        <input id="role-name" type="text" bind:value={newRoleName} placeholder="e.g. content_reviewer" />
      </div>
      <div class="form-group">
        <label for="role-desc">Description</label>
        <input id="role-desc" type="text" bind:value={newRoleDescription} placeholder="Optional description" />
      </div>
      <button class="btn btn-primary" onclick={createRole} disabled={!newRoleName.trim()}>
        Create
      </button>
    </div>
  {/if}

  {#if loading}
    <div class="loading">Loading roles...</div>
  {:else}
    <div class="roles-layout">
      <div class="roles-list">
        <h2>Roles</h2>
        {#each roles as role (role.id)}
          <div
            class="role-card"
            class:active={editingRole?.id === role.id}
            onclick={() => (editingRole = role)}
            onkeydown={(e) => e.key === 'Enter' && (editingRole = role)}
            role="button"
            tabindex="0"
          >
            <div class="role-header">
              <span class="role-name">{role.name}</span>
              {#if role.is_system}
                <span class="badge badge-system">System</span>
              {/if}
            </div>
            {#if role.description}
              <p class="role-description">{role.description}</p>
            {/if}
            <p class="role-perm-count">{role.permissions.length} permissions</p>
            {#if canManage && !role.is_system}
              <button
                class="btn btn-danger btn-sm"
                onclick={(e) => { e.stopPropagation(); deleteRole(role); }}
              >
                Delete
              </button>
            {/if}
          </div>
        {/each}
      </div>

      {#if editingRole}
        <div class="permissions-panel">
          <h2>Permissions for: {editingRole.name}</h2>
          {#if editingRole.is_system && !canManage}
            <p class="info-text">System role permissions are read-only.</p>
          {/if}

          {#each allPermissions as category (category.category)}
            <div class="perm-category">
              <h3>{category.category}</h3>
              <div class="perm-list">
                {#each category.permissions as perm (perm.id)}
                  <label class="perm-item" class:disabled={savingPermissions || !canManage}>
                    <input
                      type="checkbox"
                      checked={roleHasPermission(editingRole, perm.id)}
                      onchange={() => togglePermission(editingRole!, perm)}
                      disabled={savingPermissions || !canManage}
                    />
                    <div class="perm-info">
                      <span class="perm-name">{perm.name}</span>
                      {#if perm.description}
                        <span class="perm-desc">{perm.description}</span>
                      {/if}
                    </div>
                  </label>
                {/each}
              </div>
            </div>
          {/each}
        </div>
      {:else}
        <div class="permissions-panel empty">
          <p>Select a role to view and manage its permissions.</p>
        </div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .roles-page {
    max-width: 1200px;
  }

  .page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-end: var(--space-6);
  }

  .page-header h1 {
    font-size: var(--text-2xl);
    font-weight: 700;
  }

  .create-form {
    padding: var(--space-4);
    margin-block-end: var(--space-6);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
  }

  .create-form h3 {
    margin-block-end: var(--space-3);
  }

  .form-group {
    margin-block-end: var(--space-3);
  }

  .form-group label {
    display: block;
    font-size: var(--text-sm);
    font-weight: 500;
    margin-block-end: var(--space-1);
    color: var(--color-text-secondary);
  }

  .form-group input {
    width: 100%;
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-bg);
    color: var(--color-text);
    font-size: var(--text-sm);
  }

  .roles-layout {
    display: grid;
    grid-template-columns: 300px 1fr;
    gap: var(--space-6);
    align-items: start;
  }

  .roles-list h2,
  .permissions-panel h2 {
    font-size: var(--text-lg);
    font-weight: 600;
    margin-block-end: var(--space-3);
  }

  .role-card {
    padding: var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    margin-block-end: var(--space-2);
    cursor: pointer;
    transition: border-color var(--transition-fast), background var(--transition-fast);
    background: var(--color-surface);
  }

  .role-card:hover {
    border-color: var(--color-primary-soft);
  }

  .role-card.active {
    border-color: var(--color-primary);
    background: var(--color-primary-soft);
  }

  .role-header {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .role-name {
    font-weight: 600;
    font-size: var(--text-sm);
  }

  .badge-system {
    font-size: var(--text-xs);
    padding: 1px 6px;
    border-radius: var(--radius-full);
    background: var(--color-info);
    color: white;
    font-weight: 500;
  }

  .role-description {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    margin-block-start: var(--space-1);
  }

  .role-perm-count {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-start: var(--space-1);
  }

  .permissions-panel {
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    padding: var(--space-4);
  }

  .permissions-panel.empty {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 200px;
    color: var(--color-text-tertiary);
  }

  .info-text {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-3);
  }

  .perm-category {
    margin-block-end: var(--space-4);
  }

  .perm-category h3 {
    font-size: var(--text-sm);
    font-weight: 600;
    text-transform: capitalize;
    color: var(--color-text-secondary);
    margin-block-end: var(--space-2);
    padding-block-end: var(--space-1);
    border-block-end: 1px solid var(--color-border);
  }

  .perm-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .perm-item {
    display: flex;
    align-items: flex-start;
    gap: var(--space-2);
    padding: var(--space-1) var(--space-2);
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: background var(--transition-fast);
  }

  .perm-item:hover {
    background: var(--color-bg);
  }

  .perm-item.disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .perm-item input[type='checkbox'] {
    margin-block-start: 2px;
    flex-shrink: 0;
  }

  .perm-info {
    display: flex;
    flex-direction: column;
  }

  .perm-name {
    font-size: var(--text-sm);
    font-weight: 500;
  }

  .perm-desc {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .btn {
    padding: var(--space-2) var(--space-4);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-weight: 500;
    cursor: pointer;
    border: none;
    transition: background var(--transition-fast);
  }

  .btn-primary {
    background: var(--color-primary);
    color: white;
  }

  .btn-primary:hover {
    background: var(--color-primary-hover);
  }

  .btn-primary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .btn-danger {
    background: var(--color-danger);
    color: white;
    margin-block-start: var(--space-2);
  }

  .btn-sm {
    padding: var(--space-1) var(--space-2);
    font-size: var(--text-xs);
  }

  .loading {
    text-align: center;
    padding: var(--space-8);
    color: var(--color-text-secondary);
  }

  @media (max-width: 768px) {
    .roles-layout {
      grid-template-columns: 1fr;
    }
  }
</style>
