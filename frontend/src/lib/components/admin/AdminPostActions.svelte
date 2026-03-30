<script lang="ts">
  import type { Post } from '$lib/api/types.js';
  import {
    adminDeletePost,
    adminForceSensitive,
    adminRemoveSensitive,
    banMediaFromPost,
  } from '$lib/api/admin.js';

  let {
    post,
  }: {
    post: Post;
  } = $props();

  let showDropdown = $state(false);
  let dropdownUpward = $state(false);
  let showDeleteConfirm = $state(false);
  let deleteReason = $state('');
  let actionLoading = $state(false);
  let actionError = $state('');
  let isSensitive = $state(post.sensitive);

  let hasMedia = $derived((post.media_attachments?.length ?? 0) > 0);

  function toggleDropdown(e: MouseEvent) {
    e.stopPropagation();
    showDropdown = !showDropdown;
    if (showDropdown) {
      const btn = e.currentTarget as HTMLElement;
      const rect = btn.getBoundingClientRect();
      dropdownUpward = window.innerHeight - rect.bottom < 280;
    }
  }

  function closeDropdown() {
    showDropdown = false;
  }

  function openDeleteConfirm(e: MouseEvent) {
    e.stopPropagation();
    showDropdown = false;
    deleteReason = '';
    actionError = '';
    showDeleteConfirm = true;
  }

  async function confirmDelete() {
    actionLoading = true;
    actionError = '';
    try {
      await adminDeletePost(post.id, deleteReason || undefined);
      showDeleteConfirm = false;
      window.dispatchEvent(new CustomEvent('post-deleted', { detail: { id: post.id } }));
    } catch {
      actionError = 'Failed to delete post.';
    } finally {
      actionLoading = false;
    }
  }

  function cancelDelete() {
    showDeleteConfirm = false;
    actionError = '';
  }

  async function handleToggleSensitive(e: MouseEvent) {
    e.stopPropagation();
    showDropdown = false;
    actionLoading = true;
    try {
      if (isSensitive) {
        await adminRemoveSensitive(post.id);
        isSensitive = false;
      } else {
        await adminForceSensitive(post.id);
        isSensitive = true;
      }
      window.dispatchEvent(new CustomEvent('post-updated', { detail: { id: post.id, sensitive: isSensitive } }));
    } catch {
      actionError = 'Failed to update sensitive flag.';
    } finally {
      actionLoading = false;
    }
  }

  async function handleBanMedia(e: MouseEvent) {
    e.stopPropagation();
    showDropdown = false;
    actionLoading = true;
    try {
      await banMediaFromPost(post.id);
      window.dispatchEvent(new CustomEvent('post-updated', { detail: { id: post.id, mediaBanned: true } }));
    } catch {
      actionError = 'Failed to ban media hashes.';
    } finally {
      actionLoading = false;
    }
  }

  function handleViewInAdmin(e: MouseEvent) {
    e.stopPropagation();
    showDropdown = false;
    window.location.href = `/admin/moderation?post=${post.id}`;
  }

  function handleWindowClick() {
    showDropdown = false;
  }
</script>

<svelte:window onclick={handleWindowClick} />

