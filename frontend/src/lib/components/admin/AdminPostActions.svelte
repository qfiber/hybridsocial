<script lang="ts">
  import type { Post } from '$lib/api/types.js';
  import {
    adminDeletePost,
    adminForceSensitive,
    adminRemoveSensitive,
    banMediaFromPost,
    adminHidePost,
    adminUnhidePost,
    adminLockReplies,
    adminUnlockReplies,
    adminRefetchPost,
    suspendUser,
    silenceUser,
    warnUser,
    createModerationNote,
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
  let isHidden = $state(!!post.hidden_at);
  let repliesLocked = $state(!!post.replies_locked_at);

  // Author-action modals
  let showWarnDialog = $state(false);
  let warnMessage = $state('');
  let showNoteDialog = $state(false);
  let noteContent = $state('');
  let showAuthorActionConfirm = $state<null | 'silence' | 'suspend'>(null);

  let hasMedia = $derived((post.media_attachments?.length ?? 0) > 0);
  let authorId = $derived(post.account?.id);
  let authorHandle = $derived(post.account?.acct || post.account?.handle || '');
  let permalink = $derived(
    typeof window !== 'undefined' ? `${window.location.origin}/post/${post.id}` : `/post/${post.id}`
  );

  // Remote = the author's acct carries a `@host` suffix. Local
  // identities don't. We key refetch availability off this same
  // signal — there's no origin to refetch from for a local post.
  let isRemote = $derived(
    typeof post.account?.acct === 'string' && post.account.acct.includes('@')
  );

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
    window.location.href = `/admin/posts/${post.id}`;
  }

  async function handleToggleHidden(e: MouseEvent) {
    e.stopPropagation();
    showDropdown = false;
    actionLoading = true;
    try {
      if (isHidden) {
        await adminUnhidePost(post.id);
        isHidden = false;
      } else {
        await adminHidePost(post.id);
        isHidden = true;
      }
      window.dispatchEvent(
        new CustomEvent('post-updated', { detail: { id: post.id, hidden: isHidden } })
      );
    } catch {
      actionError = 'Failed to update visibility.';
    } finally {
      actionLoading = false;
    }
  }

  async function handleToggleReplyLock(e: MouseEvent) {
    e.stopPropagation();
    showDropdown = false;
    actionLoading = true;
    try {
      if (repliesLocked) {
        await adminUnlockReplies(post.id);
        repliesLocked = false;
      } else {
        await adminLockReplies(post.id);
        repliesLocked = true;
      }
      window.dispatchEvent(
        new CustomEvent('post-updated', {
          detail: { id: post.id, replies_locked: repliesLocked },
        })
      );
    } catch {
      actionError = 'Failed to update reply lock.';
    } finally {
      actionLoading = false;
    }
  }

  function handleAuthorAction(e: MouseEvent, action: 'silence' | 'suspend') {
    e.stopPropagation();
    showDropdown = false;
    if (!authorId) return;
    showAuthorActionConfirm = action;
  }

  async function confirmAuthorAction() {
    if (!authorId || !showAuthorActionConfirm) return;
    actionLoading = true;
    try {
      if (showAuthorActionConfirm === 'silence') {
        await silenceUser(authorId);
      } else {
        await suspendUser(authorId);
      }
      showAuthorActionConfirm = null;
    } catch {
      actionError = `Failed to ${showAuthorActionConfirm} author.`;
    } finally {
      actionLoading = false;
    }
  }

  function cancelAuthorAction() {
    showAuthorActionConfirm = null;
  }

  function handleWarnAuthor(e: MouseEvent) {
    e.stopPropagation();
    showDropdown = false;
    // Pre-fill the warning with the permalink so the user can see
    // exactly which post triggered it. Admins can overwrite; this is
    // just a sensible default.
    warnMessage = `Regarding your post: ${permalink}\n\n`;
    showWarnDialog = true;
  }

  async function confirmWarn() {
    if (!authorId || !warnMessage.trim()) return;
    actionLoading = true;
    try {
      await warnUser(authorId, warnMessage);
      showWarnDialog = false;
      warnMessage = '';
    } catch {
      actionError = 'Failed to send warning.';
    } finally {
      actionLoading = false;
    }
  }

  function cancelWarn() {
    showWarnDialog = false;
    warnMessage = '';
  }

  function handleAddNote(e: MouseEvent) {
    e.stopPropagation();
    showDropdown = false;
    noteContent = `Re: ${permalink}\n`;
    showNoteDialog = true;
  }

  async function confirmNote() {
    if (!authorId || !noteContent.trim()) return;
    actionLoading = true;
    try {
      await createModerationNote(authorId, noteContent);
      showNoteDialog = false;
      noteContent = '';
    } catch {
      actionError = 'Failed to add note.';
    } finally {
      actionLoading = false;
    }
  }

  function cancelNote() {
    showNoteDialog = false;
    noteContent = '';
  }

  async function handleCopyPermalink(e: MouseEvent) {
    e.stopPropagation();
    showDropdown = false;
    try {
      await navigator.clipboard.writeText(permalink);
    } catch {
      actionError = 'Failed to copy link.';
    }
  }

  async function handleCopyApUri(e: MouseEvent) {
    e.stopPropagation();
    showDropdown = false;
    const uri = (post as unknown as { uri?: string; ap_id?: string }).uri
      || (post as unknown as { ap_id?: string }).ap_id
      || '';
    if (!uri) {
      actionError = 'No AP URI on this post.';
      return;
    }
    try {
      await navigator.clipboard.writeText(uri);
    } catch {
      actionError = 'Failed to copy URI.';
    }
  }

  function handleViewAuthor(e: MouseEvent) {
    e.stopPropagation();
    showDropdown = false;
    if (!authorId) return;
    // /admin/user-management/users reads ?id= and pins the list to
    // exactly that identity (vs ?search= which matches substrings and
    // would also return any handle that happens to share a prefix).
    window.location.href = `/admin/user-management/users?id=${encodeURIComponent(authorId)}`;
  }

  async function handleRefetch(e: MouseEvent) {
    e.stopPropagation();
    showDropdown = false;
    actionLoading = true;
    try {
      await adminRefetchPost(post.id);
      // Nudge the post card to reload if consumers listen for this.
      window.dispatchEvent(
        new CustomEvent('post-updated', { detail: { id: post.id, refetched: true } })
      );
    } catch (err: unknown) {
      const e2 = err as { body?: { error?: string } };
      switch (e2?.body?.error) {
        case 'post.not_remote':
          actionError = 'Only remote posts can be re-fetched.';
          break;
        case 'post.origin_suspended':
          actionError = "Origin instance is suspended — can't refetch.";
          break;
        case 'post.origin_gone':
          actionError = 'Origin says this post was deleted (410 Gone).';
          break;
        default:
          actionError = 'Failed to re-fetch from origin.';
      }
    } finally {
      actionLoading = false;
    }
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
    class:admin-action-btn-hot={(post.open_report_count ?? 0) > 0}
    onclick={toggleDropdown}
    aria-label={post.open_report_count ? `Moderation actions (${post.open_report_count} open reports)` : 'Moderation actions'}
    aria-expanded={showDropdown}
    aria-haspopup="menu"
    title={post.open_report_count ? `${post.open_report_count} pending report${post.open_report_count === 1 ? '' : 's'} on this post` : 'Moderation actions'}
  >
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
    </svg>
    {#if (post.open_report_count ?? 0) > 0}
      <span class="admin-action-badge" aria-hidden="true">
        {post.open_report_count! > 9 ? '9+' : post.open_report_count}
      </span>
    {/if}
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
      <button type="button" class="admin-dropdown-item" role="menuitem" onclick={handleToggleHidden}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          {#if isHidden}
            <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>
          {:else}
            <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/>
          {/if}
        </svg>
        {isHidden ? 'Unhide from feeds' : 'Hide from feeds'}
      </button>
      <button type="button" class="admin-dropdown-item" role="menuitem" onclick={handleToggleReplyLock}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          {#if repliesLocked}
            <rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0"/>
          {:else}
            <rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
          {/if}
        </svg>
        {repliesLocked ? 'Unlock replies' : 'Lock replies'}
      </button>
      {#if hasMedia}
        <button type="button" class="admin-dropdown-item admin-dropdown-danger" role="menuitem" onclick={handleBanMedia}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
          </svg>
          Ban Media Hashes
        </button>
      {/if}

      {#if authorId}
        <div class="admin-dropdown-divider"></div>
        <button type="button" class="admin-dropdown-item" role="menuitem" onclick={handleWarnAuthor}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>
          </svg>
          Warn @{authorHandle}
        </button>
        <button type="button" class="admin-dropdown-item" role="menuitem" onclick={handleAddNote}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="9" y1="13" x2="15" y2="13"/><line x1="9" y1="17" x2="13" y2="17"/>
          </svg>
          Add moderation note
        </button>
        <button type="button" class="admin-dropdown-item admin-dropdown-danger" role="menuitem" onclick={(e) => handleAuthorAction(e, 'silence')}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><line x1="23" y1="9" x2="17" y2="15"/><line x1="17" y1="9" x2="23" y2="15"/>
          </svg>
          Silence @{authorHandle}
        </button>
        <button type="button" class="admin-dropdown-item admin-dropdown-danger" role="menuitem" onclick={(e) => handleAuthorAction(e, 'suspend')}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
          </svg>
          Suspend @{authorHandle}
        </button>
      {/if}

      <div class="admin-dropdown-divider"></div>
      <button type="button" class="admin-dropdown-item" role="menuitem" onclick={handleCopyPermalink}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
        </svg>
        Copy permalink
      </button>
      <button type="button" class="admin-dropdown-item" role="menuitem" onclick={handleCopyApUri}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
        </svg>
        Copy AP URI
      </button>
      {#if isRemote}
        <button type="button" class="admin-dropdown-item" role="menuitem" onclick={handleRefetch}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>
          </svg>
          Re-fetch from origin
        </button>
      {/if}
      {#if authorHandle}
        <button type="button" class="admin-dropdown-item" role="menuitem" onclick={handleViewAuthor}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>
          </svg>
          View author in admin
        </button>
      {/if}
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

{#if showWarnDialog}
  <div class="admin-overlay" onclick={cancelWarn} role="dialog" aria-modal="true" aria-label="Warn author">
    <div class="admin-dialog" onclick={(e) => e.stopPropagation()}>
      <h3 class="admin-dialog-title">Warn @{authorHandle}</h3>
      <p class="admin-dialog-message">
        The user will receive this message as a formal warning. The post permalink is pre-filled so they know which post triggered it — feel free to overwrite.
      </p>
      <div class="admin-dialog-form">
        <label class="admin-dialog-label" for="admin-warn-message">Warning message</label>
        <textarea
          id="admin-warn-message"
          class="admin-dialog-textarea"
          bind:value={warnMessage}
          placeholder="Explain what rule was violated..."
          rows="5"
        ></textarea>
        {#if actionError}<p class="admin-dialog-error">{actionError}</p>{/if}
      </div>
      <div class="admin-dialog-actions">
        <button type="button" class="admin-dialog-cancel" onclick={cancelWarn}>Cancel</button>
        <button type="button" class="admin-dialog-confirm" onclick={confirmWarn} disabled={actionLoading || !warnMessage.trim()}>
          {actionLoading ? 'Sending...' : 'Send warning'}
        </button>
      </div>
    </div>
  </div>
{/if}

{#if showNoteDialog}
  <div class="admin-overlay" onclick={cancelNote} role="dialog" aria-modal="true" aria-label="Add moderation note">
    <div class="admin-dialog" onclick={(e) => e.stopPropagation()}>
      <h3 class="admin-dialog-title">Note about @{authorHandle}</h3>
      <p class="admin-dialog-message">
        Private note attached to the user's account. Only staff can see it. Post permalink is pre-filled.
      </p>
      <div class="admin-dialog-form">
        <label class="admin-dialog-label" for="admin-note-content">Note</label>
        <textarea
          id="admin-note-content"
          class="admin-dialog-textarea"
          bind:value={noteContent}
          placeholder="E.g. 'Second spam attempt this week, watch closely'"
          rows="5"
        ></textarea>
        {#if actionError}<p class="admin-dialog-error">{actionError}</p>{/if}
      </div>
      <div class="admin-dialog-actions">
        <button type="button" class="admin-dialog-cancel" onclick={cancelNote}>Cancel</button>
        <button type="button" class="admin-dialog-confirm" onclick={confirmNote} disabled={actionLoading || !noteContent.trim()}>
          {actionLoading ? 'Saving...' : 'Save note'}
        </button>
      </div>
    </div>
  </div>
{/if}

{#if showAuthorActionConfirm}
  <div class="admin-overlay" onclick={cancelAuthorAction} role="dialog" aria-modal="true" aria-label="Confirm author action">
    <div class="admin-dialog" onclick={(e) => e.stopPropagation()}>
      <h3 class="admin-dialog-title">
        {showAuthorActionConfirm === 'silence' ? 'Silence' : 'Suspend'} @{authorHandle}?
      </h3>
      <p class="admin-dialog-message">
        {#if showAuthorActionConfirm === 'silence'}
          Silenced users can still post, but their content won't appear in public timelines for users who don't already follow them. Reversible.
        {:else}
          Suspended users can't log in and their content is hidden from every feed. This is a hard action — use it for clear violations. Reversible from the user's admin page.
        {/if}
      </p>
      {#if actionError}<p class="admin-dialog-error">{actionError}</p>{/if}
      <div class="admin-dialog-actions">
        <button type="button" class="admin-dialog-cancel" onclick={cancelAuthorAction}>Cancel</button>
        <button type="button" class="admin-dialog-confirm" onclick={confirmAuthorAction} disabled={actionLoading}>
          {actionLoading ? 'Working...' : (showAuthorActionConfirm === 'silence' ? 'Silence user' : 'Suspend user')}
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
    color: var(--color-warning);
    cursor: pointer;
    transition: color var(--transition-fast), background-color var(--transition-fast);
    line-height: 1;
    opacity: 0.7;
  }

  .admin-action-btn:hover {
    background: var(--color-warning-light);
    opacity: 1;
  }

  .admin-action-btn:focus-visible {
    outline: 2px solid var(--color-warning);
    outline-offset: 1px;
  }

  /* Red tint + full-opacity icon when there are pending reports on
     this post — makes "there is something to do here" glanceable in
     a crowded timeline. */
  .admin-action-btn-hot {
    color: var(--color-danger);
    opacity: 1;
  }

  .admin-action-btn-hot:hover {
    background: var(--color-danger-soft);
  }

  .admin-action-badge {
    position: absolute;
    top: -2px;
    inset-inline-end: -2px;
    min-width: 16px;
    height: 16px;
    padding: 0 4px;
    border-radius: 9999px;
    background: var(--color-danger);
    color: var(--color-text-on-primary);
    font-size: 0.65rem;
    font-weight: 700;
    line-height: 16px;
    text-align: center;
    pointer-events: none;
    box-shadow: 0 0 0 2px var(--color-surface);
  }

  .admin-post-actions {
    position: relative;
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
    box-shadow: var(--shadow-md);
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
    color: var(--color-danger);
  }

  .admin-dropdown-danger:hover {
    background: var(--color-danger-light);
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
    background: var(--color-danger);
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
    background: var(--scrim-medium);
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
    background: var(--color-surface-raised);
    border-radius: var(--radius-xl, 1rem);
    padding: var(--space-6, 1.5rem);
    max-width: 420px;
    width: 90%;
    box-shadow: var(--shadow-xl);
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
    color: var(--color-text-secondary);
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
    color: var(--color-text);
  }

  .admin-dialog-textarea {
    padding: var(--space-2, 0.5rem);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md, 0.5rem);
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text);
    background: var(--color-bg);
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
    color: var(--color-danger);
  }

  .admin-dialog-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3, 0.75rem);
  }

  .admin-dialog-cancel {
    padding: var(--space-2, 0.5rem) var(--space-4, 1rem);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md, 0.5rem);
    background: transparent;
    color: var(--color-text);
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
    background: var(--color-danger);
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
