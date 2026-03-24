<script lang="ts">
  import type { Post } from '$lib/api/types.js';
  import { api } from '$lib/api/client.js';
  import { authStore } from '$lib/stores/auth.js';
  import { get } from 'svelte/store';
  import ReactionPicker from './ReactionPicker.svelte';

  let {
    post,
    onedit,
  }: {
    post: Post;
    onedit?: () => void;
  } = $props();

  let isBoosted = $state(post.is_boosted);
  let boostCount = $state(post.boost_count);
  let replyCount = $state(post.reply_count);
  let reactionCount = $state(post.reaction_count);
  let currentReaction = $state(post.current_user_reaction);
  let showReactionPicker = $state(false);
  let showMoreMenu = $state(false);
  let bounceReaction = $state(false);

  let isOwnPost = $derived(() => {
    const state = get(authStore);
    return state.user?.id === post.account.id;
  });

  // Report modal state
  let showReportModal = $state(false);
  let reportCategory = $state('spam');
  let reportDescription = $state('');
  let reportSubmitting = $state(false);
  let reportError = $state('');

  const reportCategories = [
    { value: 'spam', label: 'Spam' },
    { value: 'harassment', label: 'Harassment' },
    { value: 'hate_speech', label: 'Hate speech' },
    { value: 'illegal', label: 'Illegal content' },
    { value: 'misinformation', label: 'Misinformation' },
    { value: 'other', label: 'Other' },
  ];

  async function handleReply(e: MouseEvent) {
    e.stopPropagation();
    window.dispatchEvent(new CustomEvent('open-composer', { detail: { replyTo: post } }));
  }

  async function handleBoost(e: MouseEvent) {
    e.stopPropagation();
    try {
      if (isBoosted) {
        await api.delete(`/api/v1/statuses/${post.id}/boost`);
        isBoosted = false;
        boostCount = Math.max(0, boostCount - 1);
      } else {
        await api.post(`/api/v1/statuses/${post.id}/boost`);
        isBoosted = true;
        boostCount += 1;
      }
    } catch {
      // Revert on error
    }
  }

  async function handleReaction(emoji: string) {
    showReactionPicker = false;
    try {
      if (currentReaction === emoji) {
        await api.delete(`/api/v1/statuses/${post.id}/react`);
        currentReaction = null;
        reactionCount = Math.max(0, reactionCount - 1);
      } else {
        const hadReaction = currentReaction !== null;
        await api.post(`/api/v1/statuses/${post.id}/react`, { type: emoji });
        currentReaction = emoji;
        if (!hadReaction) reactionCount += 1;
      }
      bounceReaction = true;
      setTimeout(() => { bounceReaction = false; }, 400);
    } catch {
      // Revert on error
    }
  }

  function toggleReactionPicker(e: MouseEvent) {
    e.stopPropagation();
    showReactionPicker = !showReactionPicker;
    showMoreMenu = false;
  }

  function toggleMoreMenu(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = !showMoreMenu;
    showReactionPicker = false;
  }

  function handleCopyLink(e: MouseEvent) {
    e.stopPropagation();
    navigator.clipboard.writeText(`${window.location.origin}/post/${post.id}`);
    showMoreMenu = false;
  }

  async function handleBookmark(e: MouseEvent) {
    e.stopPropagation();
    try {
      if (post.is_bookmarked) {
        await api.delete(`/api/v1/statuses/${post.id}/bookmark`);
      } else {
        await api.post(`/api/v1/statuses/${post.id}/bookmark`);
      }
    } catch {
      // Handle error
    }
    showMoreMenu = false;
  }

  function handleEdit(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    onedit?.();
  }

  function handleReport(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    reportCategory = 'spam';
    reportDescription = '';
    reportError = '';
    showReportModal = true;
  }

  async function submitReport() {
    reportSubmitting = true;
    reportError = '';
    try {
      await api.post('/api/v1/reports', {
        reported_id: post.account.id,
        target_type: 'post',
        target_id: post.id,
        category: reportCategory,
        description: reportDescription,
      });
      showReportModal = false;
    } catch {
      reportError = 'Failed to submit report. Please try again.';
    } finally {
      reportSubmitting = false;
    }
  }

  function cancelReport() {
    showReportModal = false;
  }

  let showDeleteConfirm = $state(false);

  function handleDelete(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    showDeleteConfirm = true;
  }

  async function confirmDelete() {
    try {
      await api.delete(`/api/v1/statuses/${post.id}`);
      window.dispatchEvent(new CustomEvent('post-deleted', { detail: { id: post.id } }));
    } catch {
      // Handle error
    }
    showDeleteConfirm = false;
  }

  function cancelDelete() {
    showDeleteConfirm = false;
  }

  function handleActionKeydown(e: KeyboardEvent, action: () => void) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      e.stopPropagation();
      action();
    }
  }

  // Close menus on outside click
  function handleWindowClick() {
    showReactionPicker = false;
    showMoreMenu = false;
  }
</script>

<svelte:window onclick={handleWindowClick} />

