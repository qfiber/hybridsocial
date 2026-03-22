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
    class="action-btn"
    onclick={handleReply}
    onkeydown={(e) => handleActionKeydown(e, () => handleReply(new MouseEvent('click')))}
    aria-label="Reply ({replyCount})"
  >
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
    </svg>
    {#if replyCount > 0}
      <span class="action-count">{replyCount}</span>
    {/if}
  </button>

  <!-- Boost -->
  <button
    type="button"
    class="action-btn"
    class:active-boost={isBoosted}
    onclick={handleBoost}
    aria-label="{isBoosted ? 'Undo boost' : 'Boost'} ({boostCount})"
    aria-pressed={isBoosted}
  >
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
      <polyline points="17 1 21 5 17 9"/>
      <path d="M3 11V9a4 4 0 0 1 4-4h14"/>
      <polyline points="7 23 3 19 7 15"/>
      <path d="M21 13v2a4 4 0 0 1-4 4H3"/>
    </svg>
    {#if boostCount > 0}
      <span class="action-count">{boostCount}</span>
    {/if}
  </button>

  <!-- Reaction -->
  <div class="action-reaction-wrapper">
    <button
      type="button"
      class="action-btn"
      class:active-reaction={currentReaction !== null}
      class:bounce={bounceReaction}
      onclick={toggleReactionPicker}
      aria-label="React ({reactionCount})"
      aria-expanded={showReactionPicker}
    >
      {#if currentReaction}
        <span class="current-reaction">{currentReaction}</span>
      {:else}
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <circle cx="12" cy="12" r="10"/>
          <path d="M8 14s1.5 2 4 2 4-2 4-2"/>
          <line x1="9" y1="9" x2="9.01" y2="9"/>
          <line x1="15" y1="9" x2="15.01" y2="9"/>
        </svg>
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

  <!-- More menu -->
  <div class="action-more-wrapper">
    <button
      type="button"
      class="action-btn"
      onclick={toggleMoreMenu}
      aria-label="More actions"
      aria-expanded={showMoreMenu}
      aria-haspopup="menu"
    >
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <circle cx="12" cy="12" r="1"/>
        <circle cx="19" cy="12" r="1"/>
        <circle cx="5" cy="12" r="1"/>
      </svg>
    </button>

    {#if showMoreMenu}
      <div class="more-menu" role="menu">
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleCopyLink}>
          Copy link
        </button>
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleBookmark}>
          {post.is_bookmarked ? 'Remove bookmark' : 'Bookmark'}
        </button>
        {#if isOwnPost()}
          <button type="button" class="more-menu-item" role="menuitem" onclick={handleEdit}>
            Edit
          </button>
          <button type="button" class="more-menu-item more-menu-danger" role="menuitem" onclick={handleDelete}>
            Delete
          </button>
        {:else}
          <button type="button" class="more-menu-item more-menu-danger" role="menuitem" onclick={handleReport}>
            Report
          </button>
        {/if}
      </div>
    {/if}
  </div>
</div>

{#if showDeleteConfirm}
  <div class="delete-overlay" onclick={cancelDelete} role="dialog" aria-modal="true" aria-label="Confirm delete">
    <div class="delete-dialog" onclick={(e) => e.stopPropagation()}>
      <h3 class="delete-title">Delete post?</h3>
      <p class="delete-message">This action cannot be undone. The post will be permanently removed.</p>
      <div class="delete-actions">
        <button type="button" class="delete-cancel" onclick={cancelDelete}>Cancel</button>
        <button type="button" class="delete-confirm" onclick={confirmDelete}>Delete</button>
      </div>
    </div>
  </div>
{/if}

{#if showReportModal}
  <div class="delete-overlay" onclick={cancelReport} role="dialog" aria-modal="true" aria-label="Report post">
    <div class="delete-dialog" onclick={(e) => e.stopPropagation()}>
      <h3 class="delete-title">Report post</h3>
      <p class="delete-message">Why are you reporting this post?</p>

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

      <div class="delete-actions">
        <button type="button" class="delete-cancel" onclick={cancelReport}>Cancel</button>
        <button type="button" class="delete-confirm" onclick={submitReport} disabled={reportSubmitting}>
          {reportSubmitting ? 'Submitting...' : 'Submit report'}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .delete-overlay {
    position: fixed;
    inset: 0;
    background: var(--color-overlay, rgba(0,0,0,0.5));
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: var(--z-modal, 40);
  }

  .delete-dialog {
    background: var(--color-surface-raised, #fff);
    border-radius: var(--radius-lg, 0.75rem);
    padding: var(--space-6, 1.5rem);
    max-width: 400px;
    width: 90%;
    box-shadow: var(--shadow-xl, 0 10px 15px rgba(0,0,0,0.1));
  }

  .delete-title {
    font-size: var(--text-lg, 1.125rem);
    font-weight: 600;
    margin-block-end: var(--space-2, 0.5rem);
  }

  .delete-message {
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text-secondary, #64748b);
    margin-block-end: var(--space-4, 1rem);
  }

  .delete-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3, 0.75rem);
  }

  .delete-cancel {
    padding: var(--space-2, 0.5rem) var(--space-4, 1rem);
    border: 1px solid var(--color-border, #e2e8f0);
    border-radius: var(--radius-md, 0.5rem);
    background: transparent;
    color: var(--color-text, #0f172a);
    font-size: var(--text-sm, 0.875rem);
    cursor: pointer;
  }

  .delete-confirm {
    padding: var(--space-2, 0.5rem) var(--space-4, 1rem);
    border: none;
    border-radius: var(--radius-md, 0.5rem);
    background: var(--color-danger, #ef4444);
    color: white;
    font-size: var(--text-sm, 0.875rem);
    font-weight: 600;
    cursor: pointer;
  }

  .delete-confirm:hover {
    opacity: 0.9;
  }

  .delete-confirm:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .report-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-2, 0.5rem);
    margin-block-end: var(--space-4, 1rem);
  }

  .report-label {
    font-size: var(--text-sm, 0.875rem);
    font-weight: 500;
    color: var(--color-text, #0f172a);
  }

  .report-select {
    padding: var(--space-2, 0.5rem);
    border: 1px solid var(--color-border, #e2e8f0);
    border-radius: var(--radius-md, 0.5rem);
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text, #0f172a);
    background: var(--color-bg, #fff);
  }

  .report-textarea {
    padding: var(--space-2, 0.5rem);
    border: 1px solid var(--color-border, #e2e8f0);
    border-radius: var(--radius-md, 0.5rem);
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text, #0f172a);
    background: var(--color-bg, #fff);
    resize: vertical;
    font-family: inherit;
  }

  .report-error {
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-danger, #ef4444);
  }

  .post-actions {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    padding-inline-start: calc(40px + var(--space-3));
    margin-block-start: var(--space-3);
  }

  .action-btn {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    padding: var(--space-1) var(--space-2);
    background: transparent;
    border: none;
    border-radius: var(--radius-md);
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    cursor: pointer;
    transition: color var(--transition-fast), background-color var(--transition-fast);
    line-height: 1;
  }

  .action-btn:hover {
    background: var(--color-bg-tertiary);
    color: var(--color-text-secondary);
  }

  .action-btn:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 1px;
  }

  .active-boost {
    color: #0d9488;
  }

  .active-boost:hover {
    color: #0d9488;
  }

  .active-reaction {
    color: var(--color-primary);
  }

  .action-count {
    font-size: var(--text-xs);
    font-weight: var(--font-medium);
  }

  .current-reaction {
    font-size: var(--text-base);
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
    margin-block-end: var(--space-2);
    z-index: var(--z-dropdown);
  }

  .action-more-wrapper {
    position: relative;
    margin-inline-start: auto;
  }

  .more-menu {
    position: absolute;
    inset-block-start: 100%;
    inset-inline-end: 0;
    margin-block-start: var(--space-1);
    min-width: 180px;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-lg);
    padding: var(--space-1);
    z-index: var(--z-dropdown);
  }

  .more-menu-item {
    display: block;
    width: 100%;
    padding: var(--space-2) var(--space-3);
    background: transparent;
    border: none;
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    color: var(--color-text);
    cursor: pointer;
    text-align: start;
    transition: background-color var(--transition-fast);
  }

  .more-menu-item:hover {
    background: var(--color-bg-tertiary);
  }

  .more-menu-danger {
    color: var(--color-danger);
  }

  .more-menu-danger:hover {
    background: var(--color-danger-light);
  }
</style>
