<script lang="ts">
  import { instanceName } from '$lib/stores/instance.js';
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import {
    getPage,
    getPageRoles,
    addPageRole,
    removePageRole,
    invitePageManager,
    type PageRole,
  } from '$lib/api/pages.js';
  import { search } from '$lib/api/search.js';
  import { addToast } from '$lib/stores/toast.js';
  import type { Identity } from '$lib/api/types.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import Tabs from '$lib/components/ui/Tabs.svelte';

  // Mirror the role tiers from the backend (Pages.can_manage? /
  // can_moderate?). `viewer_role` comes from the page response and is
  // already normalized — "owner" covers both the org owner and the
  // parent identity owner (the user who created the page).
  const MANAGE_ROLES = new Set(['owner', 'admin']);
  const MODERATE_ROLES = new Set(['owner', 'admin', 'editor', 'moderator']);

  type AssignableRole = 'admin' | 'editor' | 'moderator';

  let pageId = $derived(page.params.id!);

  let pageData = $state<Record<string, unknown> | null>(null);
  let loading = $state(true);

  let roles = $state<PageRole[]>([]);
  let rolesLoading = $state(false);
  let rolesLoaded = $state(false);

  let activeTab = $state('members');

  // Invite tab state
  let inviteQuery = $state('');
  let inviteResults = $state<Identity[]>([]);
  let inviteSearching = $state(false);
  let inviteTimeout: ReturnType<typeof setTimeout> | undefined;
  let inviting = $state(false);

  let viewerRole = $derived(
    typeof pageData?.viewer_role === 'string' ? (pageData!.viewer_role as string) : '',
  );
  let canManage = $derived(MANAGE_ROLES.has(viewerRole));
  let canModerate = $derived(MODERATE_ROLES.has(viewerRole));

  // Tabs filtered by role tier — moderators see Members in read-only
  // mode, admins/owners also see Invite. Members tab is always
  // available to anyone with at least moderate access since the goal
  // is letting them see who's on the team even if they can't change
  // it.
  let tabs = $derived(
    [
      canModerate ? { id: 'members', label: 'Members' } : null,
      canManage ? { id: 'invite', label: 'Invite' } : null,
    ].filter((t) => t !== null) as { id: string; label: string }[],
  );

  let displayName = $derived(
    typeof pageData?.display_name === 'string' && pageData.display_name
      ? (pageData.display_name as string)
      : typeof pageData?.handle === 'string'
        ? (pageData.handle as string)
        : '',
  );

  onMount(async () => {
    try {
      pageData = await getPage(pageId);
      if (!MODERATE_ROLES.has(viewerRole)) {
        // Anyone without at least a moderator-level role gets bounced
        // back to the page profile — nothing to manage here.
        goto(`/pages/${pageId}`);
        return;
      }
    } catch {
      goto(`/pages/${pageId}`);
      return;
    } finally {
      loading = false;
    }
  });

  $effect(() => {
    if (activeTab === 'members' && !rolesLoaded && !loading) {
      loadRoles();
    }
  });

  async function loadRoles() {
    rolesLoading = true;
    try {
      roles = await getPageRoles(pageId);
      rolesLoaded = true;
    } catch {
      addToast('Failed to load page members', 'error');
    } finally {
      rolesLoading = false;
    }
  }

  async function handleRoleChange(role: PageRole, newRole: AssignableRole) {
    if (!canManage) return;
    try {
      // The backend has no role-update endpoint — revoke the old one
      // and grant the new one in sequence. Cheaper than adding a PATCH
      // since these rows are append-only audit records anyway.
      await removePageRole(pageId, role.id);
      const created = await addPageRole(pageId, role.identity_id, newRole);
      roles = roles.map((r) => (r.id === role.id ? created : r));
      addToast(`Role updated to ${newRole}`, 'success');
    } catch {
      addToast('Failed to update role', 'error');
      // Reload so the UI reflects whatever the server actually has.
      void loadRoles();
    }
  }

  async function handleRemoveRole(role: PageRole) {
    if (!canManage) return;
    if (!confirm(`Remove ${role.identity?.display_name || role.identity?.handle || 'this user'} from the page team?`)) {
      return;
    }
    try {
      await removePageRole(pageId, role.id);
      roles = roles.filter((r) => r.id !== role.id);
      addToast('Removed from page', 'success');
    } catch {
      addToast('Failed to remove role', 'error');
    }
  }

  function handleInviteSearch() {
    if (inviteTimeout) clearTimeout(inviteTimeout);
    const q = inviteQuery.trim();
    if (q.length < 2) {
      inviteResults = [];
      return;
    }
    inviteSearching = true;
    inviteTimeout = setTimeout(async () => {
      try {
        const res = await search(q, { type: 'accounts', limit: 10 });
        inviteResults = res.accounts;
      } catch {
        inviteResults = [];
      } finally {
        inviteSearching = false;
      }
    }, 250);
  }

  async function handleInvite(accountId: string) {
    if (inviting || !canManage) return;
    inviting = true;
    try {
      await invitePageManager(pageId, accountId);
      // Drop the invitee from the result list immediately so a quick
      // double-click can't re-fire the request and 422 on duplicate.
      inviteResults = inviteResults.filter((a) => a.id !== accountId);
      addToast('Invite sent', 'success');
    } catch (err: unknown) {
      const apiErr = err as { body?: { error?: string }; message?: string };
      const msg =
        apiErr?.body?.error === 'invite.disabled_by_recipient'
          ? "This user doesn't accept invites"
          : apiErr?.body?.error === 'invite.recipient_follows_only'
            ? 'Only people they follow can invite them'
            : 'Could not send invite';
      addToast(msg, 'error');
    } finally {
      inviting = false;
    }
  }
