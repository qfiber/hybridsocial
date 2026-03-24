<script lang="ts">
  import type { Post } from '$lib/api/types.js';
  import { relativeTime, fullDateTime } from '$lib/utils/time.js';
  import { editPost } from '$lib/api/statuses.js';
  import { api } from '$lib/api/client.js';
  import { isStaffMember } from '$lib/stores/auth.js';
  import PostActions from './PostActions.svelte';
  import AdminPostActions from '$lib/components/admin/AdminPostActions.svelte';
  import QuoteCard from './QuoteCard.svelte';
  import LinkPreview from './LinkPreview.svelte';
  import VerifiedBadge from '$lib/components/ui/VerifiedBadge.svelte';
  import RoleBadge from '$lib/components/ui/RoleBadge.svelte';

  let {
    post,
    compact = false,
    detail = false,
  }: {
    post: Post;
    compact?: boolean;
    detail?: boolean;
  } = $props();

  let showSensitive = $state(false);
  let timeAgo = $derived(relativeTime(post.created_at));
  let fullDate = $derived(fullDateTime(post.created_at));

  let avatarUrl = $derived(post.account.avatar_url || '');
  let displayName = $derived(post.account.display_name || post.account.handle);
  let domain = $derived((post.account as any).domain as string | null);
  let isRemote = $derived(!!domain);
  let handle = $derived(isRemote ? `@${post.account.handle}` : `@${post.account.handle}`);
  let instanceFavicon = $derived(domain ? `https://www.google.com/s2/favicons?domain=${domain}&sz=16` : null);

  // Media grid class based on count
  let mediaAttachments = $derived(post.media_attachments || []);
  let mediaCount = $derived(mediaAttachments.length);
  let mediaGridClass = $derived(
    mediaCount === 1 ? 'media-grid-1'
    : mediaCount === 2 ? 'media-grid-2'
    : 'media-grid-4'
  );

  // Edit mode
  let editing = $state(false);
  let editContent = $state('');
  let editSaving = $state(false);
  let editError = $state('');

  function startEditing() {
    editContent = post.content;
    editError = '';
    editing = true;
  }

  async function saveEdit() {
    if (!editContent.trim()) return;
    editSaving = true;
    editError = '';
    try {
      const updated = await editPost(post.id, { content: editContent });
      post.content = updated.content;
      post.content_html = updated.content_html;
      post.edited_at = updated.edited_at;
      editing = false;
    } catch {
      editError = 'Failed to save edit. Please try again.';
    } finally {
      editSaving = false;
    }
  }

  function cancelEdit() {
    editing = false;
    editError = '';
  }

  // Poll voting
  let pollVoted = $state(post.poll?.voted ?? false);
  let pollOwnVotes = $state<number[]>(post.poll?.own_votes ?? []);
  let pollOptions = $state(post.poll?.options ?? []);
  let pollVotesCount = $state(post.poll?.votes_count ?? 0);
  let pollVotersCount = $state(post.poll?.voters_count ?? 0);
  let pollExpired = $state(post.poll?.expired ?? false);
  let selectedPollOptions = $state<number[]>([]);
  let pollVoting = $state(false);

  let showPollResults = $derived(pollVoted || pollExpired);

  function togglePollOption(index: number) {
    if (showPollResults || pollVoting) return;
    if (post.poll?.multiple) {
      if (selectedPollOptions.includes(index)) {
        selectedPollOptions = selectedPollOptions.filter((i) => i !== index);
      } else {
        selectedPollOptions = [...selectedPollOptions, index];
      }
    } else {
      selectedPollOptions = [index];
    }
  }

  async function submitPollVote() {
    if (!post.poll || selectedPollOptions.length === 0 || pollVoting) return;
    pollVoting = true;
    try {
      const result = await api.post<typeof post.poll>(`/api/v1/polls/${post.poll.id}/votes`, {
        choices: selectedPollOptions,
      });
      pollVoted = true;
      pollOwnVotes = result.own_votes;
      pollOptions = result.options;
      pollVotesCount = result.votes_count;
      pollVotersCount = result.voters_count;
      pollExpired = result.expired;
    } catch {
      // Handle error silently
    } finally {
      pollVoting = false;
    }
  }

  function navigateToPost() {
    window.location.href = `/post/${post.id}`;
  }

  function handleCardClick(e: MouseEvent) {
    if (detail) return;
    const selection = window.getSelection();
    if (selection && selection.toString().length > 0) return;
    const target = e.target as HTMLElement;
    if (target.closest('a, button, [role="button"], video, audio, textarea, select, input')) return;
    navigateToPost();
  }

  function handleCardKeydown(e: KeyboardEvent) {
    if (detail) return;
    if (e.key === 'Enter' || e.key === ' ') {
      const target = e.target as HTMLElement;
      if (target.closest('a, button, [role="button"], textarea, select, input')) return;
      e.preventDefault();
      navigateToPost();
    }
  }
