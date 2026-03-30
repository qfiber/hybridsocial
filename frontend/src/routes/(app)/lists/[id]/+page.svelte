<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import type { Post, Identity } from '$lib/api/types.js';
  import type { List } from '$lib/api/lists.js';
  import {
    getList,
    updateList,
    deleteList,
    getListTimeline,
    getListMembers,
    addListMember,
    removeListMember
  } from '$lib/api/lists.js';
  import { search } from '$lib/api/search.js';
  import FeedList from '$lib/components/feed/FeedList.svelte';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';

  let list = $state<List | null>(null);
  let posts = $state<Post[]>([]);
  let members = $state<Identity[]>([]);
  let loading = $state(true);
  let postsLoading = $state(false);
  let postsCursor = $state<string | null>(null);
  let hasMorePosts = $state(true);

  // Edit title
  let editingTitle = $state(false);
  let editTitle = $state('');
  let savingTitle = $state(false);

  // Manage members
  let showMembers = $state(false);
  let membersLoading = $state(false);
  let membersLoaded = $state(false);

  // Add member
  let addQuery = $state('');
  let addResults = $state<Identity[]>([]);
  let addSearching = $state(false);
  let adding = $state(false);
  let addTimeout: ReturnType<typeof setTimeout> | undefined;

  let listId = $derived(page.params.id!);

  onMount(async () => {
    try {
      const [l, timeline] = await Promise.all([
        getList(listId),
        getListTimeline(listId)
      ]);
      list = l;
      editTitle = l.title || l.name;
      posts = timeline.data;
      postsCursor = timeline.next_cursor;
      hasMorePosts = !!timeline.next_cursor;
    } catch {
      // Error loading
    } finally {
      loading = false;
    }
  });

  async function loadMorePosts() {
    if (!postsCursor || !hasMorePosts || postsLoading) return;
    postsLoading = true;
    try {
      const result = await getListTimeline(listId, postsCursor);
      posts = [...posts, ...result.data];
      postsCursor = result.next_cursor;
      hasMorePosts = !!result.next_cursor;
    } catch {
      // Error
    } finally {
      postsLoading = false;
    }
  }

  function startEditTitle() {
    if (list) {
      editTitle = list.title || list.name;
      editingTitle = true;
    }
  }

  async function saveTitle() {
    const t = editTitle.trim();
    if (!t || !list || savingTitle) return;
    savingTitle = true;
    try {
      const updated = await updateList(listId, t);
      list = updated;
      editingTitle = false;
    } catch {
      // Error
    } finally {
      savingTitle = false;
    }
  }

  function cancelEditTitle() {
    editingTitle = false;
    if (list) editTitle = list.title || list.name;
  }

  async function handleDelete() {
    if (!confirm('Delete this list? This cannot be undone.')) return;
    try {
      await deleteList(listId);
      goto('/lists');
    } catch {
      // Error
    }
  }

  async function openMembers() {
    showMembers = true;
    if (!membersLoaded) {
      membersLoading = true;
      try {
        const result = await getListMembers(listId);
        members = result.data;
        membersLoaded = true;
      } catch {
        // Error
      } finally {
        membersLoading = false;
      }
    }
  }

  async function handleRemoveMember(accountId: string) {
    try {
      await removeListMember(listId, accountId);
      members = members.filter((m) => m.id !== accountId);
      if (list) {
        list = { ...list, member_count: Math.max(0, list.member_count - 1) };
      }
    } catch {
      // Error
    }
  }

  function handleAddSearch() {
    if (addTimeout) clearTimeout(addTimeout);
    const q = addQuery.trim();
    if (q.length < 2) {
      addResults = [];
      return;
    }
    addSearching = true;
    addTimeout = setTimeout(async () => {
      try {
        const res = await search(q, { type: 'accounts', limit: 10 });
        // Filter out existing members
        const memberIds = new Set(members.map((m) => m.id));
        addResults = res.accounts.filter((a) => !memberIds.has(a.id));
      } catch {
        addResults = [];
      } finally {
        addSearching = false;
      }
    }, 300);
  }

  async function handleAddMember(account: Identity) {
    adding = true;
    try {
      await addListMember(listId, account.id);
      members = [...members, account];
      addResults = addResults.filter((a) => a.id !== account.id);
      if (list) {
        list = { ...list, member_count: list.member_count + 1 };
      }
    } catch {
      // Error
    } finally {
      adding = false;
    }
  }

  function goBack() {
    goto('/lists');
  }
</script>

<svelte:head>
  <title>{list?.title ?? 'List'} - HybridSocial</title>
</svelte:head>

