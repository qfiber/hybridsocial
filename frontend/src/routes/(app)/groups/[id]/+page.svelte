<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { get } from 'svelte/store';
  import type { Post } from '$lib/api/types.js';
  import type { GroupDetail, GroupMember } from '$lib/api/groups.js';
  import { getGroup, getGroupTimeline, getGroupMembers, joinGroup, leaveGroup, updateGroup, deleteGroup, updateMemberRole, banMember } from '$lib/api/groups.js';
  import { authStore } from '$lib/stores/auth.js';
  import GroupHeader from '$lib/components/group/GroupHeader.svelte';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import FeedList from '$lib/components/feed/FeedList.svelte';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';

  let group = $state<GroupDetail | null>(null);
  let posts = $state<Post[]>([]);
  let members = $state<GroupMember[]>([]);
  let loading = $state(true);
  let postsLoading = $state(false);
  let membersLoading = $state(false);
  let hasMorePosts = $state(true);
  let hasMoreMembers = $state(true);
  let activeTab = $state('posts');
  let membersLoaded = $state(false);

  // Admin controls
  let showEditModal = $state(false);
  let showDeleteConfirm = $state(false);
  let showMemberActions = $state<string | null>(null);
  let editName = $state('');
  let editDescription = $state('');
  let editVisibility = $state('public');
  let editJoinPolicy = $state('open');
  let saving = $state(false);
  let deleting = $state(false);

  let groupId = $derived(page.params.id!);
  let currentUserId = $derived(get(authStore)?.user?.id);
  let isAdmin = $derived(group?.role === 'owner' || group?.role === 'admin');
  let isOwner = $derived(group?.role === 'owner');

  const tabs = [
    { id: 'posts', label: 'Posts' },
    { id: 'members', label: 'Members' },
    { id: 'about', label: 'About' }
  ];

  onMount(async () => {
    try {
      const [g, timeline] = await Promise.all([
        getGroup(groupId),
        getGroupTimeline(groupId)
      ]);
      group = g;
      posts = Array.isArray(timeline) ? timeline : (timeline as any).data || [];
      hasMorePosts = posts.length >= 20;
    } catch {
      // Error loading group
    } finally {
      loading = false;
    }
  });

  $effect(() => {
    if (activeTab === 'members' && !membersLoaded) {
      loadMembers();
    }
  });

  async function loadMembers() {
    membersLoading = true;
    try {
      const result = await getGroupMembers(groupId);
      members = Array.isArray(result) ? result : (result as any).data || [];
      hasMoreMembers = members.length >= 20;
      membersLoaded = true;
    } catch {
      // Error loading members
    } finally {
      membersLoading = false;
    }
  }

  async function loadMorePosts() {
    if (!hasMorePosts || postsLoading) return;
    postsLoading = true;
    try {
      const cursor = posts.length > 0 ? posts[posts.length - 1]?.id : undefined;
      const result = await getGroupTimeline(groupId, cursor);
      const data = Array.isArray(result) ? result : (result as any).data || [];
      posts = [...posts, ...data];
      hasMorePosts = data.length >= 20;
    } catch {
      // Error
    } finally {
      postsLoading = false;
    }
  }

  async function handleJoin() {
    if (!group) return;
    try {
      const result = await joinGroup(groupId);
      if (result.status === 'joined') {
        group = { ...group, is_member: true, member_count: group.member_count + 1, pending_request: false };
      } else {
        group = { ...group, pending_request: true };
      }
    } catch {}
  }

  async function handleLeave() {
    if (!group) return;
    try {
      await leaveGroup(groupId);
      group = { ...group, is_member: false, member_count: Math.max(0, group.member_count - 1), role: null };
    } catch {}
  }

  // --- Admin: Edit Group ---
  function openEdit() {
    if (!group) return;
    editName = group.name;
    editDescription = group.description || '';
    editVisibility = group.visibility || 'public';
    editJoinPolicy = group.join_policy || 'open';
    showEditModal = true;
  }

  async function saveEdit() {
    saving = true;
    try {
      const updated = await updateGroup(groupId, {
        name: editName,
        description: editDescription,
        visibility: editVisibility as 'public' | 'private' | 'secret',
        join_policy: editJoinPolicy as 'open' | 'approval' | 'invite'
      });
      group = { ...group, ...updated };
      showEditModal = false;
    } catch {}
    saving = false;
  }

  // --- Admin: Delete Group ---
  async function confirmDeleteGroup() {
    deleting = true;
    try {
      await deleteGroup(groupId);
      goto('/groups');
    } catch {}
    deleting = false;
  }

  // --- Admin: Member Management ---
  async function handleChangeRole(memberId: string, newRole: string) {
    try {
      await updateMemberRole(groupId, memberId, newRole);
      members = members.map(m =>
        m.id === memberId ? { ...m, role: newRole as GroupMember['role'] } : m
      );
      showMemberActions = null;
    } catch {}
  }

  async function handleRemoveMember(memberId: string) {
    if (!confirm('Remove this member from the group?')) return;
    try {
      await banMember(groupId, memberId);
      members = members.filter(m => m.id !== memberId);
      if (group) group = { ...group, member_count: Math.max(0, group.member_count - 1) };
      showMemberActions = null;
    } catch {}
  }

  function openSettings() {
    goto(`/groups/${groupId}/settings`);
  }

  function roleBadge(role: string): string {
    switch (role) {
      case 'owner': return 'Owner';
      case 'admin': return 'Admin';
      case 'moderator': return 'Mod';
      default: return '';
    }
  }
