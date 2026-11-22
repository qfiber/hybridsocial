<script lang="ts">
  import { onMount } from 'svelte';
  import type { Post } from '$lib/api/types.js';
  import { getScheduledPosts, deleteScheduledPost, updateScheduledPost } from '$lib/api/statuses.js';
  import { fullDateTime } from '$lib/utils/time.js';
  import { addToast } from '$lib/stores/toast.js';
  import AsyncState from '$lib/components/ui/AsyncState.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';
  import { instanceName } from '$lib/stores/instance.js';

  let posts: Post[] = $state([]);
  let loading = $state(true);
  let error = $state('');

  // Edit state
  let editingId: string | null = $state(null);
  let editContent = $state('');
  let editScheduledAt = $state('');
  let editSaving = $state(false);

  // Delete confirmation
  let deletingId: string | null = $state(null);
  let showDeleteModal = $state(false);
  let deleting = $state(false);

  async function loadScheduledPosts() {
    loading = true;
    error = '';
    try {
      const result = await getScheduledPosts();
      posts = Array.isArray(result) ? result : [];
    } catch {
      error = 'Failed to load scheduled posts.';
    } finally {
      loading = false;
    }
  }

  function startEdit(post: Post) {
    editingId = post.id;
    editContent = post.content;
    editScheduledAt = (post as any).scheduled_at || '';
  }

  function cancelEdit() {
    editingId = null;
    editContent = '';
    editScheduledAt = '';
  }

  async function saveEdit() {
    if (!editingId || editSaving) return;
    editSaving = true;
    try {
      await updateScheduledPost(editingId, {
        content: editContent,
        scheduled_at: editScheduledAt || undefined,
      });
      editingId = null;
      addToast('Scheduled post updated', 'success');
      await loadScheduledPosts();
    } catch {
      addToast('Could not update scheduled post', 'error');
    } finally {
      editSaving = false;
    }
  }

  function confirmDelete(id: string) {
    deletingId = id;
    showDeleteModal = true;
  }

  async function handleDelete() {
    if (!deletingId || deleting) return;
    deleting = true;
    const id = deletingId;
    const prev = posts;
    // Optimistic removal; restore on failure.
    posts = posts.filter((p) => p.id !== id);
    try {
      await deleteScheduledPost(id);
      addToast('Scheduled post deleted', 'success');
      showDeleteModal = false;
      deletingId = null;
    } catch {
      posts = prev;
      addToast('Could not delete scheduled post', 'error');
    } finally {
      deleting = false;
    }
  }

  function getVisibilityLabel(visibility: string): string {
    switch (visibility) {
      case 'public': return 'Public';
      case 'followers': return 'Followers only';
      case 'direct': return 'Direct';
      default: return visibility;
    }
  }

  function getVisibilityIcon(visibility: string): string {
    switch (visibility) {
      case 'public': return 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z';
      case 'followers': return 'M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10';
      case 'direct': return 'M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z';
      default: return '';
    }
  }

  onMount(() => {
    loadScheduledPosts();
  });
</script>

<svelte:head>
  <title>Scheduled Posts - {$instanceName}</title>
</svelte:head>