</script>

<article
  class="post-card"
  class:compact
  class:detail
  role="article"
  tabindex={detail ? -1 : 0}
  onclick={handleCardClick}
  onkeydown={handleCardKeydown}
  aria-label="Post by {displayName}"
>
  <div class="post-layout">
    <!-- Avatar column -->
    <div class="post-avatar">
      {#if avatarUrl}
        <img src={avatarUrl} alt="" class="avatar-img" loading="lazy" />
      {:else}
        <div class="avatar-placeholder" aria-hidden="true">
          {displayName.charAt(0).toUpperCase()}
        </div>
      {/if}
    </div>

    <!-- Content column -->
    <div class="post-content-col">
      <div class="post-author-line">
        <div class="post-author-info">
          <div class="post-author-name-row">
            <a href="/@{post.account.handle}" class="post-display-name">{displayName}</a>
            {#if (post.account as any).verified}
              <VerifiedBadge size="sm" />
            {/if}
            {#if (post.account as any).badges}
              {#each (post.account as any).badges as badge (badge.type)}
                <RoleBadge type={badge.type} label={badge.label} size="sm" />
              {/each}
            {/if}
          </div>
          <div class="post-meta-row">
            <span class="post-handle">{handle}</span>
            {#if instanceFavicon}
              <img src={instanceFavicon} alt={domain} class="instance-favicon" loading="lazy" />
            {/if}
            <span class="post-dot" aria-hidden="true">&middot;</span>
            <time class="post-time" datetime={post.created_at} title={fullDate}>{timeAgo}</time>
            {#if post.edited_at}
              <span class="post-edited" title="Edited {fullDateTime(post.edited_at)}">(edited)</span>
            {/if}
          </div>
        </div>
        {#if $isStaffMember}
          <AdminPostActions {post} />
        {/if}
      </div>

      {#if post.parent_id}
        <div class="post-reply-indicator">
          <span class="material-symbols-outlined reply-icon" aria-hidden="true">reply</span>
          <span>replying to a post</span>
        </div>
      {/if}

      <!-- Post body -->
      <div class="post-body">
        {#if post.sensitive && post.spoiler_text}
          <div class="post-cw">
            <span class="cw-label">CW</span>
            <span class="cw-text">{post.spoiler_text}</span>
            <button
              type="button"
              class="cw-toggle"
              onclick={(e) => { e.stopPropagation(); showSensitive = !showSensitive; }}
              aria-expanded={showSensitive}
            >
              {showSensitive ? 'Show less' : 'Show more'}
            </button>
          </div>
        {/if}

        <div class="cw-reveal" class:cw-revealed={!post.sensitive || showSensitive || !post.spoiler_text}>
          <div class="cw-reveal-inner">
          {#if editing}
            <div class="edit-form">
              <textarea
                class="edit-textarea"
                bind:value={editContent}
                rows="4"
                aria-label="Edit post content"
              ></textarea>
              {#if editError}
                <p class="edit-error">{editError}</p>
              {/if}
              <div class="edit-actions">
                <button type="button" class="edit-cancel" onclick={cancelEdit}>Cancel</button>
                <button type="button" class="edit-save" onclick={saveEdit} disabled={editSaving || !editContent.trim()}>
                  {editSaving ? 'Saving...' : 'Save'}
                </button>
              </div>
            </div>
          {:else if post.content_html}
            <div class="post-content">
              {@html post.content_html}
            </div>
          {:else if post.content}
            <div class="post-content">
              <p>{post.content}</p>
            </div>
          {/if}

          {#if mediaCount > 0 && !compact}
            <div class="media-grid {mediaGridClass}">
              {#each mediaAttachments as media (media.id)}
                {#if media.type === 'image' || media.type === 'gifv'}
                  <div class="media-item">
                    <img
                      src={media.preview_url || media.url}
                      alt={media.description || ''}
                      class="media-img"
                      loading="lazy"
                    />
                  </div>
                {:else if media.type === 'video'}
                  <div class="media-item">
                    <video
                      src={media.url}
                      controls
                      preload="metadata"
                      class="media-video"
                      aria-label={media.description || 'Video attachment'}
                    >
                      <track kind="captions" />
                    </video>
                  </div>
                {:else if media.type === 'audio'}
                  <div class="media-item media-audio">
                    <audio
                      src={media.url}
                      controls
                      preload="metadata"
                      aria-label={media.description || 'Audio attachment'}
                    ></audio>
                  </div>
                {/if}
              {/each}
            </div>
          {/if}

          {#if post.poll && !compact}
            <div class="post-poll">
              {#each pollOptions as option, i (i)}
                {#if showPollResults}
                  <div class="poll-option poll-result">
                    <div class="poll-bar" style="width: {pollVotesCount > 0 ? (option.votes_count / pollVotesCount * 100) : 0}%"></div>
                    <span class="poll-label">
                      {#if pollOwnVotes.includes(i)}
                        <span class="poll-voted-check" aria-label="Your vote">&#10003;</span>
                      {/if}
                      {option.title}
                    </span>
                    <span class="poll-pct">
                      {pollVotesCount > 0 ? Math.round(option.votes_count / pollVotesCount * 100) : 0}%
                    </span>
                  </div>
                {:else}
                  <button
                    type="button"
                    class="poll-option poll-votable"
                    class:poll-selected={selectedPollOptions.includes(i)}
                    onclick={(e) => { e.stopPropagation(); togglePollOption(i); }}
                  >
                    <span class="poll-check-indicator">
                      {#if post.poll?.multiple}
                        {#if selectedPollOptions.includes(i)}&#9632;{:else}&#9633;{/if}
                      {:else}
                        {#if selectedPollOptions.includes(i)}&#9679;{:else}&#9675;{/if}
                      {/if}
                    </span>
                    <span class="poll-label">{option.title}</span>
                  </button>
                {/if}
              {/each}

              {#if !showPollResults && selectedPollOptions.length > 0}
                <button
                  type="button"
                  class="poll-vote-btn"
                  onclick={(e) => { e.stopPropagation(); submitPollVote(); }}
                  disabled={pollVoting}
                >
                  {pollVoting ? 'Voting...' : 'Vote'}
                </button>
              {/if}

              <div class="poll-info">
                {pollVotersCount} {pollVotersCount === 1 ? 'voter' : 'voters'}
                &middot; {pollVotesCount} {pollVotesCount === 1 ? 'vote' : 'votes'}
                {#if post.poll.expires_at && !pollExpired}
                  &middot; ends {relativeTime(post.poll.expires_at)}
                {:else if pollExpired}
                  &middot; closed
                {/if}
              </div>
            </div>
          {/if}

          {#if post.quote && !compact}
            <QuoteCard post={post.quote} />
          {/if}
          </div>
        </div>
      </div>

      {#if !compact}
        <div class="post-actions-divider"></div>
        <PostActions {post} onedit={startEditing} />
      {/if}
    </div>
  </div>
</article>

<style>
  .post-card {
    background: var(--color-surface-container-lowest);
    border: var(--ghost-border);
    border-radius: var(--radius-xl);
    padding: 24px;
    cursor: pointer;
    box-shadow: 0 2px 10px rgba(25, 28, 29, 0.14);
    transition: background-color 300ms ease, box-shadow 300ms ease;
    user-select: text;
  }

  .post-card.detail {
    cursor: default;
  }

  .post-card:hover {
    background: var(--color-surface);
  }

  .post-card:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .post-card.compact {
    padding: 16px;
  }

  /* Main flex layout: avatar + content */
  .post-layout {
    display: flex;
    gap: 16px;
  }

  .post-avatar {
    flex-shrink: 0;
  }

  .avatar-img {
    width: 48px;
    height: 48px;
    border-radius: 9999px;
    object-fit: cover;
  }

  .compact .avatar-img {
    width: 36px;
    height: 36px;
  }

  .avatar-placeholder {
    width: 48px;
    height: 48px;
    border-radius: 9999px;
    background: var(--color-primary);
    color: var(--color-on-primary);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 700;
    font-size: 1rem;
  }

  .compact .avatar-placeholder {
    width: 36px;
    height: 36px;
    font-size: 0.8rem;
  }

  .post-content-col {
    flex: 1;
    min-width: 0;
  }

  /* Author line */
  .post-author-line {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-end: 2px;
  }

  .post-author-info {
    display: flex;
    flex-direction: column;
    gap: 0;
    min-width: 0;
  }

  .post-author-name-row {
    display: flex;
    align-items: center;
    gap: 4px;
    min-width: 0;
  }

  .post-display-name {
    font-weight: 700;
    font-size: 16px;
    color: var(--color-text);
    text-decoration: none;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .post-display-name:hover {
    text-decoration: underline;
  }

  .post-meta-row {
    display: flex;
    align-items: center;
    gap: 4px;
    margin-top: 1px;
  }

  .post-handle {
    font-size: 0.8125rem;
    color: var(--color-text-secondary);
    max-width: 200px;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }

  .instance-favicon {
    width: 14px;
    height: 14px;
    border-radius: 3px;
    flex-shrink: 0;
  }

  .post-dot {
    flex-shrink: 0;
    color: var(--color-text-tertiary);
    font-size: 0.8125rem;
  }

  .post-time {
    white-space: nowrap;
    color: var(--color-text-secondary);
    font-size: 0.8125rem;
  }

  .post-time:hover {
    text-decoration: underline;
  }

  .post-edited {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .post-reply-indicator {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    margin-block-end: 4px;
  }

  .reply-icon {
    font-size: 14px;
  }

  /* Post body */
  .post-body {
    margin-block-start: 4px;
  }

  .post-content {
    font-size: 15px;
    line-height: 1.65;
    color: var(--color-text);
    word-break: break-word;
    overflow-wrap: break-word;
  }

  .post-content :global(a) {
    color: var(--color-primary);
    font-weight: 500;
  }

  .post-content :global(.hashtag),
  .post-content :global(a[href*="/tags/"]) {
    color: var(--color-primary);
    font-weight: 500;
  }

  .post-content :global(p) {
    margin-block-end: 8px;
  }

  .post-content :global(p:last-child) {
    margin-block-end: 0;
  }

  /* CW */
  .post-cw {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    background: var(--color-surface);
    border-radius: 8px;
    margin-block-end: 8px;
    font-size: 0.875rem;
  }

  .cw-label {
    font-size: var(--text-xs);
    font-weight: 700;
    color: var(--color-warning);
    background: var(--color-warning-soft);
    padding: 1px 6px;
    border-radius: 4px;
    flex-shrink: 0;
  }

  .cw-text {
    flex: 1;
    color: var(--color-text);
  }

  .cw-toggle {
    font-size: var(--text-xs);
    color: var(--color-primary);
    background: none;
    border: none;
    cursor: pointer;
    padding: 4px 8px;
    border-radius: 4px;
    white-space: nowrap;
    font-weight: 600;
  }

  .cw-toggle:hover {
    background: var(--color-primary-soft);
  }

  /* Edit form */
  .edit-form {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .edit-textarea {
    width: 100%;
    padding: 8px 12px;
    border: 1px solid var(--color-border);
    border-radius: 8px;
    font-size: 15px;
    font-family: inherit;
    color: var(--color-text);
    background: var(--color-surface-container-lowest);
    resize: vertical;
    line-height: 1.65;
  }

  .edit-textarea:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 2px var(--color-primary-soft);
  }

  .edit-error {
    font-size: 0.875rem;
    color: var(--color-danger);
  }

  .edit-actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  .edit-cancel {
    padding: 6px 16px;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    background: transparent;
    color: var(--color-text);
    font-size: 0.875rem;
    cursor: pointer;
  }

  .edit-cancel:hover {
    background: var(--color-surface);
  }

  .edit-save {
    padding: 6px 16px;
    border: none;
    border-radius: 9999px;
    background: var(--color-primary);
    color: var(--color-on-primary);
    font-size: 0.875rem;
    font-weight: 700;
    cursor: pointer;
  }

  .edit-save:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .edit-save:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  /* Media Grid */
  .media-grid {
    display: grid;
    gap: 4px;
    margin-block-start: 12px;
    border-radius: 12px;
    overflow: hidden;
    border: var(--ghost-border);
  }

  .media-grid-1 {
    grid-template-columns: 1fr;
  }

  .media-grid-2 {
    grid-template-columns: 1fr 1fr;
  }

  .media-grid-4 {
    grid-template-columns: 1fr 1fr;
    grid-template-rows: auto auto;
  }

  .media-item {
    position: relative;
    overflow: hidden;
    background: var(--color-surface);
  }

  .media-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
    max-height: 400px;
    aspect-ratio: 16 / 9;
  }

  .media-grid-2 .media-img,
  .media-grid-4 .media-img {
    max-height: 220px;
  }

  .media-video {
    width: 100%;
    max-height: 400px;
    display: block;
    aspect-ratio: 16 / 9;
  }

  .media-audio {
    padding: 12px;
    display: flex;
    align-items: center;
  }

  .media-audio audio {
    width: 100%;
  }

  /* Poll */
  .post-poll {
    margin-block-start: 12px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .poll-option {
    position: relative;
    padding: 10px 14px;
    background: var(--color-surface);
    border-radius: 10px;
    overflow: hidden;
    display: flex;
    align-items: center;
    font-size: 0.875rem;
  }

  .poll-result {
    justify-content: space-between;
  }

  .poll-votable {
    border: 1px solid var(--color-border);
    background: transparent;
    cursor: pointer;
    gap: 8px;
    width: 100%;
    text-align: start;
    font-family: inherit;
    color: var(--color-text);
    transition: background-color 150ms ease, border-color 150ms ease;
  }

  .poll-votable:hover {
    background: var(--color-surface);
    border-color: var(--color-primary);
  }

  .poll-selected {
    border-color: var(--color-primary);
    background: var(--color-primary-soft);
  }

  .poll-check-indicator {
    flex-shrink: 0;
    font-size: 1rem;
    color: var(--color-primary);
    line-height: 1;
  }

  .poll-voted-check {
    color: var(--color-primary);
    font-weight: 700;
    margin-inline-end: 4px;
  }

  .poll-bar {
    position: absolute;
    inset-block-start: 0;
    inset-inline-start: 0;
    height: 100%;
    background: var(--color-primary-soft);
    transition: width 300ms ease;
    z-index: 0;
  }

  .poll-label {
    position: relative;
    z-index: 1;
  }

  .poll-pct {
    position: relative;
    z-index: 1;
    font-weight: 600;
    color: var(--color-text-secondary);
  }

  .poll-vote-btn {
    align-self: flex-start;
    padding: 6px 20px;
    border: 1px solid var(--color-primary);
    border-radius: 9999px;
    background: transparent;
    color: var(--color-primary);
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    transition: background-color 150ms ease;
  }

  .poll-vote-btn:hover:not(:disabled) {
    background: var(--color-primary-soft);
  }

  .poll-vote-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .poll-info {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  /* CW reveal animation */
  .cw-reveal {
    display: grid;
    grid-template-rows: 0fr;
    transition: grid-template-rows 0.35s ease;
  }

  .cw-revealed {
    grid-template-rows: 1fr;
  }

  .cw-reveal-inner {
    overflow: hidden;
  }

  .post-actions-divider {
    height: 1px;
    background: rgba(188, 201, 200, 0.35);
    margin-top: 20px;
    margin-bottom: 12px;
  }
</style>
