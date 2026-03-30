<script lang="ts">
  import type { Post } from '$lib/api/types.js';
  import { api } from '$lib/api/client.js';
  import { authStore } from '$lib/stores/auth.js';
  import { mute, unmute, block, unblock } from '$lib/api/accounts.js';
  import { get } from 'svelte/store';
  import ReactionPicker from './ReactionPicker.svelte';

  let {
    post,
    onedit,
  }: {
    post: Post;
    onedit?: () => void;
  } = $props();

  const reactionEmojis: Record<string, string> = {
    like: '\u{1F600}',
    love: '\u{2764}\u{FE0F}',
    care: '\u{1F917}',
    angry: '\u{1F621}',
    sad: '\u{1F622}',
    lol: '\u{1F602}',
    wow: '\u{1F92F}',
  };

  let isBoosted = $state(post.is_boosted);
  let boostCount = $state(post.boost_count);
  let replyCount = $state(post.reply_count);
  let reactionCount = $state(post.reaction_count);
  let currentReaction = $state(post.current_user_reaction);
  let showReactionPicker = $state(false);
  let showMoreMenu = $state(false);
  let bounceReaction = $state(false);
  let floatingEmoji = $state<string | null>(null);
  let showReactionDetail = $state(false);
  let reactionDetailData = $state<{type: string; count: number; accounts: {id: string; handle: string; display_name: string | null; avatar_url: string | null}[]}[]>([]);
  let reactionDetailLoading = $state(false);
  let reactionDetailTab = $state('all');
  let reactions = $state(post.reactions || []);
  let isPostMuted = $state(false);

  let isOwnPost = $derived(() => {
    const state = get(authStore);
    return state.user?.id === post.account.id;
  });

  let isRemotePost = $derived(() => {
    const acct = post.account.acct || post.account.handle;
    return acct.includes('@');
  });

  let remotePostUrl = $derived(() => {
    return post.account.url;
  });

  // Confirmation dialog state
  let confirmAction: 'mute_user' | 'unmute_user' | 'block_user' | 'unblock_user' | null = $state(null);

  const confirmMessages: Record<string, { title: string; message: string; button: string }> = {
    mute_user: { title: 'Mute this user?', message: 'Their posts will be hidden from your feeds. They will not be notified.', button: 'Mute' },
    unmute_user: { title: 'Unmute this user?', message: 'Their posts will appear in your feeds again.', button: 'Unmute' },
    block_user: { title: 'Block this user?', message: 'They will not be able to see your posts or interact with you. You can unblock them at any time.', button: 'Block' },
    unblock_user: { title: 'Unblock this user?', message: 'They will be able to see your posts and interact with you again.', button: 'Unblock' },
  };

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
        // Remove from reactions array
        reactions = reactions
          .map(r => r.name === emoji ? { ...r, count: r.count - 1, me: false } : r)
          .filter(r => r.count > 0);
        currentReaction = null;
        reactionCount = Math.max(0, reactionCount - 1);
      } else {
        const previousReaction = currentReaction;
        const hadReaction = previousReaction !== null;
        await api.post(`/api/v1/statuses/${post.id}/react`, { type: emoji });
        currentReaction = emoji;
        if (!hadReaction) reactionCount += 1;

        // Remove old reaction from array if switching
        if (hadReaction && previousReaction !== emoji) {
          reactions = reactions.map(r => r.name === previousReaction ? { ...r, count: r.count - 1, me: false } : r).filter(r => r.count > 0);
        }

        // Add/increment new reaction (only if not already counted as mine)
        const existing = reactions.find(r => r.name === emoji);
        if (existing) {
          if (!existing.me) {
            reactions = reactions.map(r => r.name === emoji ? { ...r, count: r.count + 1, me: true } : r);
          }
        } else {
          reactions = [...reactions, { name: emoji, count: 1, me: true }];
        }
        // Trigger floating emoji animation
        floatingEmoji = emoji;
        setTimeout(() => { floatingEmoji = null; }, 800);
      }
      bounceReaction = true;
      setTimeout(() => { bounceReaction = false; }, 400);
    } catch {
      // Revert on error
    }
  }

  let hoverTimer: ReturnType<typeof setTimeout> | null = null;

  function toggleReactionPicker(e: MouseEvent) {
    e.stopPropagation();
    // If already reacted, clicking removes the reaction
    if (currentReaction) {
      handleReaction(currentReaction);
      return;
    }
    showReactionPicker = !showReactionPicker;
    showMoreMenu = false;
    showReactionDetail = false;
  }

  let closeTimer: ReturnType<typeof setTimeout> | null = null;

  function handleReactionHoverOut() {
    if (hoverTimer) {
      clearTimeout(hoverTimer);
      hoverTimer = null;
    }
    if (showReactionPicker) {
      closeTimer = setTimeout(() => {
        showReactionPicker = false;
      }, 100);
    }
  }

  function handleReactionHoverIn() {
    // Cancel close timer if re-entering
    if (closeTimer) {
      clearTimeout(closeTimer);
      closeTimer = null;
    }
    // Don't open picker if detail popover is showing
    if (showReactionPicker || showReactionDetail) return;
    hoverTimer = setTimeout(() => {
      showReactionPicker = true;
      showMoreMenu = false;
    }, 200);
  }

  let menuOpenUpward = $state(false);

  function toggleMoreMenu(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = !showMoreMenu;
    showReactionPicker = false;

    if (showMoreMenu) {
      // Check if the button is near the bottom of the viewport
      const btn = e.currentTarget as HTMLElement;
      const rect = btn.getBoundingClientRect();
      const spaceBelow = window.innerHeight - rect.bottom;
      menuOpenUpward = spaceBelow < 280;
    }
  }

  async function handleShare(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;

    const url = `${window.location.origin}/post/${post.id}`;
    const title = `Post by ${post.account.display_name || post.account.handle}`;
    const text = (post.content || '').slice(0, 200);

    if (navigator.share) {
      try {
        await navigator.share({ title, text, url });
        return;
      } catch {
        // User cancelled or share failed — fall through to copy
      }
    }

    // Fallback: copy link
    await navigator.clipboard.writeText(url);
    window.dispatchEvent(new CustomEvent('toast', { detail: { message: 'Link copied', type: 'success' } }));
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

  function handleQuote(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    window.dispatchEvent(new CustomEvent('open-composer', { detail: { quotePost: post } }));
  }

  // Edit history
  let showHistoryModal = $state(false);
  let historyData = $state<{id: string; content: string; content_html: string; edited_at: string; revision_number: number}[]>([]);
  let historyLoading = $state(false);

  async function handleViewHistory(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    showHistoryModal = true;
    historyLoading = true;
    try {
      historyData = await api.get(`/api/v1/statuses/${post.id}/history`);
    } catch { /* */ }
    finally { historyLoading = false; }
  }

  function handleDisplayOnInstance(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    const url = post.account.url;
    if (url) {
      // Construct the post URL on the remote instance from the actor URL
      const origin = new URL(url).origin;
      window.open(url, '_blank', 'noopener,noreferrer');
    }
  }

  function handleMuteNotifications(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    togglePostMute();
  }

  async function togglePostMute() {
    try {
      if (isPostMuted) {
        await api.delete(`/api/v1/statuses/${post.id}/mute`);
        isPostMuted = false;
      } else {
        await api.post(`/api/v1/statuses/${post.id}/mute`);
        isPostMuted = true;
      }
    } catch { /* handle error */ }
  }

  function handleMentionUser(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    const mention = post.account.acct || post.account.handle;
    window.dispatchEvent(new CustomEvent('open-composer', { detail: { prefill: `@${mention} ` } }));
  }

  function handleChatWithUser(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    window.location.href = `/messages?to=${post.account.handle}`;
  }

  function handleMuteUser(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    confirmAction = 'mute_user';
  }

  function handleBlockUser(e: MouseEvent) {
    e.stopPropagation();
    showMoreMenu = false;
    confirmAction = 'block_user';
  }

  async function executeConfirmedAction() {
    if (!confirmAction) return;
    try {
      switch (confirmAction) {
        case 'mute_user':
          await mute(post.account.id);
          break;
        case 'unmute_user':
          await unmute(post.account.id);
          break;
        case 'block_user':
          await block(post.account.id);
          break;
        case 'unblock_user':
          await unblock(post.account.id);
          break;
      }
    } catch { /* handle error */ }
    confirmAction = null;
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

  async function fetchReactionDetail() {
    if (reactionDetailLoading) return;
    showReactionDetail = !showReactionDetail;
    showReactionPicker = false;
    showMoreMenu = false;
    reactionDetailTab = 'all';
    if (!showReactionDetail) return;
    reactionDetailLoading = true;
    try {
      reactionDetailData = await api.get(`/api/v1/statuses/${post.id}/reactions`);
    } catch { /* */ }
    finally { reactionDetailLoading = false; }
  }

  // Close menus on outside click
  function handleWindowClick() {
    showReactionPicker = false;
    showMoreMenu = false;
    showReactionDetail = false;
  }
</script>

<svelte:window onclick={handleWindowClick} />

<div class="post-actions" role="group" aria-label="Post actions">
  <!-- Reaction stack + Like button -->
  <div class="action-reaction-wrapper" onmouseenter={handleReactionHoverIn} onmouseleave={handleReactionHoverOut}>
    <!-- Stacked emoji display (clickable for detail) -->
    {#if reactionCount > 0}
      {@const sorted = reactions.filter(r => r.count > 0).sort((a, b) => b.count - a.count)}
      <button
        type="button"
        class="reaction-stack"
        onclick={(e) => { e.stopPropagation(); fetchReactionDetail(); }}
        aria-label="View reactions"
      >
        <span class="reaction-stack-emojis">
          {#each sorted.slice(0, 3) as r, i (r.name)}
            <span class="reaction-stack-emoji" style="z-index: {3 - i}">{reactionEmojis[r.name] ?? r.name}</span>
          {/each}
        </span>
        <span class="reaction-stack-count">{reactionCount}</span>
      </button>
    {/if}

    <!-- Like/react button -->
    <button
      type="button"
      class="action-btn action-like"
      class:active-reaction={currentReaction !== null}
      class:bounce={bounceReaction}
      onclick={toggleReactionPicker}
      aria-label="React"
      aria-expanded={showReactionPicker}
    >
      {#if currentReaction}
        {#if currentReaction.startsWith(':') && currentReaction.endsWith(':')}
          <img class="current-reaction-custom" src="/api/v1/custom_emojis/{currentReaction.slice(1, -1)}/image" alt={currentReaction} />
        {:else}
          <span class="current-reaction">{reactionEmojis[currentReaction] ?? currentReaction}</span>
        {/if}
      {:else}
        <span class="material-symbols-outlined action-icon">favorite</span>
      {/if}
      {#if floatingEmoji}
        <span class="floating-emoji">{reactionEmojis[floatingEmoji] ?? floatingEmoji}</span>
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

  <!-- Reply -->
  <button
    type="button"
    class="action-btn action-reply"
    onclick={handleReply}
    onkeydown={(e) => handleActionKeydown(e, () => handleReply(new MouseEvent('click')))}
    aria-label="Reply ({replyCount})"
  >
    {#if replyCount > 0}
      <span class="material-symbols-outlined action-icon filled">chat_bubble</span>
      <span class="action-count">{replyCount}</span>
    {:else}
      <span class="material-symbols-outlined action-icon">chat_bubble</span>
    {/if}
  </button>

  <!-- Boost / Share -->
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

  <!-- Options (3 dots) -->
  <div class="action-more-wrapper">
    <button
      type="button"
      class="action-btn action-options"
      onclick={toggleMoreMenu}
      aria-label="More options"
      aria-expanded={showMoreMenu}
      aria-haspopup="menu"
    >
      <span class="material-symbols-outlined action-icon">more_horiz</span>
    </button>

    {#if showMoreMenu}
      <div class="more-menu" class:more-menu-upward={menuOpenUpward} role="menu">
        {#if isRemotePost()}
          <button type="button" class="more-menu-item" role="menuitem" onclick={handleDisplayOnInstance}>
            <span class="material-symbols-outlined menu-icon">open_in_new</span>
            Display on original instance
          </button>
        {/if}
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleQuote}>
          <span class="material-symbols-outlined menu-icon">format_quote</span>
          Quote post
        </button>
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleShare}>
          <span class="material-symbols-outlined menu-icon">share</span>
          Share
        </button>
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleCopyLink}>
          <span class="material-symbols-outlined menu-icon">link</span>
          Copy link
        </button>
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleBookmark}>
          <span class="material-symbols-outlined menu-icon">{post.is_bookmarked ? 'bookmark_remove' : 'bookmark'}</span>
          {post.is_bookmarked ? 'Remove bookmark' : 'Bookmark'}
        </button>
        <button type="button" class="more-menu-item" role="menuitem" onclick={handleMuteNotifications}>
          <span class="material-symbols-outlined menu-icon">{isPostMuted ? 'notifications_active' : 'notifications_off'}</span>
          {isPostMuted ? 'Unmute notifications' : 'Mute notifications'}
        </button>
        {#if isOwnPost()}
          {#if !post.edit_expires_at || new Date(post.edit_expires_at) > new Date()}
            <button type="button" class="more-menu-item" role="menuitem" onclick={handleEdit}>
              <span class="material-symbols-outlined menu-icon">edit</span>
              Edit
            </button>
          {/if}
          <button type="button" class="more-menu-item more-menu-danger" role="menuitem" onclick={handleDelete}>
            <span class="material-symbols-outlined menu-icon">delete</span>
            Delete
          </button>
        {/if}
        {#if post.edited_at}
          <button type="button" class="more-menu-item" role="menuitem" onclick={handleViewHistory}>
            <span class="material-symbols-outlined menu-icon">history</span>
            Edit history
          </button>
        {/if}
        {#if !isOwnPost()}
          <div class="more-menu-divider"></div>
          <button type="button" class="more-menu-item" role="menuitem" onclick={handleMentionUser}>
            <span class="material-symbols-outlined menu-icon">alternate_email</span>
            Mention @{post.account.acct || post.account.handle}
          </button>
          <button type="button" class="more-menu-item" role="menuitem" onclick={handleChatWithUser}>
            <span class="material-symbols-outlined menu-icon">chat</span>
            Chat with @{post.account.acct || post.account.handle}
          </button>
          <div class="more-menu-divider"></div>
          <button type="button" class="more-menu-item more-menu-danger" role="menuitem" onclick={handleMuteUser}>
            <span class="material-symbols-outlined menu-icon">volume_off</span>
            Mute @{post.account.acct || post.account.handle}
          </button>
          <button type="button" class="more-menu-item more-menu-danger" role="menuitem" onclick={handleBlockUser}>
            <span class="material-symbols-outlined menu-icon">block</span>
            Block @{post.account.acct || post.account.handle}
          </button>
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

{#if confirmAction}
  <div class="dialog-overlay" onclick={() => confirmAction = null} role="dialog" aria-modal="true" aria-label={confirmMessages[confirmAction].title}>
    <div class="dialog-panel" onclick={(e) => e.stopPropagation()}>
      <h3 class="dialog-title">{confirmMessages[confirmAction].title}</h3>
      <p class="dialog-message">{confirmMessages[confirmAction].message}</p>
      <div class="dialog-actions">
        <button type="button" class="dialog-cancel" onclick={() => confirmAction = null}>Cancel</button>
        <button
          type="button"
          class={confirmAction === 'block_user' || confirmAction === 'mute_user' ? 'dialog-confirm-danger' : 'dialog-confirm'}
          onclick={executeConfirmedAction}
        >
          {confirmMessages[confirmAction].button}
        </button>
      </div>
    </div>
  </div>
{/if}

{#if showReactionDetail}
  <div class="reactions-modal-overlay" onclick={() => showReactionDetail = false} role="dialog" aria-modal="true" aria-label="Reactions">
    <div class="reactions-modal" onclick={(e) => e.stopPropagation()}>
      <div class="reactions-modal-header">
        <h3 class="reactions-modal-title">Reactions</h3>
        <button type="button" class="reactions-modal-close" onclick={() => showReactionDetail = false} aria-label="Close">
          <span class="material-symbols-outlined">close</span>
        </button>
      </div>

      {#if reactionDetailLoading}
        <div class="reactions-modal-loading">Loading...</div>
      {:else}
        <div class="reactions-modal-tabs" role="tablist">
          <button
            type="button"
            role="tab"
            class="reactions-tab"
            class:reactions-tab-active={reactionDetailTab === 'all'}
            onclick={() => reactionDetailTab = 'all'}
          >
            All
          </button>
          {#each reactionDetailData as group (group.type)}
            <button
              type="button"
              role="tab"
              class="reactions-tab"
              class:reactions-tab-active={reactionDetailTab === group.type}
              onclick={() => reactionDetailTab = group.type}
            >
              <span class="reactions-tab-emoji">{reactionEmojis[group.type] ?? group.type}</span>
              <span class="reactions-tab-count">{group.count}</span>
            </button>
          {/each}
        </div>

        <div class="reactions-modal-list">
          {#each reactionDetailData as group (group.type)}
            {#if reactionDetailTab === 'all' || reactionDetailTab === group.type}
              {#each group.accounts as account (account.id)}
                <a href="/@{account.handle}" class="reactions-user" onclick={() => showReactionDetail = false}>
                  <div class="reactions-user-avatar-wrap">
                    {#if account.avatar_url}
                      <img src={account.avatar_url} alt="" class="reactions-user-avatar" />
                    {:else}
                      <div class="reactions-user-avatar reactions-user-avatar-placeholder">
                        {(account.display_name || account.handle).charAt(0).toUpperCase()}
                      </div>
                    {/if}
                    <span class="reactions-user-emoji">{reactionEmojis[group.type] ?? group.type}</span>
                  </div>
                  <div class="reactions-user-info">
                    <span class="reactions-user-name">{account.display_name || account.handle}</span>
                    <span class="reactions-user-handle">@{account.handle}</span>
                  </div>
                </a>
              {/each}
            {/if}
          {/each}
        </div>
      {/if}
    </div>
  </div>
{/if}

{#if showHistoryModal}
  <div class="reactions-modal-overlay" onclick={() => showHistoryModal = false} role="dialog" aria-modal="true" aria-label="Edit history">
    <div class="reactions-modal" onclick={(e) => e.stopPropagation()}>
      <div class="reactions-modal-header">
        <h3 class="reactions-modal-title">Edit History</h3>
        <button type="button" class="reactions-modal-close" onclick={() => showHistoryModal = false} aria-label="Close">
          <span class="material-symbols-outlined">close</span>
        </button>
      </div>

      {#if historyLoading}
        <div class="reactions-modal-loading">Loading...</div>
      {:else if historyData.length === 0}
        <div class="reactions-modal-loading">No edit history</div>
      {:else}
        <div class="history-list">
          {#each historyData as rev (rev.id)}
            <div class="history-item">
              <div class="history-meta">
                <span class="history-revision">Revision {rev.revision_number}</span>
                <span class="history-date">{new Date(rev.edited_at).toLocaleString()}</span>
              </div>
              <div class="history-content">
                {#if rev.content_html}
                  {@html rev.content_html}
                {:else}
                  <p>{rev.content}</p>
                {/if}
              </div>
            </div>
          {/each}
        </div>
      {/if}
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
  .action-options:hover {
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

  .current-reaction-custom {
    width: 20px;
    height: 20px;
    object-fit: contain;
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

  .floating-emoji {
    position: absolute;
    top: 50%;
    left: 50%;
    font-size: 1.25rem;
    pointer-events: none;
    animation: emoji-snap 0.5s cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
    z-index: 10;
  }

  @keyframes emoji-snap {
    0% {
      transform: translate(-50%, -50px) scale(1.8);
      opacity: 1;
    }
    50% {
      transform: translate(-50%, -50%) scale(0.7);
      opacity: 1;
    }
    70% {
      transform: translate(-50%, -50%) scale(1.15);
      opacity: 1;
    }
    85% {
      transform: translate(-50%, -50%) scale(0.95);
    }
    100% {
      transform: translate(-50%, -50%) scale(1);
      opacity: 0;
    }
  }

  .action-icon.filled {
    font-variation-settings: 'FILL' 1;
  }

  .action-reply:has(.filled) {
    color: var(--color-primary);
  }

  .action-reaction-wrapper {
    position: relative;
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .action-like {
    position: relative;
    overflow: visible;
  }

  /* ---- Stacked emoji display ---- */
  .reaction-stack {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    background: none;
    border: none;
    cursor: pointer;
    padding: 2px 4px;
    border-radius: 10px;
    transition: background 150ms ease;
  }

  .reaction-stack:hover {
    background: var(--color-surface);
  }

  .reaction-stack-emojis {
    display: flex;
    align-items: center;
    flex-direction: row-reverse;
  }

  .reaction-stack-emoji {
    line-height: 1;
    margin-inline-start: -6px;
    background: var(--color-surface-container-lowest);
    border: 2px solid var(--color-surface-container-lowest);
    border-radius: 50%;
    width: 22px;
    height: 22px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.8rem;
    position: relative;
    box-shadow: 0 0 0 0.5px rgba(0, 0, 0, 0.06);
  }

  .reaction-stack-emoji:last-child {
    margin-inline-start: 0;
  }

  .reaction-stack-count {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
    margin-inline-start: 4px;
  }

  /* ---- Reactions Modal ---- */
  .reactions-modal-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 9999;
    animation: overlay-fade-in 0.15s ease;
  }

  @keyframes overlay-fade-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .reactions-modal {
    background: var(--color-surface-container-lowest);
    border-radius: 18px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.15);
    width: 90%;
    max-width: 400px;
    max-height: 70vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    animation: modal-scale-in 0.2s cubic-bezier(0.22, 1, 0.36, 1);
  }

  @keyframes modal-scale-in {
    from { opacity: 0; transform: scale(0.95) translateY(8px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .reactions-modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 18px 20px 12px;
  }

  .reactions-modal-title {
    font-size: 1.125rem;
    font-weight: 700;
    color: var(--color-text);
  }

  .reactions-modal-close {
    background: none;
    border: none;
    color: var(--color-text-secondary);
    cursor: pointer;
    padding: 4px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    transition: background 150ms ease;
  }

  .reactions-modal-close:hover {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .reactions-modal-close .material-symbols-outlined {
    font-size: 22px;
  }

  .reactions-modal-loading {
    padding: 32px;
    text-align: center;
    color: var(--color-text-tertiary);
    font-size: 0.875rem;
  }

  /* Tabs */
  .reactions-modal-tabs {
    display: flex;
    gap: 0;
    padding: 0 20px;
    border-bottom: 2px solid var(--color-border);
    overflow-x: auto;
  }

  .reactions-tab {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 8px 14px;
    background: none;
    border: none;
    border-bottom: 2px solid transparent;
    margin-bottom: -2px;
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text-secondary);
    cursor: pointer;
    white-space: nowrap;
    transition: color 150ms ease, border-color 150ms ease;
  }

  .reactions-tab:hover {
    color: var(--color-text);
  }

  .reactions-tab-active {
    color: var(--color-primary);
    border-bottom-color: var(--color-primary);
  }

  .reactions-tab-emoji {
    font-size: 1rem;
  }

  .reactions-tab-count {
    font-size: 0.75rem;
    font-weight: 700;
  }

  /* User list */
  .reactions-modal-list {
    flex: 1;
    overflow-y: auto;
    padding: 8px 12px 16px;
  }

  .reactions-user {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px;
    border-radius: 12px;
    text-decoration: none;
    color: var(--color-text);
    transition: background 150ms ease;
  }

  .reactions-user:hover {
    background: var(--color-surface);
  }

  .reactions-user-avatar-wrap {
    position: relative;
    flex-shrink: 0;
  }

  .reactions-user-avatar {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    object-fit: cover;
    display: block;
  }

  .reactions-user-avatar-placeholder {
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--color-primary-soft);
    color: var(--color-primary);
    font-size: 1rem;
    font-weight: 700;
  }

  .reactions-user-emoji {
    position: absolute;
    bottom: -2px;
    inset-inline-end: -4px;
    font-size: 0.875rem;
    background: var(--color-surface-container-lowest);
    border-radius: 50%;
    width: 20px;
    height: 20px;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
  }

  .reactions-user-info {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .reactions-user-name {
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text);
  }

  .reactions-user-handle {
    font-size: 0.75rem;
    color: var(--color-text-secondary);
  }

  /* History modal */
  .history-list {
    padding: 0 16px 16px;
    display: flex;
    flex-direction: column;
    gap: 12px;
    max-height: 50vh;
    overflow-y: auto;
  }

  .history-item {
    padding: 12px;
    background: var(--color-surface);
    border-radius: 10px;
    border: 1px solid var(--color-border);
  }

  .history-meta {
    display: flex;
    justify-content: space-between;
    margin-block-end: 8px;
    font-size: 0.75rem;
  }

  .history-revision {
    font-weight: 700;
    color: var(--color-primary);
  }

  .history-date {
    color: var(--color-text-tertiary);
  }

  .history-content {
    font-size: 0.875rem;
    color: var(--color-text);
    line-height: 1.5;
  }

  .history-content :global(p) {
    margin: 0;
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
    animation: menu-roll-down 0.2s ease;
    transform-origin: top right;
  }

  .more-menu-upward {
    inset-block-start: auto;
    inset-block-end: 100%;
    margin-block-start: 0;
    margin-block-end: 4px;
    animation: menu-roll-up 0.2s ease;
    transform-origin: bottom right;
  }

  @keyframes menu-roll-up {
    from {
      opacity: 0;
      transform: scaleY(0.6) translateY(4px);
    }
    to {
      opacity: 1;
      transform: scaleY(1) translateY(0);
    }
  }

  @keyframes menu-roll-down {
    from {
      opacity: 0;
      transform: scaleY(0.6) translateY(-4px);
    }
    to {
      opacity: 1;
      transform: scaleY(1) translateY(0);
    }
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

  .more-menu-divider {
    height: 1px;
    background: var(--color-border);
    margin: 4px 8px;
  }

  .dialog-confirm {
    padding: 8px 20px;
    border: none;
    border-radius: 9999px;
    background: var(--color-primary);
    color: white;
    font-size: 0.875rem;
    font-weight: 700;
    cursor: pointer;
    transition: opacity 150ms ease;
  }

  .dialog-confirm:hover {
    opacity: 0.9;
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
