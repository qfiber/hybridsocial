<script lang="ts">
  import { instanceName } from '$lib/stores/instance.js';
  import { onMount } from 'svelte';
  import type { PostDraft } from '$lib/api/types.js';
  import { listDrafts, deleteDraft } from '$lib/api/drafts.js';
  import { relativeTime, fullDateTime } from '$lib/utils/time.js';
  import { addToast } from '$lib/stores/toast.js';
  import AsyncState from '$lib/components/ui/AsyncState.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';

  let drafts: PostDraft[] = $state([]);
  let loading = $state(true);
  let error = $state('');

  // Delete confirmation
  let draftToDelete: PostDraft | null = $state(null);
  let showDeleteModal = $state(false);
  let deleting = $state(false);

  async function load() {
    loading = true;
    error = '';
    try {
      drafts = await listDrafts();
    } catch {
      error = 'Failed to load drafts.';
    } finally {
      loading = false;
    }
  }

  function resume(draft: PostDraft) {
    // Opening the composer with a draftId lets the composer fetch the
    // full draft (so subsequent state updates go through the same path
    // as an open-composer event from anywhere else).
    window.dispatchEvent(
      new CustomEvent('open-composer', { detail: { draftId: draft.id } }),
    );
  }

  function confirmDelete(draft: PostDraft) {
    draftToDelete = draft;
    showDeleteModal = true;
  }

  async function handleDelete() {
    if (!draftToDelete || deleting) return;
    deleting = true;
    const target = draftToDelete;
    const prev = drafts;
    // Optimistic removal; restore on failure. Note this is a per-row
    // action, so failures must NOT touch the page-level `error` state
    // (that would replace the whole list with the error view).
    drafts = drafts.filter((d) => d.id !== target.id);
    try {
      await deleteDraft(target.id);
      addToast('Draft deleted', 'success');
      showDeleteModal = false;
      draftToDelete = null;
    } catch {
      drafts = prev;
      addToast('Could not delete draft', 'error');
    } finally {
      deleting = false;
    }
  }

  function preview(draft: PostDraft): string {
    const text = (draft.content || '').trim();
    if (text.length === 0) {
      if (draft.media_ids?.length) return `(${draft.media_ids.length} attachment${draft.media_ids.length > 1 ? 's' : ''})`;
      return '(empty)';
    }
    return text.length > 140 ? text.slice(0, 140) + '…' : text;
  }

  onMount(load);
</script>

<svelte:head>
  <title>Drafts — {$instanceName}</title>
</svelte:head>