<div class="scheduled-page">
  <div class="sticky-section-head page-header">
    <h1 class="page-title">Scheduled Posts</h1>
  </div>

  <AsyncState
    {loading}
    {error}
    isEmpty={posts.length === 0}
    emptyTitle="No scheduled posts"
    emptyText="Posts you schedule for later will appear here."
    onretry={loadScheduledPosts}
  >
    {#snippet skeleton()}
      <div class="scheduled-list" aria-hidden="true">
        {#each Array(3) as _, i (i)}
          <div class="scheduled-card">
            <div class="skel-line lg"></div>
            <div class="skel-line sm"></div>
            <div class="skel-meta"></div>
          </div>
        {/each}
      </div>
    {/snippet}

    <div class="scheduled-list">
      {#each posts as post (post.id)}
        <div class="scheduled-card">
          {#if editingId === post.id}
            <div class="edit-form">
              <textarea
                class="edit-textarea"
                bind:value={editContent}
                rows="3"
                aria-label="Edit post content"
              ></textarea>
              <div class="edit-time-row">
                <label class="edit-time-label" for="edit-time-{post.id}">Scheduled time</label>
                <input
                  id="edit-time-{post.id}"
                  type="datetime-local"
                  class="edit-time-input"
                  bind:value={editScheduledAt}
                />
              </div>
              <div class="edit-actions">
                <button type="button" class="btn btn-ghost btn-sm" onclick={cancelEdit}>Cancel</button>
                <button type="button" class="btn btn-primary btn-sm" onclick={saveEdit} disabled={editSaving}>
                  {editSaving ? 'Saving...' : 'Save'}
                </button>
              </div>
            </div>
          {:else}
            <div class="card-content">
              <p class="content-preview">{post.content}</p>
            </div>
            <div class="card-meta">
              <div class="meta-item">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>
                </svg>
                <span>{(post as any).scheduled_at ? fullDateTime((post as any).scheduled_at) : 'Not set'}</span>
              </div>
              <div class="meta-item">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <path d={getVisibilityIcon(post.visibility)} />
                </svg>
                <span>{getVisibilityLabel(post.visibility)}</span>
              </div>
            </div>
            <div class="card-actions">
              <button type="button" class="btn btn-ghost btn-sm" onclick={() => startEdit(post)}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/>
                  <path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/>
                </svg>
                Edit
              </button>
              <button type="button" class="btn btn-ghost btn-sm btn-danger" onclick={() => confirmDelete(post.id)}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                  <polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2"/>
                </svg>
                Delete
              </button>
            </div>
          {/if}
        </div>
      {/each}
    </div>
  </AsyncState>
</div>

<Modal bind:open={showDeleteModal} title="Cancel scheduled post?" onclose={() => { deletingId = null; }}>
  <p class="confirm-message">This scheduled post will be permanently deleted and will not be published.</p>
  <div class="confirm-actions">
    <button type="button" class="btn btn-ghost" onclick={() => (showDeleteModal = false)}>Keep it</button>
    <button type="button" class="btn btn-danger" onclick={handleDelete} disabled={deleting}>
      {deleting ? 'Deleting…' : 'Delete'}
    </button>
  </div>
</Modal>

<style>
  .scheduled-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
  }

  .page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-end: var(--space-4);
  }

  .page-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
  }

  .scheduled-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .scheduled-card {
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-4);
  }

  .card-content {
    margin-block-end: var(--space-3);
  }

  .content-preview {
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: var(--leading-relaxed);
    white-space: pre-wrap;
    word-break: break-word;
  }

  .card-meta {
    display: flex;
    gap: var(--space-4);
    margin-block-end: var(--space-3);
  }

  .meta-item {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .card-actions {
    display: flex;
    gap: var(--space-2);
    border-block-start: 1px solid var(--color-border);
    padding-block-start: var(--space-3);
  }

  .btn {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    padding: var(--space-2) var(--space-3);
    border: none;
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-weight: 500;
    cursor: pointer;
    transition: background var(--transition-fast);
  }

  .btn-sm {
    padding: var(--space-1) var(--space-2);
    font-size: var(--text-xs);
  }

  .btn-ghost {
    background: transparent;
    color: var(--color-text-secondary);
  }

  .btn-ghost:hover {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .btn-primary {
    background: var(--color-primary);
    color: var(--color-text-inverse);
  }

  .btn-primary:hover {
    background: var(--color-primary-hover);
  }

  .btn-primary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .btn-danger {
    color: var(--color-danger);
  }

  .btn-danger:hover {
    background: var(--color-danger-light, rgba(239, 68, 68, 0.1));
  }

  /* Skeleton lines shown inside placeholder cards while loading. */
  .skel-line,
  .skel-meta {
    height: 12px;
    border-radius: var(--radius-sm);
    background: var(--color-border);
    margin-block-end: var(--space-3);
  }

  .skel-line.lg { width: 85%; }
  .skel-line.sm { width: 55%; }
  .skel-meta { width: 35%; height: 10px; margin-block-end: 0; }

  @media (prefers-reduced-motion: no-preference) {
    .skel-line,
    .skel-meta {
      animation: skel-pulse 1.5s ease-in-out infinite;
    }
  }

  @keyframes skel-pulse {
    0%, 100% { opacity: 0.4; }
    50% { opacity: 0.7; }
  }

  /* Edit form */
  .edit-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .edit-textarea {
    width: 100%;
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-family: inherit;
    color: var(--color-text);
    background: var(--color-bg);
    resize: vertical;
  }

  .edit-textarea:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .edit-time-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .edit-time-label {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    white-space: nowrap;
  }

  .edit-time-input {
    padding: var(--space-1) var(--space-2);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-xs);
    color: var(--color-text);
    background: var(--color-bg);
  }

  .edit-time-input:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .edit-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
  }

  /* Confirm dialog (rendered inside the shared Modal) */
  .confirm-message {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-4);
  }

  .confirm-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3);
  }
</style>