</script>

<svelte:head>
  <title>{displayName ? `${displayName} — Settings` : 'Page settings'} — {$instanceName}</title>
</svelte:head>

<div class="settings-page">
  {#if loading}
    <div class="page-loading"><Spinner /></div>
  {:else if pageData}
    <div class="page-header">
      <button type="button" class="back-btn" onclick={() => goto(`/pages/${pageId}`)} aria-label="Back to page">
        <span class="material-symbols-outlined rtl-mirror">arrow_back</span>
      </button>
      <div class="page-header-info">
        <h1 class="page-title">Manage {displayName}</h1>
        <p class="page-sub">Add admins, editors, or moderators. Invite collaborators to the page.</p>
      </div>
    </div>

    <Tabs {tabs} bind:active={activeTab}>
      {#if activeTab === 'members'}
        {#if rolesLoading}
          <div class="tab-loading"><Spinner /></div>
        {:else if roles.length === 0}
          <div class="tab-empty">
            <p class="empty-text">No additional managers yet</p>
            <p class="empty-sub">
              The page owner is always in charge. Invite people from the Invite tab to add admins, editors, or moderators.
            </p>
          </div>
        {:else}
          <ul class="member-mgmt-list">
            {#each roles as role (role.id)}
              <li class="member-mgmt-item">
                <div class="member-row">
                  <Avatar
                    src={role.identity?.avatar_url}
                    name={role.identity?.display_name || role.identity?.handle || ''}
                    size="sm"
                  />
                  <div class="member-details">
                    <span class="member-name-text">
                      {role.identity?.display_name || role.identity?.handle || 'Unknown'}
                    </span>
                    {#if role.identity?.handle}
                      <span class="member-handle-text">@{role.identity.handle}</span>
                    {/if}
                  </div>
                </div>
                <div class="member-actions">
                  {#if canManage}
                    <select
                      class="input role-select"
                      value={role.role}
                      onchange={(e) =>
                        handleRoleChange(role, (e.target as HTMLSelectElement).value as AssignableRole)}
                    >
                      <option value="moderator">Moderator</option>
                      <option value="editor">Editor</option>
                      <option value="admin">Admin</option>
                    </select>
                    <button
                      type="button"
                      class="btn btn-danger btn-sm"
                      onclick={() => handleRemoveRole(role)}
                    >
                      Remove
                    </button>
                  {:else}
                    <!-- Moderators see roles but cannot change them.
                         Promotions are an admin-tier action so a mod
                         can't silently elevate themselves or peers. -->
                    <span class="role-badge">{role.role}</span>
                  {/if}
                </div>
              </li>
            {/each}
          </ul>
        {/if}
      {:else if activeTab === 'invite'}
        <div class="invite-section">
          <input
            type="text"
            class="input"
            placeholder="Search users to invite as a manager…"
            bind:value={inviteQuery}
            oninput={handleInviteSearch}
          />

          {#if inviteSearching}
            <div class="tab-loading"><Spinner size={20} /></div>
          {:else if inviteResults.length > 0}
            <ul class="invite-results">
              {#each inviteResults as account (account.id)}
                <li class="invite-item">
                  <div class="invite-user">
                    <Avatar
                      src={account.avatar_url}
                      name={account.display_name || account.handle}
                      size="sm"
                    />
                    <div class="invite-user-info">
                      <span class="invite-user-name">
                        {account.display_name || account.handle}
                      </span>
                      <span class="invite-user-handle">@{account.handle}</span>
                    </div>
                  </div>
                  <button
                    type="button"
                    class="btn btn-primary btn-sm"
                    onclick={() => handleInvite(account.id)}
                    disabled={inviting}
                  >
                    Invite
                  </button>
                </li>
              {/each}
            </ul>
          {:else if inviteQuery.trim().length >= 2}
            <p class="empty-text" style="text-align: center; padding: var(--space-4);">
              No users found
            </p>
          {:else}
            <p class="invite-hint">
              Invitees can decide whether to accept the invitation. Once accepted, they get the role you assign here from the Members tab.
            </p>
          {/if}
        </div>
      {/if}
    </Tabs>
  {/if}
</div>

<style>
  .settings-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    width: 100%;
  }

  .page-loading {
    display: flex;
    justify-content: center;
    padding: var(--space-16);
  }

  .page-header {
    display: flex;
    align-items: flex-start;
    gap: var(--space-3);
    padding-block-end: var(--space-4);
    border-block-end: 1px solid var(--color-border);
    margin-block-end: var(--space-4);
  }

  .back-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    border: none;
    background: transparent;
    border-radius: var(--radius-full);
    color: var(--color-text-secondary);
    cursor: pointer;
    flex-shrink: 0;
  }

  .back-btn:hover {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .page-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
    margin: 0;
  }

  .page-sub {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    margin: var(--space-1) 0 0 0;
  }

  .tab-loading {
    display: flex;
    justify-content: center;
    padding: var(--space-8);
  }

  .tab-empty {
    text-align: center;
    padding: var(--space-8) var(--space-4);
  }

  .empty-text {
    font-size: var(--text-base);
    color: var(--color-text);
    font-weight: 600;
  }

  .empty-sub {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    margin-block-start: var(--space-1);
  }

  .member-mgmt-list,
  .invite-results {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .member-mgmt-item,
  .invite-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-3);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
  }

  .member-row,
  .invite-user {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    min-width: 0;
    flex: 1;
  }

  .member-details,
  .invite-user-info {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .member-name-text,
  .invite-user-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .member-handle-text,
  .invite-user-handle {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .member-actions {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-shrink: 0;
  }

  .role-select {
    width: auto;
    min-width: 120px;
    padding: var(--space-1) var(--space-2);
    font-size: var(--text-xs);
  }

  .role-badge {
    display: inline-flex;
    align-items: center;
    padding: var(--space-1) var(--space-3);
    border-radius: var(--radius-full);
    background: var(--color-surface-container, var(--color-surface));
    color: var(--color-text-secondary);
    font-size: var(--text-xs);
    font-weight: 600;
    text-transform: capitalize;
  }

  .invite-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .invite-hint {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    text-align: center;
    padding: var(--space-4);
  }
</style>