<div class="list-detail-page">
  {#if loading}
    <div class="page-loading">
      <Spinner />
    </div>
  {:else if list}
    <div class="page-header">
      <button type="button" class="back-btn" onclick={goBack} aria-label="Back to lists">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <polyline points="15 18 9 12 15 6" />
        </svg>
      </button>

      <div class="header-center">
        {#if editingTitle}
          <form class="edit-title-form" onsubmit={(e) => { e.preventDefault(); saveTitle(); }}>
            <input
              type="text"
              class="input edit-title-input"
              bind:value={editTitle}
              required
            />
            <button type="submit" class="btn btn-primary btn-sm" disabled={savingTitle}>Save</button>
            <button type="button" class="btn btn-ghost btn-sm" onclick={cancelEditTitle}>Cancel</button>
          </form>
        {:else}
          <button type="button" class="title-btn" onclick={startEditTitle} title="Click to edit">
            <h1 class="page-title">{list.title}</h1>
            <svg class="edit-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7" />
              <path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z" />
            </svg>
          </button>
        {/if}
      </div>

      <div class="header-actions">
        <button type="button" class="btn btn-outline btn-sm" onclick={openMembers}>
          Members ({list.member_count})
        </button>
        <button type="button" class="btn btn-ghost btn-sm" onclick={handleDelete} aria-label="Delete list">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-danger)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="3 6 5 6 21 6" />
            <path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2" />
          </svg>
        </button>
      </div>
    </div>

    <FeedList
      {posts}
      loading={postsLoading}
      hasMore={hasMorePosts}
      emptyMessage="No posts from list members yet. Add some members to get started."
      onloadmore={loadMorePosts}
    />
  {:else}
    <div class="page-error">
      <p>List not found</p>
    </div>
  {/if}
</div>

<Modal bind:open={showMembers} title="List Members">
  <div class="members-modal">
    <div class="add-member-section">
      <input
        type="text"
        class="input"
        placeholder="Search users to add..."
        bind:value={addQuery}
        oninput={handleAddSearch}
      />
      {#if addSearching}
        <div class="search-loading"><Spinner size={20} /></div>
      {:else if addResults.length > 0}
        <ul class="add-results">
          {#each addResults as account (account.id)}
            <li class="add-result-item">
              <div class="user-row">
                <Avatar src={account.avatar_url} name={account.display_name || account.handle} size="sm" />
                <div class="user-info-col">
                  <span class="user-display-name">{account.display_name || account.handle}</span>
                  <span class="user-handle-text">@{account.handle}</span>
                </div>
              </div>
              <button type="button" class="btn btn-primary btn-sm" onclick={() => handleAddMember(account)} disabled={adding}>
                Add
              </button>
            </li>
          {/each}
        </ul>
      {/if}
    </div>

    <div class="members-divider"></div>

    {#if membersLoading}
      <div class="search-loading"><Spinner /></div>
    {:else if members.length === 0}
      <p class="no-members-text">No members in this list</p>
    {:else}
      <ul class="member-list">
        {#each members as member (member.id)}
          <li class="member-item">
            <a href="/@{member.handle}" class="user-row user-row-link">
              <Avatar src={member.avatar_url} name={member.display_name || member.handle} size="sm" />
              <div class="user-info-col">
                <span class="user-display-name">{member.display_name || member.handle}</span>
                <span class="user-handle-text">@{member.handle}</span>
              </div>
            </a>
            <button type="button" class="btn btn-ghost btn-sm remove-btn" onclick={() => handleRemoveMember(member.id)} aria-label="Remove {member.handle} from list">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
              </svg>
            </button>
          </li>
        {/each}
      </ul>
    {/if}
  </div>
</Modal>

<style>
  .list-detail-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    width: 100%;
  }

  .page-loading,
  .page-error {
    display: flex;
    justify-content: center;
    padding: var(--space-16);
    color: var(--color-text-tertiary);
  }

  .page-header {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding-block-end: var(--space-4);
    border-block-end: 1px solid var(--color-border);
    margin-block-end: var(--space-4);
    flex-wrap: wrap;
  }

  .back-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    border: none;
    background: none;
    border-radius: var(--radius-full);
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: background var(--transition-fast);
    flex-shrink: 0;
  }

  .back-btn:hover {
    background: var(--color-surface);
  }

  .header-center {
    flex: 1;
    min-width: 0;
  }

  .title-btn {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    border: none;
    background: none;
    cursor: pointer;
    padding: var(--space-1) var(--space-2);
    border-radius: var(--radius-md);
    transition: background var(--transition-fast);
  }

  .title-btn:hover {
    background: var(--color-surface);
  }

  .page-title {
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-text);
  }

  .edit-icon {
    color: var(--color-text-tertiary);
    flex-shrink: 0;
  }

  .edit-title-form {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .edit-title-input {
    flex: 1;
    min-width: 120px;
  }

  .header-actions {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-shrink: 0;
  }

  .members-modal {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .add-member-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .search-loading {
    display: flex;
    justify-content: center;
    padding: var(--space-4);
  }

  .add-results,
  .member-list {
    display: flex;
    flex-direction: column;
  }

  .add-result-item,
  .member-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-2) 0;
    border-block-end: 1px solid var(--color-border);
  }

  .add-result-item:last-child,
  .member-item:last-child {
    border-block-end: none;
  }

  .user-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    min-width: 0;
  }

  .user-row-link {
    text-decoration: none;
    color: inherit;
  }

  .user-row-link:hover {
    text-decoration: none;
  }

  .user-info-col {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .user-display-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .user-handle-text {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .members-divider {
    height: 1px;
    background: var(--color-border);
  }

  .no-members-text {
    text-align: center;
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    padding: var(--space-4);
  }

  .remove-btn {
    color: var(--color-text-tertiary);
  }

  .remove-btn:hover {
    color: var(--color-danger);
  }
</style>