<div class="post-actions" role="group" aria-label="Post actions">
  <!-- Reply -->
  <button
    type="button"
    class="action-btn action-reply"
    onclick={handleReply}
    onkeydown={(e) => handleActionKeydown(e, () => handleReply(new MouseEvent('click')))}
    aria-label="Reply ({replyCount})"
  >
    <span class="material-symbols-outlined action-icon">chat_bubble</span>
    {#if replyCount > 0}
      <span class="action-count">{replyCount}</span>
    {/if}
  </button>

  <!-- Boost -->
  <button
    type="button"
    class="action-btn action-boost"
    class:active-boost={isBoosted}
    onclick={handleBoost}
    aria-label="{isBoosted ? 'Undo boost' : 'Boost'} ({boostCount})"
    aria-pressed={isBoosted}
  >
    <span class="material-symbols-outlined action-icon">cached</span>
    {#if boostCount > 0}
      <span class="action-count">{boostCount}</span>
    {/if}
  </button>

  <!-- Reaction / Like -->
  <div class="action-reaction-wrapper">
    <button
      type="button"
      class="action-btn action-like"
      class:active-reaction={currentReaction !== null}
      class:bounce={bounceReaction}
      onclick={toggleReactionPicker}
      aria-label="React ({reactionCount})"
      aria-expanded={showReactionPicker}
    >
      {#if currentReaction}
        <span class="current-reaction">{currentReaction}</span>
      {:else}
        <span class="material-symbols-outlined action-icon">favorite</span>
      {/if}
      {#if reactionCount > 0}
        <span class="action-count">{reactionCount}</span>
      {/if}
    </button>

    {#if showReactionPicker}
      <div class="picker-anchor">
        <ReactionPicker
          selected={currentReaction}
          onselect={handleReaction}
        />
      </div>
    {/if}
  </div>

  <!-- Share -->
  <div class="action-more-wrapper">
    <button
      type="button"
      class="action-btn action-share"
      onclick={toggleMoreMenu}
      aria-label="More actions"
      aria-expanded={showMoreMenu}
      aria-haspopup="menu"
    >
      <span class="material-symbols-outlined action-icon">share</span>
    </button>

    {#if showMoreMenu}
      <div class="more-menu" role="menu">
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleCopyLink}>
          <span class="material-symbols-outlined menu-icon">link</span>
          Copy link
        </button>
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleBookmark}>
          <span class="material-symbols-outlined menu-icon">{post.is_bookmarked ? 'bookmark_remove' : 'bookmark'}</span>
          {post.is_bookmarked ? 'Remove bookmark' : 'Bookmark'}
        </button>
        {#if isOwnPost()}
          <button type="button" class="more-menu-item" role="menuitem" onclick={handleEdit}>
            <span class="material-symbols-outlined menu-icon">edit</span>
            Edit
          </button>
          <button type="button" class="more-menu-item more-menu-danger" role="menuitem" onclick={handleDelete}>
            <span class="material-symbols-outlined menu-icon">delete</span>
            Delete
          </button>
        {:else}
          <button type="button" class="more-menu-item more-menu-danger" role="menuitem" onclick={handleReport}>
            <span class="material-symbols-outlined menu-icon">flag</span>
            Report
          </button>
        {/if}
      </div>
    {/if}
  </div>
</div>

{#if showDeleteConfirm}
  <div class="dialog-overlay" onclick={cancelDelete} role="dialog" aria-modal="true" aria-label="Confirm delete">
    <div class="dialog-panel" onclick={(e) => e.stopPropagation()}>
      <h3 class="dialog-title">Delete post?</h3>
      <p class="dialog-message">This action cannot be undone. The post will be permanently removed.</p>
      <div class="dialog-actions">
        <button type="button" class="dialog-cancel" onclick={cancelDelete}>Cancel</button>
        <button type="button" class="dialog-confirm-danger" onclick={confirmDelete}>Delete</button>
      </div>
    </div>
  </div>
{/if}

{#if showReportModal}
  <div class="dialog-overlay" onclick={cancelReport} role="dialog" aria-modal="true" aria-label="Report post">
    <div class="dialog-panel" onclick={(e) => e.stopPropagation()}>
      <h3 class="dialog-title">Report post</h3>
      <p class="dialog-message">Why are you reporting this post?</p>

      <div class="report-form">
        <label class="report-label" for="report-category">Category</label>
        <select id="report-category" class="report-select" bind:value={reportCategory}>
          {#each reportCategories as cat (cat.value)}
            <option value={cat.value}>{cat.label}</option>
          {/each}
        </select>

        <label class="report-label" for="report-description">Description (optional)</label>
        <textarea
          id="report-description"
          class="report-textarea"
          bind:value={reportDescription}
          placeholder="Provide additional details..."
          rows="3"
        ></textarea>

        {#if reportError}
          <p class="report-error">{reportError}</p>
        {/if}
      </div>

      <div class="dialog-actions">
        <button type="button" class="dialog-cancel" onclick={cancelReport}>Cancel</button>
        <button type="button" class="dialog-confirm-danger" onclick={submitReport} disabled={reportSubmitting}>
          {reportSubmitting ? 'Submitting...' : 'Submit report'}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  /* ---- Action Bar ---- */
  .post-actions {
    display: flex;
    align-items: center;
    justify-content: space-between;
    max-width: 28rem;
  }

  .action-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 6px 8px;
    background: transparent;
    border: none;
    border-radius: 9999px;
    color: var(--color-text-secondary);
    font-size: 0.875rem;
    cursor: pointer;
    transition: color 150ms ease, transform 150ms ease;
    line-height: 1;
  }

  .action-icon {
    font-size: 20px;
    transition: transform 150ms ease, color 150ms ease;
  }

  .action-btn:hover .action-icon {
    transform: scale(1.1);
  }

  .action-btn:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 1px;
  }

  /* Reply hover */
  .action-reply:hover {
    color: var(--color-primary);
  }

  /* Boost hover + active */
  .action-boost:hover {
    color: var(--color-primary);
  }

  .active-boost {
    color: var(--color-primary);
  }

  /* Like hover + active */
  .action-like:hover {
    color: #ef4444;
  }

  .active-reaction {
    color: #ef4444;
  }

  /* Share hover */
  .action-share:hover {
    color: var(--color-primary);
  }

  .action-count {
    font-size: var(--text-xs);
    font-weight: 500;
  }

  .current-reaction {
    font-size: 1.125rem;
    line-height: 1;
  }

  .bounce {
    animation: spring-bounce 0.4s ease;
  }

  @keyframes spring-bounce {
    0% { transform: scale(1); }
    30% { transform: scale(1.3); }
    50% { transform: scale(0.9); }
    70% { transform: scale(1.1); }
    100% { transform: scale(1); }
  }

  .action-reaction-wrapper {
    position: relative;
  }

  .picker-anchor {
    position: absolute;
    inset-block-end: 100%;
    inset-inline-start: 50%;
    transform: translateX(-50%);
    margin-block-end: 8px;
    z-index: var(--z-dropdown);
  }

  .action-more-wrapper {
    position: relative;
  }

  /* ---- More Menu ---- */
  .more-menu {
    position: absolute;
    inset-block-start: 100%;
    inset-inline-end: 0;
    margin-block-start: 4px;
    min-width: 200px;
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: 14px;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.08);
    padding: 6px;
    z-index: var(--z-dropdown);
  }

  .more-menu-item {
    display: flex;
    align-items: center;
    gap: 10px;
    width: 100%;
    padding: 10px 14px;
    background: transparent;
    border: none;
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    cursor: pointer;
    text-align: start;
    transition: background-color 150ms ease;
  }

  .menu-icon {
    font-size: 18px;
    color: var(--color-text-secondary);
  }

  .more-menu-item:hover {
    background: var(--color-surface);
  }

  .more-menu-danger {
    color: var(--color-danger);
  }

  .more-menu-danger .menu-icon {
    color: var(--color-danger);
  }

  .more-menu-danger:hover {
    background: var(--color-danger-soft);
  }

  /* ---- Dialog Overlay ---- */
  .dialog-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 9999;
    animation: overlay-in 0.15s ease;
  }

  @keyframes overlay-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes dialog-in {
    from { opacity: 0; transform: scale(0.95) translateY(4px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .dialog-panel {
    background: var(--color-surface-container-lowest);
    border-radius: 18px;
    padding: 28px;
    max-width: 400px;
    width: 90%;
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.15);
    animation: dialog-in 0.2s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .dialog-title {
    font-size: 1.125rem;
    font-weight: 700;
    margin-block-end: 8px;
  }

  .dialog-message {
    font-size: 0.875rem;
    color: var(--color-text-secondary);
    margin-block-end: 20px;
    line-height: 1.5;
  }

  .dialog-actions {
    display: flex;
    justify-content: flex-end;
    gap: 12px;
  }

  .dialog-cancel {
    padding: 8px 20px;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    background: transparent;
    color: var(--color-text);
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    transition: background-color 150ms ease;
  }

  .dialog-cancel:hover {
    background: var(--color-surface);
  }

  .dialog-confirm-danger {
    padding: 8px 20px;
    border: none;
    border-radius: 9999px;
    background: var(--color-danger);
    color: white;
    font-size: 0.875rem;
    font-weight: 700;
    cursor: pointer;
    transition: opacity 150ms ease;
  }

  .dialog-confirm-danger:hover {
    opacity: 0.9;
  }

  .dialog-confirm-danger:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  /* ---- Report Form ---- */
  .report-form {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-block-end: 20px;
  }

  .report-label {
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text);
  }

  .report-select {
    padding: 8px 12px;
    border: 1px solid var(--color-border);
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    background: var(--color-surface-container-lowest);
  }

  .report-textarea {
    padding: 8px 12px;
    border: 1px solid var(--color-border);
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    background: var(--color-surface-container-lowest);
    resize: vertical;
    font-family: inherit;
  }

  .report-error {
    font-size: 0.875rem;
    color: var(--color-danger);
  }
</style>