<div class="drafts-page">
  <div class="sticky-section-head page-header">
    <h1 class="page-title">Drafts</h1>
    <p class="page-sub">Saved post drafts. Resume to continue editing, or delete to discard.</p>
  </div>

  <AsyncState
    {loading}
    {error}
    isEmpty={drafts.length === 0}
    onretry={load}
  >
    {#snippet skeleton()}
      <ul class="drafts-list" aria-hidden="true">
        {#each Array(3) as _, i (i)}
          <li class="draft-card">
            <div class="draft-body">
              <div class="skel-line lg"></div>
              <div class="skel-line sm"></div>
              <div class="skel-meta"></div>
            </div>
          </li>
        {/each}
      </ul>
    {/snippet}

    {#snippet empty()}
      <div class="state-center empty">
        <span class="material-symbols-outlined empty-icon">edit_note</span>
        <p class="empty-text">No drafts yet</p>
        <p class="empty-sub">Use <strong>Save draft</strong> in the composer to save in-flight posts here.</p>
      </div>
    {/snippet}

    <ul class="drafts-list">
      {#each drafts as draft (draft.id)}
        <li class="draft-card">
          <div class="draft-body">
            {#if draft.group}
              <a class="draft-target draft-target-group" href={`/groups/${draft.group.id}`}>
                <span class="material-symbols-outlined draft-target-icon" aria-hidden="true">groups</span>
                <span class="draft-target-label">Posting to</span>
                <span class="draft-target-name">{draft.group.name}</span>
              </a>
            {:else if draft.page}
              <a class="draft-target draft-target-page" href={`/@${draft.page.id}`}>
                <span class="material-symbols-outlined draft-target-icon" aria-hidden="true">description</span>
                <span class="draft-target-label">Posting on</span>
                <span class="draft-target-name">{draft.page.name}</span>
              </a>
            {/if}
            {#if draft.spoiler_text}
              <p class="draft-cw">CW: {draft.spoiler_text}</p>
            {/if}
            <p class="draft-content">{preview(draft)}</p>
            <div class="draft-meta">
              <span class="draft-visibility">{draft.visibility}</span>
              <span class="draft-sep">·</span>
              <time title={fullDateTime(draft.updated_at)}>{relativeTime(draft.updated_at)}</time>
              {#if draft.media_ids?.length}
                <span class="draft-sep">·</span>
                <span>{draft.media_ids.length} media</span>
              {/if}
              {#if draft.poll_options?.length}
                <span class="draft-sep">·</span>
                <span>poll</span>
              {/if}
              {#if draft.scheduled_at}
                <span class="draft-sep">·</span>
                <span>scheduled</span>
              {/if}
            </div>
          </div>
          <div class="draft-actions">
            <button type="button" class="btn btn-primary" onclick={() => resume(draft)}>Resume</button>
            <button type="button" class="btn btn-ghost draft-delete" onclick={() => confirmDelete(draft)}>
              Delete
            </button>
          </div>
        </li>
      {/each}
    </ul>
  </AsyncState>
</div>

<Modal bind:open={showDeleteModal} title="Delete draft?" onclose={() => { draftToDelete = null; }}>
  <p class="confirm-message">This draft will be permanently discarded. This cannot be undone.</p>
  <div class="confirm-actions">
    <button type="button" class="btn btn-ghost" onclick={() => (showDeleteModal = false)}>Keep it</button>
    <button type="button" class="btn btn-danger" onclick={handleDelete} disabled={deleting}>
      {deleting ? 'Deleting…' : 'Delete'}
    </button>
  </div>
</Modal>

<style>
  .drafts-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
  }

  .page-header {
    margin-block-end: var(--space-4);
  }

  .page-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
  }

  .page-sub {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    margin-block-start: var(--space-1);
  }

  .state-center {
    text-align: center;
    padding: var(--space-12) var(--space-4);
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    align-items: center;
  }

  .empty-icon {
    font-size: 48px;
    color: var(--color-text-tertiary);
  }

  .empty-text {
    font-size: var(--text-base);
    color: var(--color-text);
  }

  .empty-sub {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  .drafts-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .draft-card {
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    padding: var(--space-4);
    display: flex;
    gap: var(--space-4);
    align-items: flex-start;
    justify-content: space-between;
  }

  .draft-body {
    flex: 1;
    min-width: 0;
  }

  .draft-target {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 4px 10px;
    border-radius: var(--radius-full);
    background: var(--color-primary-soft, var(--color-surface-container-low));
    color: var(--color-primary);
    font-size: var(--text-xs);
    font-weight: 500;
    text-decoration: none;
    margin-block-end: var(--space-2);
    /* Lets the chip wrap nicely if the group / page name is long
       instead of pushing the row out and clipping. */
    max-width: 100%;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
    transition: background var(--transition-fast);
  }

  .draft-target:hover {
    background: var(--color-primary);
    color: var(--color-on-primary);
    text-decoration: none;
  }

  .draft-target-icon {
    font-size: 16px;
    flex-shrink: 0;
  }

  .draft-target-label {
    color: inherit;
    opacity: 0.8;
  }

  .draft-target-name {
    font-weight: 700;
  }

  .draft-cw {
    font-size: var(--text-sm);
    color: var(--color-warning, #f59e0b);
    font-weight: 600;
    margin: 0 0 var(--space-2) 0;
  }

  .draft-content {
    font-size: var(--text-base);
    color: var(--color-text);
    white-space: pre-wrap;
    word-break: break-word;
    margin: 0 0 var(--space-2) 0;
  }

  .draft-meta {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    display: flex;
    gap: var(--space-1);
    flex-wrap: wrap;
  }

  .draft-visibility {
    text-transform: capitalize;
  }

  .draft-sep {
    opacity: 0.6;
  }

  .draft-target:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .draft-actions {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    flex-shrink: 0;
  }

  /* Ghost button with a destructive tint; the confirming red button
     lives in the modal. (`btn-ghost-danger` isn't a global variant.) */
  .draft-delete {
    color: var(--color-danger);
  }

  .draft-delete:hover:not(:disabled) {
    background: var(--color-danger-light, rgba(239, 68, 68, 0.1));
  }

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

  /* Skeleton placeholder lines while drafts load. */
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
</style>