</script>

<svelte:head>
  <title>{group?.name ?? 'Group'} - HybridSocial</title>
</svelte:head>

<div class="group-detail-page">
  {#if loading}
    <div class="page-loading"><Spinner /></div>
  {:else if group}
    <GroupHeader
      {group}
      onjoin={handleJoin}
      onleave={handleLeave}
      onsettings={openSettings}
    />

    {#if isAdmin}
      <div class="admin-bar">
        <button type="button" class="btn btn-outline btn-sm" onclick={openEdit}>
          Edit Group
        </button>
        {#if isOwner}
          <button type="button" class="btn btn-outline btn-sm btn-danger-outline" onclick={() => showDeleteConfirm = true}>
            Delete Group
          </button>
        {/if}
      </div>
    {/if}

    <div class="group-content">
      <Tabs {tabs} bind:active={activeTab}>
        {#if activeTab === 'posts'}
          <FeedList
            {posts}
            loading={postsLoading}
            hasMore={hasMorePosts}
            emptyMessage="No posts in this group yet"
            onloadmore={loadMorePosts}
          />
        {:else if activeTab === 'members'}
          {#if membersLoading}
            <div class="tab-loading"><Spinner /></div>
          {:else if members.length === 0}
            <div class="tab-empty"><p class="empty-text">No members</p></div>
          {:else}
            <ul class="member-list">
              {#each members as member (member.id || member.identity_id)}
                {@const acct = member.account || {}}
                <li class="member-item">
                  <a href="/@{acct.handle || ''}" class="member-link">
                    <Avatar
                      src={acct.avatar_url}
                      name={acct.display_name || acct.handle || 'Member'}
                      size="md"
                    />
                    <div class="member-info">
                      <span class="member-name">{acct.display_name || acct.handle || 'Member'}</span>
                      <span class="member-handle">@{acct.handle || '...'}</span>
                    </div>
                  </a>

                  {#if member.role && member.role !== 'member'}
                    <span class="role-badge role-{member.role}">{roleBadge(member.role)}</span>
                  {/if}

                  {#if isAdmin && member.identity_id !== currentUserId && member.role !== 'owner'}
                    <div class="member-actions-wrapper">
                      <button
                        type="button"
                        class="member-actions-btn"
                        onclick={(e) => { e.stopPropagation(); showMemberActions = showMemberActions === member.id ? null : member.id!; }}
                        aria-label="Member actions"
                      >
                        ···
                      </button>

                      {#if showMemberActions === member.id}
                        <div class="member-actions-menu">
                          {#if member.role !== 'admin'}
                            <button type="button" class="menu-item" onclick={() => handleChangeRole(member.id!, 'admin')}>
                              Make Admin
                            </button>
                          {/if}
                          {#if member.role !== 'moderator'}
                            <button type="button" class="menu-item" onclick={() => handleChangeRole(member.id!, 'moderator')}>
                              Make Moderator
                            </button>
                          {/if}
                          {#if member.role !== 'member'}
                            <button type="button" class="menu-item" onclick={() => handleChangeRole(member.id!, 'member')}>
                              Remove Role
                            </button>
                          {/if}
                          <button type="button" class="menu-item menu-item-danger" onclick={() => handleRemoveMember(member.id!)}>
                            Remove from Group
                          </button>
                        </div>
                      {/if}
                    </div>
                  {/if}
                </li>
              {/each}
            </ul>
          {/if}
        {:else if activeTab === 'about'}
          <div class="about-section">
            {#if group.description}
              <div class="about-block">
                <h3 class="about-heading">Description</h3>
                <p class="about-text">{group.description}</p>
              </div>
            {/if}

            <div class="about-block">
              <h3 class="about-heading">Info</h3>
              <dl class="info-list">
                <div class="info-row">
                  <dt class="info-label">Created</dt>
                  <dd class="info-value">{new Date(group.created_at).toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' })}</dd>
                </div>
                <div class="info-row">
                  <dt class="info-label">Visibility</dt>
                  <dd class="info-value" style="text-transform: capitalize">{group.visibility}</dd>
                </div>
                <div class="info-row">
                  <dt class="info-label">Join Policy</dt>
                  <dd class="info-value" style="text-transform: capitalize">{group.join_policy}</dd>
                </div>
                <div class="info-row">
                  <dt class="info-label">Members</dt>
                  <dd class="info-value">{group.member_count}</dd>
                </div>
              </dl>
            </div>
          </div>
        {/if}
      </Tabs>
    </div>
  {:else}
    <div class="page-error"><p>Group not found</p></div>
  {/if}
</div>

<!-- Edit Group Modal -->
{#if showEditModal}
  <div class="modal-overlay" onclick={() => showEditModal = false}>
    <div class="modal-dialog" onclick={(e) => e.stopPropagation()}>
      <h2 class="modal-title">Edit Group</h2>

      <div class="form-group">
        <label class="form-label" for="edit-name">Name</label>
        <input id="edit-name" type="text" class="input" bind:value={editName} />
      </div>

      <div class="form-group">
        <label class="form-label" for="edit-desc">Description</label>
        <textarea id="edit-desc" class="textarea" rows="4" bind:value={editDescription}></textarea>
      </div>

      <div class="form-group">
        <label class="form-label" for="edit-vis">Visibility</label>
        <select id="edit-vis" class="input" bind:value={editVisibility}>
          <option value="public">Public</option>
          <option value="private">Private</option>
          <option value="local_only">Local Only</option>
        </select>
      </div>

      <div class="form-group">
        <label class="form-label" for="edit-policy">Join Policy</label>
        <select id="edit-policy" class="input" bind:value={editJoinPolicy}>
          <option value="open">Open</option>
          <option value="screening">Screening</option>
          <option value="approval">Approval Required</option>
          <option value="invite_only">Invite Only</option>
        </select>
      </div>

      <div class="modal-actions">
        <button type="button" class="btn btn-outline" onclick={() => showEditModal = false}>Cancel</button>
        <button type="button" class="btn btn-primary" onclick={saveEdit} disabled={saving || !editName.trim()}>
          {saving ? 'Saving...' : 'Save Changes'}
        </button>
      </div>
    </div>
  </div>
{/if}

<!-- Delete Confirmation -->
{#if showDeleteConfirm}
  <div class="modal-overlay" onclick={() => showDeleteConfirm = false}>
    <div class="modal-dialog" onclick={(e) => e.stopPropagation()}>
      <h2 class="modal-title">Delete Group?</h2>
      <p class="modal-message">This will permanently delete <strong>{group?.name}</strong> and all its content. This action cannot be undone.</p>
      <div class="modal-actions">
        <button type="button" class="btn btn-outline" onclick={() => showDeleteConfirm = false}>Cancel</button>
        <button type="button" class="btn btn-danger" onclick={confirmDeleteGroup} disabled={deleting}>
          {deleting ? 'Deleting...' : 'Delete Group'}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .group-detail-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    width: 100%;
  }

  .page-loading, .page-error {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-16);
    color: var(--color-text-tertiary);
  }

  .admin-bar {
    display: flex;
    gap: var(--space-2);
    padding: var(--space-3) var(--space-4);
    border-block-end: 1px solid var(--color-border);
    background: var(--color-surface);
    border-radius: var(--radius-md);
    margin-block-start: var(--space-2);
  }

  .btn-danger-outline {
    color: var(--color-danger);
    border-color: var(--color-danger);
  }
  .btn-danger-outline:hover { background: var(--color-danger-soft); }

  .btn-danger {
    background: var(--color-danger);
    color: white;
    border: none;
    padding: var(--space-2) var(--space-4);
    border-radius: var(--radius-md);
    font-weight: 600;
    cursor: pointer;
  }
  .btn-danger:hover { opacity: 0.9; }

  .group-content { margin-block-start: var(--space-4); }
  .tab-loading { display: flex; justify-content: center; padding: var(--space-8); }
  .tab-empty { text-align: center; padding: var(--space-12); }
  .empty-text { color: var(--color-text-tertiary); }

  .member-list { display: flex; flex-direction: column; }
  .member-item {
    display: flex;
    align-items: center;
    padding: var(--space-3) var(--space-2);
    border-block-end: 1px solid var(--color-border);
  }
  .member-item:last-child { border-block-end: none; }

  .member-link {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    flex: 1;
    min-width: 0;
    text-decoration: none;
    color: inherit;
  }
  .member-link:hover { text-decoration: none; }

  .member-info { display: flex; flex-direction: column; min-width: 0; }
  .member-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .member-handle { font-size: var(--text-xs); color: var(--color-text-secondary); }

  .role-badge {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: var(--space-1) var(--space-2);
    border-radius: var(--radius-full);
    flex-shrink: 0;
    margin-inline-start: var(--space-2);
  }
  .role-owner { background: var(--color-warning-soft); color: var(--color-warning); }
  .role-admin { background: var(--color-info-soft); color: var(--color-info); }
  .role-moderator { background: var(--color-success-soft); color: var(--color-success); }

  .member-actions-wrapper { position: relative; margin-inline-start: var(--space-2); }
  .member-actions-btn {
    background: none;
    border: none;
    padding: var(--space-1) var(--space-2);
    color: var(--color-text-secondary);
    cursor: pointer;
    font-size: var(--text-lg);
    border-radius: var(--radius-md);
  }
  .member-actions-btn:hover { background: var(--color-surface); }

  .member-actions-menu {
    position: absolute;
    inset-inline-end: 0;
    inset-block-start: 100%;
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow-lg);
    z-index: var(--z-dropdown);
    min-width: 180px;
    overflow: hidden;
  }

  .menu-item {
    display: block;
    width: 100%;
    padding: var(--space-2) var(--space-3);
    background: none;
    border: none;
    text-align: start;
    font-size: var(--text-sm);
    color: var(--color-text);
    cursor: pointer;
  }
  .menu-item:hover { background: var(--color-surface); }
  .menu-item-danger { color: var(--color-danger); }
  .menu-item-danger:hover { background: var(--color-danger-soft); }

  .about-section { display: flex; flex-direction: column; gap: var(--space-6); }
  .about-block { display: flex; flex-direction: column; gap: var(--space-2); }
  .about-heading {
    font-size: var(--text-sm);
    font-weight: 700;
    color: var(--color-text);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .about-text { font-size: var(--text-sm); color: var(--color-text-secondary); line-height: 1.6; }

  .info-list { display: flex; flex-direction: column; gap: var(--space-2); }
  .info-row { display: flex; justify-content: space-between; align-items: center; }
  .info-label { font-size: var(--text-sm); color: var(--color-text-secondary); }
  .info-value { font-size: var(--text-sm); color: var(--color-text); font-weight: 500; }

  /* Modal styles */
  .modal-overlay {
    position: fixed;
    inset: 0;
    background: var(--color-overlay, rgba(0,0,0,0.5));
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: var(--z-modal, 40);
  }
  .modal-dialog {
    background: var(--color-surface-raised, #fff);
    border-radius: var(--radius-lg);
    padding: var(--space-6);
    max-width: 480px;
    width: 90%;
    box-shadow: var(--shadow-xl);
  }
  .modal-title {
    font-size: var(--text-lg);
    font-weight: 600;
    margin-block-end: var(--space-4);
  }
  .modal-message {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-6);
    line-height: 1.6;
  }
  .form-group { margin-block-end: var(--space-4); }
  .form-label {
    display: block;
    font-size: var(--text-sm);
    font-weight: 500;
    margin-block-end: var(--space-1);
  }
  .modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3);
    margin-block-start: var(--space-6);
  }
</style>
