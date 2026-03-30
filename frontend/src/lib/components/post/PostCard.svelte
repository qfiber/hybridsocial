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
  import ProfileHoverCard from '$lib/components/ui/ProfileHoverCard.svelte';

  // Seeded PRNG from post ID for deterministic wave patterns
  function seededRng(seed: string) {
    let h = 0;
    for (let i = 0; i < seed.length; i++) {
      h = Math.imul(31, h) + seed.charCodeAt(i) | 0;
    }
    return () => {
      h = Math.imul(h ^ (h >>> 16), 0x45d9f3b);
      h = Math.imul(h ^ (h >>> 13), 0x45d9f3b);
      h = (h ^ (h >>> 16)) >>> 0;
      return h / 0x100000000;
    };
  }

  function generateWavePaths(postId: string): string[] {
    const rng = seededRng(postId);
    const layers = 6;
    const paths: string[] = [];

    for (let l = 0; l < layers; l++) {
      const yBase = 10 + (l * 80) / layers + (rng() * 20 - 10);
      const points: [number, number][] = [];

      // Generate control points across the width
      for (let x = 0; x <= 100; x += 12 + rng() * 8) {
        const waveY = yBase + Math.sin((x / 100) * Math.PI * (1.5 + rng())) * (15 + rng() * 20);
        points.push([x, waveY + (rng() * 14 - 7)]);
      }
      points.push([100, points[points.length - 1][1]]);

      // Build smooth cubic bezier path
      let d = `M -5 ${points[0][1]}`;
      for (let i = 0; i < points.length - 1; i++) {
        const cx = (points[i][0] + points[i + 1][0]) / 2;
        d += ` C ${cx} ${points[i][1]}, ${cx} ${points[i + 1][1]}, ${points[i + 1][0]} ${points[i + 1][1]}`;
      }
      d += ` L 105 105 L -5 105 Z`;
      paths.push(d);
    }

    return paths;
  }

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
  let contentCollapsed = $state(!detail);
  let contentOverflows = $state(false);
  let contentEl: HTMLDivElement | undefined = $state();

  let fullHeight = $state(0);
  const collapsedHeight = 110; // ~4 lines: 4 * 15px * 1.65

  // Check if content overflows 4 lines
  $effect(() => {
    if (contentEl && !detail) {
      fullHeight = contentEl.scrollHeight;
      contentOverflows = fullHeight > collapsedHeight;
      if (!contentOverflows) contentCollapsed = false;
    }
  });

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

  let editSpoilerText = $state('');

  function startEditing() {
    editContent = post.content;
    editSpoilerText = post.spoiler_text || '';
    editError = '';
    editing = true;
  }

  async function saveEdit() {
    if (!editContent.trim()) return;
    editSaving = true;
    editError = '';
    try {
      const updated = await editPost(post.id, {
        content: editContent,
        ...(post.spoiler_text !== null ? { spoiler_text: editSpoilerText } : {}),
      });
      post.content = updated.content;
      post.content_html = updated.content_html;
      post.edited_at = updated.edited_at;
      if (updated.spoiler_text !== undefined) post.spoiler_text = updated.spoiler_text;
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

{#if post.tombstone}
<article class="post-card post-tombstone" role="article">
  <div class="tombstone-content">
    <span class="material-symbols-outlined tombstone-icon">delete</span>
    <p class="tombstone-text">This post has been deleted</p>
  </div>
</article>
{:else}
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
            <ProfileHoverCard handle={post.account.acct || post.account.handle}>
              <a href="/@{post.account.handle}" class="post-display-name">{displayName}</a>
            </ProfileHoverCard>
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
          {#if post.in_reply_to_account_id}
            <span>Replying to <a href="/post/{post.parent_id}" class="reply-to-link">a post</a></span>
          {:else}
            <span>Replying to a post</span>
          {/if}
        </div>
      {/if}

      <!-- Post body -->
      <div class="post-body">
        <div class="nsfw-container" class:nsfw-active={post.sensitive && post.spoiler_text} class:nsfw-revealed={showSensitive}>
          <div class="nsfw-content">
          {#if post.content_html}
            <div
              class="post-content"
              class:post-content-collapsed={contentCollapsed && contentOverflows}
              style={contentOverflows ? `max-height: ${contentCollapsed ? collapsedHeight : fullHeight}px` : ''}
              bind:this={contentEl}
            >
              {@html post.content_html}
            </div>
          {:else if post.content}
            <div
              class="post-content"
              class:post-content-collapsed={contentCollapsed && contentOverflows}
              style={contentOverflows ? `max-height: ${contentCollapsed ? collapsedHeight : fullHeight}px` : ''}
              bind:this={contentEl}
            >
              <p>{post.content}</p>
            </div>
          {/if}
          {#if contentOverflows && contentCollapsed}
            <button type="button" class="content-toggle-btn" onclick={(e) => { e.stopPropagation(); contentCollapsed = false; }}>
              <span class="material-symbols-outlined content-toggle-icon">expand_more</span>
              Show more
            </button>
          {/if}
          {#if contentOverflows && !contentCollapsed && !detail}
            <button type="button" class="content-toggle-btn content-toggle-collapse" onclick={(e) => { e.stopPropagation(); contentCollapsed = true; }}>
              <span class="material-symbols-outlined content-toggle-icon">expand_less</span>
              Show less
            </button>
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

          {#if post.card && !compact}
            <a href={post.card.url} class="link-card" target="_blank" rel="noopener noreferrer" onclick={(e) => e.stopPropagation()}>
              {#if post.card.image}
                <div class="link-card-image">
                  <img src={post.card.image} alt="" loading="lazy" />
                </div>
              {/if}
              <div class="link-card-body">
                {#if post.card.provider_name}
                  <span class="link-card-provider">{post.card.provider_name}</span>
                {/if}
                {#if post.card.title}
                  <span class="link-card-title">{post.card.title}</span>
                {/if}
                {#if post.card.description}
                  <span class="link-card-desc">{post.card.description}</span>
                {/if}
              </div>
            </a>
          {/if}
          </div>

          {#if post.sensitive && post.spoiler_text}
            {@const wavePaths = generateWavePaths(post.id)}
            <svg class="nsfw-noise-svg" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" preserveAspectRatio="none">
              <defs>
                <linearGradient id="nsfw-grad-{post.id}" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0%" stop-color="var(--color-primary)" stop-opacity="0.15" />
                  <stop offset="50%" stop-color="var(--color-primary)" stop-opacity="0.4" />
                  <stop offset="100%" stop-color="var(--color-primary)" stop-opacity="0.7" />
                </linearGradient>
              </defs>
              <rect width="100" height="100" fill="var(--color-primary)" opacity="0.08" />
              {#each wavePaths as d, i (i)}
                {@const rng2 = seededRng(post.id + '-anim-' + i)}
                {@const drift = 2 + rng2() * 3}
                {@const dur = 7 + rng2() * 9}
                {@const delay = rng2() * -dur}
                {@const driftX = 1 + rng2() * 2}
                {@const durX = 9 + rng2() * 12}
                {@const delayX = rng2() * -durX}
                <g opacity={0.08 + i * 0.07}>
                  <animateTransform
                    attributeName="transform"
                    type="translate"
                    values="0,0; {driftX},{drift}; -{driftX},0; 0,-{drift}; 0,0"
                    dur="{dur}s"
                    begin="{delay}s"
                    repeatCount="indefinite"
                    calcMode="spline"
                    keySplines="0.45 0.05 0.55 0.95; 0.45 0.05 0.55 0.95; 0.45 0.05 0.55 0.95; 0.45 0.05 0.55 0.95"
                  />
                  <path
                    {d}
                    fill="var(--color-primary)"
                  />
                </g>
              {/each}
            </svg>
            <div class="nsfw-frost-glass"></div>
            <div class="nsfw-overlay" onclick={(e) => e.stopPropagation()}>
              <span class="nsfw-badge">NSFW</span>
              <p class="nsfw-warning">
                {post.spoiler_text && post.spoiler_text !== 'true'
                  ? post.spoiler_text
                  : 'Warning: this content might not be suitable for everyone.'}
              </p>
              <button
                type="button"
                class="nsfw-reveal-btn"
                onclick={(e) => { e.stopPropagation(); showSensitive = true; }}
              >
                Show content
              </button>
            </div>
            <button
              type="button"
              class="nsfw-hide-btn"
              onclick={(e) => { e.stopPropagation(); showSensitive = false; contentCollapsed = true; }}
            >
              Hide content
            </button>
          {/if}
        </div>
      </div>

      {#if !compact}
        <div class="post-actions-divider"></div>
        <PostActions {post} onedit={startEditing} />
      {/if}
    </div>
  </div>
</article>
{/if}

{#if editing}
  <div class="edit-overlay" onclick={cancelEdit} role="dialog" aria-modal="true" aria-label="Edit post">
    <div class="edit-dialog" onclick={(e) => e.stopPropagation()}>
      <div class="edit-dialog-header">
        <h3 class="edit-dialog-title">Edit post</h3>
        <button type="button" class="edit-dialog-close" onclick={cancelEdit} aria-label="Close">
          <span class="material-symbols-outlined">close</span>
        </button>
      </div>

      {#if post.spoiler_text !== null && post.spoiler_text !== undefined}
        <input
          type="text"
          class="edit-cw-input"
          bind:value={editSpoilerText}
          placeholder="Content warning"
          aria-label="Content warning"
        />
      {/if}

      <textarea
        class="edit-textarea"
        bind:value={editContent}
        rows="6"
        aria-label="Edit post content"
        autofocus
      ></textarea>

      {#if editError}
        <p class="edit-error">{editError}</p>
      {/if}

      <div class="edit-dialog-actions">
        <button type="button" class="edit-cancel" onclick={cancelEdit}>Cancel</button>
        <button type="button" class="edit-save" onclick={saveEdit} disabled={editSaving || !editContent.trim()}>
          {editSaving ? 'Saving...' : 'Save'}
        </button>
      </div>
    </div>
  </div>
{/if}

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

  .post-tombstone {
    cursor: default;
    opacity: 0.6;
    padding: 16px 24px;
  }

  .post-tombstone:hover {
    background: var(--color-surface-container-lowest);
  }

  .tombstone-content {
    display: flex;
    align-items: center;
    gap: 10px;
    color: var(--color-text-tertiary);
  }

  .tombstone-icon {
    font-size: 20px;
  }

  .tombstone-text {
    font-size: 0.875rem;
    font-style: italic;
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

  .reply-to-link {
    color: var(--color-primary);
    text-decoration: none;
    font-weight: 500;
  }

  .reply-to-link:hover {
    text-decoration: underline;
  }

  /* Link Card */
  .link-card {
    display: flex;
    flex-direction: column;
    border: 1px solid var(--color-border);
    border-radius: 12px;
    overflow: hidden;
    margin-block-start: 8px;
    text-decoration: none;
    color: inherit;
    transition: background 150ms ease;
  }

  .link-card:hover {
    background: var(--color-surface);
  }

  .link-card-image {
    width: 100%;
    max-height: 200px;
    overflow: hidden;
  }

  .link-card-image img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .link-card-body {
    padding: 10px 14px;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .link-card-provider {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    text-transform: uppercase;
    font-weight: 600;
    letter-spacing: 0.03em;
  }

  .link-card-title {
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .link-card-desc {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    line-height: 1.4;
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
    white-space: pre-line;
    transition: max-height 0.4s cubic-bezier(0.22, 1, 0.36, 1);
    overflow: hidden;
  }

  .post-content-collapsed {
    -webkit-mask-image: linear-gradient(to bottom, black 55%, transparent 100%);
    mask-image: linear-gradient(to bottom, black 55%, transparent 100%);
  }

  .content-toggle-btn {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    margin-block-start: 8px;
    padding: 4px 14px 4px 8px;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    color: var(--color-text-secondary);
    font-size: 0.75rem;
    font-weight: 600;
    cursor: pointer;
    transition: background 150ms ease, color 150ms ease, border-color 150ms ease;
  }

  .content-toggle-btn:hover {
    background: var(--color-primary-soft, rgba(0, 128, 128, 0.08));
    color: var(--color-primary);
    border-color: var(--color-primary);
  }

  .content-toggle-icon {
    font-size: 18px;
  }

  .content-toggle-collapse {
    margin-block-start: 12px;
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
  .nsfw-container {
    position: relative;
    border-radius: 8px;
    overflow: hidden;
  }

  /* When NSFW is active (not yet revealed), enforce minimum height and hide content */
  .nsfw-active:not(.nsfw-revealed) {
    min-height: 220px;
  }

  /* Content: starts fully hidden, decodes into view AFTER overlay is gone */
  .nsfw-active .nsfw-content {
    filter: blur(20px) saturate(0);
    opacity: 0;
    transform: scale(1.05);
    transition: none;
    user-select: none;
    pointer-events: none;
  }

  .nsfw-active.nsfw-revealed .nsfw-content {
    filter: blur(0) saturate(1);
    opacity: 1;
    transform: scale(1);
    user-select: auto;
    pointer-events: auto;
    transition: filter 0.7s cubic-bezier(0.22, 1, 0.36, 1) 0.35s,
                opacity 0.5s ease 0.3s,
                transform 0.7s cubic-bezier(0.22, 1, 0.36, 1) 0.35s;
  }

  /* SVG noise background */
  .nsfw-noise-svg {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    z-index: 0;
    pointer-events: none;
    border-radius: inherit;
    opacity: 1;
    transition: opacity 0.6s ease 0.1s;
  }

  .nsfw-revealed .nsfw-noise-svg {
    opacity: 0;
    transition: opacity 0.4s ease;
  }

  /* Frost glass layer */
  .nsfw-frost-glass {
    position: absolute;
    inset: 0;
    z-index: 1;
    background: rgba(255, 255, 255, 0.3);
    backdrop-filter: blur(3px);
    border-radius: inherit;
    opacity: 1;
    transition: opacity 0.5s ease 0.05s;
    pointer-events: none;
  }

  .nsfw-revealed .nsfw-frost-glass {
    opacity: 0;
    transition: opacity 0.3s ease;
  }

  @media (prefers-color-scheme: dark) {
    .nsfw-frost-glass {
      background: rgba(0, 0, 0, 0.25);
    }
  }

  /* Overlay with badge, warning text, and button */
  .nsfw-overlay {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 16px;
    z-index: 2;
    padding: 24px;
    text-align: center;
    opacity: 1;
    transition: opacity 0.3s ease, transform 0.4s ease;
    pointer-events: auto;
  }

  .nsfw-revealed .nsfw-overlay {
    opacity: 0;
    transform: scale(0.95);
    pointer-events: none;
  }

  .nsfw-badge {
    font-size: 0.75rem;
    font-weight: 800;
    letter-spacing: 0.05em;
    color: #fff;
    background: rgba(220, 50, 50, 0.85);
    padding: 3px 12px;
    border-radius: 6px;
    text-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
  }

  .nsfw-warning {
    font-size: 0.9375rem;
    font-weight: 700;
    color: #fff;
    line-height: 1.4;
    margin: 0;
    max-width: 300px;
    text-shadow: 0 1px 4px rgba(0, 0, 0, 0.4);
  }

  .nsfw-reveal-btn {
    margin-top: 20px;
    padding: 6px 20px;
    border: 1px solid rgba(255, 255, 255, 0.4);
    border-radius: 9999px;
    background: rgba(255, 255, 255, 0.2);
    backdrop-filter: blur(4px);
    color: #fff;
    font-size: 0.8125rem;
    font-weight: 600;
    cursor: pointer;
    transition: background 150ms ease;
    text-shadow: 0 1px 2px rgba(0, 0, 0, 0.2);
  }

  .nsfw-reveal-btn:hover {
    background: rgba(255, 255, 255, 0.35);
  }

  /* Hide content button — only visible when revealed */
  .nsfw-hide-btn {
    display: block;
    margin: 8px auto 4px;
    padding: 4px 14px;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    background: var(--color-surface);
    color: var(--color-text-secondary);
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.12), 0 0 1px rgba(0, 0, 0, 0.08);
    font-size: var(--text-xs);
    font-weight: 600;
    cursor: pointer;
    position: relative;
    z-index: 3;
    opacity: 0;
    pointer-events: none;
    transition: opacity 0s ease;
  }

  .nsfw-revealed .nsfw-hide-btn {
    opacity: 1;
    pointer-events: auto;
    transition: opacity 0.3s ease 0.5s;
  }

  .nsfw-hide-btn:hover {
    background: var(--color-surface);
  }

  /* Edit form */
  .edit-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 9999;
    padding: var(--space-4);
    animation: edit-overlay-in 0.15s ease;
  }

  @keyframes edit-overlay-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .edit-dialog {
    background: var(--color-surface-container-lowest);
    border-radius: 18px;
    padding: 24px;
    max-width: 560px;
    width: 100%;
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.15);
    display: flex;
    flex-direction: column;
    gap: 12px;
    animation: edit-dialog-in 0.2s cubic-bezier(0.22, 1, 0.36, 1);
  }

  @keyframes edit-dialog-in {
    from { opacity: 0; transform: scale(0.95) translateY(4px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .edit-dialog-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .edit-dialog-title {
    font-size: 1.125rem;
    font-weight: 700;
    margin: 0;
  }

  .edit-dialog-close {
    background: transparent;
    border: none;
    color: var(--color-text-secondary);
    cursor: pointer;
    padding: 4px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .edit-dialog-close:hover {
    background: var(--color-surface-hover);
    color: var(--color-text);
  }

  .edit-dialog-actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  .edit-cw-input {
    width: 100%;
    padding: 8px 12px;
    border: 1px solid var(--color-border);
    border-radius: 8px;
    font-size: 14px;
    font-family: inherit;
    color: var(--color-text);
    background: var(--color-surface-container-lowest);
  }

  .edit-cw-input:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 2px var(--color-primary-soft);
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

  .nsfw-content {
    transition: filter 0.3s ease;
  }

  .post-actions-divider {
    height: 1px;
    background: rgba(188, 201, 200, 0.35);
    margin-top: 20px;
    margin-bottom: 12px;
  }
</style>