<div class="admin-post-actions">
  <button
    type="button"
    class="admin-action-btn"
    onclick={toggleDropdown}
    aria-label="Moderation actions"
    aria-expanded={showDropdown}
    aria-haspopup="menu"
    title="Moderation actions"
  >
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
    </svg>
  </button>

  {#if showDropdown}
    <div class="admin-dropdown" class:admin-dropdown-upward={dropdownUpward} role="menu" onclick={(e) => e.stopPropagation()}>
      <button type="button" class="admin-dropdown-item admin-dropdown-danger" role="menuitem" onclick={openDeleteConfirm}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
        </svg>
        Delete Post
      </button>
      <button type="button" class="admin-dropdown-item" role="menuitem" onclick={handleToggleSensitive}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          {#if isSensitive}
            <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>
          {:else}
            <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/>
          {/if}
        </svg>
        {isSensitive ? 'Remove Sensitive' : 'Force Sensitive'}
      </button>
      {#if hasMedia}
        <button type="button" class="admin-dropdown-item admin-dropdown-danger" role="menuitem" onclick={handleBanMedia}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
          </svg>
          Ban Media Hashes
        </button>
      {/if}
      <div class="admin-dropdown-divider"></div>
      <button type="button" class="admin-dropdown-item" role="menuitem" onclick={handleViewInAdmin}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/>
        </svg>
        View in Admin
      </button>
    </div>
  {/if}

  {#if actionError}
    <div class="admin-toast" role="alert">
      {actionError}
      <button type="button" class="admin-toast-close" onclick={(e) => { e.stopPropagation(); actionError = ''; }} aria-label="Dismiss">&times;</button>
    </div>
  {/if}
</div>

{#if showDeleteConfirm}
  <div class="admin-overlay" onclick={cancelDelete} role="dialog" aria-modal="true" aria-label="Delete post as admin">
    <div class="admin-dialog" onclick={(e) => e.stopPropagation()}>
      <h3 class="admin-dialog-title">Delete post (Admin)</h3>
      <p class="admin-dialog-message">This will permanently remove the post. This action is logged.</p>

      <div class="admin-dialog-form">
        <label class="admin-dialog-label" for="admin-delete-reason">Reason (optional)</label>
        <textarea
          id="admin-delete-reason"
          class="admin-dialog-textarea"
          bind:value={deleteReason}
          placeholder="Reason for deletion..."
          rows="2"
        ></textarea>

        {#if actionError}
          <p class="admin-dialog-error">{actionError}</p>
        {/if}
      </div>

      <div class="admin-dialog-actions">
        <button type="button" class="admin-dialog-cancel" onclick={cancelDelete}>Cancel</button>
        <button type="button" class="admin-dialog-confirm" onclick={confirmDelete} disabled={actionLoading}>
          {actionLoading ? 'Deleting...' : 'Delete Post'}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .admin-post-actions {
    position: relative;
    display: inline-flex;
  }

  .admin-action-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-1);
    background: transparent;
    border: none;
    border-radius: var(--radius-md);
    color: var(--color-warning, #f59e0b);
    cursor: pointer;
    transition: color var(--transition-fast), background-color var(--transition-fast);
    line-height: 1;
    opacity: 0.7;
  }

  .admin-action-btn:hover {
    background: var(--color-warning-light, rgba(245, 158, 11, 0.1));
    opacity: 1;
  }

  .admin-action-btn:focus-visible {
    outline: 2px solid var(--color-warning, #f59e0b);
    outline-offset: 1px;
  }

  .admin-dropdown {
    position: absolute;
    inset-block-start: 100%;
    inset-inline-end: 0;
    margin-block-start: var(--space-1);
    min-width: 200px;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: 14px;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.08);
    padding: 6px;
    z-index: var(--z-dropdown, 50);
    animation: admin-menu-down 0.2s ease;
    transform-origin: top right;
  }

  @keyframes admin-menu-down {
    from { opacity: 0; transform: scaleY(0.6) translateY(-4px); }
    to { opacity: 1; transform: scaleY(1) translateY(0); }
  }

  .admin-dropdown-upward {
    inset-block-start: auto;
    inset-block-end: 100%;
    margin-block-start: 0;
    margin-block-end: var(--space-1);
    animation: admin-menu-up 0.2s ease;
    transform-origin: bottom right;
  }

  @keyframes admin-menu-up {
    from { opacity: 0; transform: scaleY(0.6) translateY(4px); }
    to { opacity: 1; transform: scaleY(1) translateY(0); }
  }

  .admin-dropdown-item {
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
    font-family: inherit;
  }

  .admin-dropdown-item:hover {
    background: var(--color-surface);
  }

  .admin-dropdown-danger {
    color: var(--color-danger, #ef4444);
  }

  .admin-dropdown-danger:hover {
    background: var(--color-danger-light, rgba(239, 68, 68, 0.1));
  }

  .admin-dropdown-divider {
    height: 1px;
    background: var(--color-border);
    margin: var(--space-1) 0;
  }

  .admin-toast {
    position: fixed;
    inset-block-end: var(--space-4);
    inset-inline-end: var(--space-4);
    background: var(--color-danger, #ef4444);
    color: white;
    padding: var(--space-2) var(--space-4);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    z-index: var(--z-toast, 60);
    display: flex;
    align-items: center;
    gap: var(--space-2);
    box-shadow: var(--shadow-lg);
  }

  .admin-toast-close {
    background: none;
    border: none;
    color: white;
    cursor: pointer;
    font-size: var(--text-lg);
    line-height: 1;
    padding: 0;
    opacity: 0.8;
  }

  .admin-toast-close:hover {
    opacity: 1;
  }

  .admin-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    backdrop-filter: blur(2px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 9999;
    animation: admin-overlay-in 0.15s ease;
  }

  @keyframes admin-overlay-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes admin-dialog-in {
    from { opacity: 0; transform: scale(0.95) translateY(4px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .admin-dialog {
    background: var(--color-surface-raised, #fff);
    border-radius: var(--radius-xl, 1rem);
    padding: var(--space-6, 1.5rem);
    max-width: 420px;
    width: 90%;
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.15);
    animation: admin-dialog-in 0.2s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .admin-dialog-title {
    font-size: var(--text-lg, 1.125rem);
    font-weight: 600;
    margin-block-end: var(--space-2, 0.5rem);
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .admin-dialog-message {
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text-secondary, #64748b);
    margin-block-end: var(--space-4, 1rem);
  }

  .admin-dialog-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-2, 0.5rem);
    margin-block-end: var(--space-4, 1rem);
  }

  .admin-dialog-label {
    font-size: var(--text-sm, 0.875rem);
    font-weight: 500;
    color: var(--color-text, #0f172a);
  }

  .admin-dialog-textarea {
    padding: var(--space-2, 0.5rem);
    border: 1px solid var(--color-border, #e2e8f0);
    border-radius: var(--radius-md, 0.5rem);
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text, #0f172a);
    background: var(--color-bg, #fff);
    resize: vertical;
    font-family: inherit;
  }

  .admin-dialog-textarea:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 2px var(--color-primary-light);
  }

  .admin-dialog-error {
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-danger, #ef4444);
  }

  .admin-dialog-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3, 0.75rem);
  }

  .admin-dialog-cancel {
    padding: var(--space-2, 0.5rem) var(--space-4, 1rem);
    border: 1px solid var(--color-border, #e2e8f0);
    border-radius: var(--radius-md, 0.5rem);
    background: transparent;
    color: var(--color-text, #0f172a);
    font-size: var(--text-sm, 0.875rem);
    cursor: pointer;
  }

  .admin-dialog-cancel:hover {
    background: var(--color-bg-tertiary);
  }

  .admin-dialog-confirm {
    padding: var(--space-2, 0.5rem) var(--space-4, 1rem);
    border: none;
    border-radius: var(--radius-md, 0.5rem);
    background: var(--color-danger, #ef4444);
    color: white;
    font-size: var(--text-sm, 0.875rem);
    font-weight: 600;
    cursor: pointer;
  }

  .admin-dialog-confirm:hover {
    opacity: 0.9;
  }

  .admin-dialog-confirm:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>
