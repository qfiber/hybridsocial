<script lang="ts">
  import type { Post } from '$lib/api/types.js';
  import { relativeTime, fullDateTime } from '$lib/utils/time.js';
  import { editPost } from '$lib/api/statuses.js';
  import { api } from '$lib/api/client.js';
  import PostActions from './PostActions.svelte';
  import QuoteCard from './QuoteCard.svelte';
  import LinkPreview from './LinkPreview.svelte';
  import VerifiedBadge from '$lib/components/ui/VerifiedBadge.svelte';
  import RoleBadge from '$lib/components/ui/RoleBadge.svelte';

  let {
    post,
    compact = false,
  }: {
    post: Post;
    compact?: boolean;
  } = $props();

  let showSensitive = $state(false);
  let timeAgo = $derived(relativeTime(post.created_at));
  let fullDate = $derived(fullDateTime(post.created_at));

  let avatarUrl = $derived(post.account.avatar_url || '');
  let displayName = $derived(post.account.display_name || post.account.handle);
  let handle = $derived(`@${post.account.handle}`);

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
    const target = e.target as HTMLElement;
    if (target.closest('a, button, [role="button"], video, audio, textarea, select, input')) return;
    navigateToPost();
  }

  function handleCardKeydown(e: KeyboardEvent) {
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
  role="article"
  tabindex="0"
  onclick={handleCardClick}
  onkeydown={handleCardKeydown}
  aria-label="Post by {displayName}"
>
  <div class="post-header">
    <div class="post-avatar">
      {#if avatarUrl}
        <img src={avatarUrl} alt="" class="avatar-img" loading="lazy" />
      {:else}
        <div class="avatar-placeholder" aria-hidden="true">
          {displayName.charAt(0).toUpperCase()}
        </div>
      {/if}
    </div>

    <div class="post-meta">
      <div class="post-author-line">
        <a href="/@{post.account.handle}" class="post-display-name">{displayName}</a>
        {#if (post.account as any).verified}
          <VerifiedBadge size="sm" />
        {/if}
        {#if (post.account as any).badges}
          {#each (post.account as any).badges as badge (badge.type)}
            <RoleBadge type={badge.type} label={badge.label} size="sm" />
          {/each}
        {/if}
        <span class="post-handle">{handle}</span>
        <span class="post-separator" aria-hidden="true">&middot;</span>
        <time class="post-time" datetime={post.created_at} title={fullDate}>
          {timeAgo}
        </time>
        {#if post.edited_at}
          <span class="post-edited" title="Edited {fullDateTime(post.edited_at)}">
            (edited)
          </span>
        {/if}
      </div>

      {#if post.parent_id}
        <div class="post-reply-indicator">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <polyline points="9 14 4 9 9 4"/>
            <path d="M20 20v-7a4 4 0 0 0-4-4H4"/>
          </svg>
          <span>replying to a post</span>
        </div>
      {/if}
    </div>
  </div>

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

    {#if !post.sensitive || showSensitive || !post.spoiler_text}
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
    {/if}
  </div>

  {#if !compact}
    <PostActions {post} onedit={startEditing} />
  {/if}
</article>

<style>
  .post-card {
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-4);
    cursor: pointer;
    transition: box-shadow var(--transition-base), border-color var(--transition-base);
  }

  .post-card:hover {
    box-shadow: var(--shadow-md);
    border-color: var(--color-border);
  }

  .post-card:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .post-card.compact {
    padding: var(--space-3);
  }

  .post-header {
    display: flex;
    align-items: flex-start;
    gap: var(--space-3);
    margin-block-end: var(--space-2);
  }

  .post-avatar {
    flex-shrink: 0;
  }

  .avatar-img {
    width: 40px;
    height: 40px;
    border-radius: var(--radius-full);
    object-fit: cover;
  }

  .compact .avatar-img {
    width: 32px;
    height: 32px;
  }

  .avatar-placeholder {
    width: 40px;
    height: 40px;
    border-radius: var(--radius-full);
    background: var(--color-primary);
    color: var(--color-text-inverse);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: var(--font-semibold);
    font-size: var(--text-sm);
  }

  .compact .avatar-placeholder {
    width: 32px;
    height: 32px;
    font-size: var(--text-xs);
  }

  .post-meta {
    flex: 1;
    min-width: 0;
  }

  .post-author-line {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    flex-wrap: wrap;
    font-size: var(--text-sm);
  }

  .post-display-name {
    font-weight: var(--font-semibold);
    color: var(--color-text);
    text-decoration: none;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .post-display-name:hover {
    text-decoration: underline;
  }

  .post-handle {
    color: var(--color-text-tertiary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .post-separator {
    color: var(--color-text-tertiary);
  }

  .post-time {
    color: var(--color-text-tertiary);
    white-space: nowrap;
  }

  .post-time:hover {
    text-decoration: underline;
  }

  .post-edited {
    color: var(--color-text-tertiary);
    font-size: var(--text-xs);
  }

  .post-reply-indicator {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-start: var(--space-1);
  }

  .post-body {
    padding-inline-start: calc(40px + var(--space-3));
  }

  .compact .post-body {
    padding-inline-start: calc(32px + var(--space-3));
  }

  .post-content {
    font-size: var(--text-sm);
    line-height: var(--leading-relaxed);
    color: var(--color-text);
    word-break: break-word;
    overflow-wrap: break-word;
  }

  .post-content :global(a) {
    color: var(--color-primary);
  }

  .post-content :global(p) {
    margin-block-end: var(--space-2);
  }

  .post-content :global(p:last-child) {
    margin-block-end: 0;
  }

  .post-cw {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3);
    background: var(--color-bg-tertiary);
    border-radius: var(--radius-md);
    margin-block-end: var(--space-2);
    font-size: var(--text-sm);
  }

  .cw-label {
    font-size: var(--text-xs);
    font-weight: var(--font-bold);
    color: var(--color-warning);
    background: var(--color-warning-light);
    padding: 1px var(--space-1);
    border-radius: var(--radius-sm);
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
    padding: var(--space-1) var(--space-2);
    border-radius: var(--radius-sm);
    white-space: nowrap;
  }

  .cw-toggle:hover {
    background: var(--color-primary-light);
  }

  /* Edit form */
  .edit-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
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
    line-height: var(--leading-relaxed);
  }

  .edit-textarea:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 2px var(--color-primary-light);
  }

  .edit-error {
    font-size: var(--text-sm);
    color: var(--color-danger);
  }

  .edit-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
  }

  .edit-cancel {
    padding: var(--space-1) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: transparent;
    color: var(--color-text);
    font-size: var(--text-sm);
    cursor: pointer;
  }

  .edit-cancel:hover {
    background: var(--color-bg-tertiary);
  }

  .edit-save {
    padding: var(--space-1) var(--space-3);
    border: none;
    border-radius: var(--radius-md);
    background: var(--color-primary);
    color: var(--color-text-inverse);
    font-size: var(--text-sm);
    font-weight: 600;
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
    gap: var(--space-1);
    margin-block-start: var(--space-3);
    border-radius: var(--radius-lg);
    overflow: hidden;
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
    background: var(--color-bg-tertiary);
  }

  .media-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
    max-height: 400px;
  }

  .media-grid-2 .media-img,
  .media-grid-4 .media-img {
    max-height: 220px;
  }

  .media-video {
    width: 100%;
    max-height: 400px;
    display: block;
  }

  .media-audio {
    padding: var(--space-3);
    display: flex;
    align-items: center;
  }

  .media-audio audio {
    width: 100%;
  }

  /* Poll */
  .post-poll {
    margin-block-start: var(--space-3);
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .poll-option {
    position: relative;
    padding: var(--space-2) var(--space-3);
    background: var(--color-bg-tertiary);
    border-radius: var(--radius-md);
    overflow: hidden;
    display: flex;
    align-items: center;
    font-size: var(--text-sm);
  }

  .poll-result {
    justify-content: space-between;
  }

  .poll-votable {
    border: 1px solid var(--color-border);
    background: transparent;
    cursor: pointer;
    gap: var(--space-2);
    width: 100%;
    text-align: start;
    font-family: inherit;
    color: var(--color-text);
    transition: background-color var(--transition-fast), border-color var(--transition-fast);
  }

  .poll-votable:hover {
    background: var(--color-bg-tertiary);
    border-color: var(--color-primary);
  }

  .poll-selected {
    border-color: var(--color-primary);
    background: var(--color-primary-light, rgba(99, 102, 241, 0.1));
  }

  .poll-check-indicator {
    flex-shrink: 0;
    font-size: var(--text-base);
    color: var(--color-primary);
    line-height: 1;
  }

  .poll-voted-check {
    color: var(--color-primary);
    font-weight: 700;
    margin-inline-end: var(--space-1);
  }

  .poll-bar {
    position: absolute;
    inset-block-start: 0;
    inset-inline-start: 0;
    height: 100%;
    background: var(--color-primary-light);
    transition: width var(--transition-slow);
    z-index: 0;
  }

  .poll-label {
    position: relative;
    z-index: 1;
  }

  .poll-pct {
    position: relative;
    z-index: 1;
    font-weight: var(--font-semibold);
    color: var(--color-text-secondary);
  }

  .poll-vote-btn {
    align-self: flex-start;
    padding: var(--space-1) var(--space-4);
    border: 1px solid var(--color-primary);
    border-radius: var(--radius-md);
    background: transparent;
    color: var(--color-primary);
    font-size: var(--text-sm);
    font-weight: 600;
    cursor: pointer;
    transition: background-color var(--transition-fast);
  }

  .poll-vote-btn:hover:not(:disabled) {
    background: var(--color-primary-light);
  }

  .poll-vote-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .poll-info {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }
</style>
