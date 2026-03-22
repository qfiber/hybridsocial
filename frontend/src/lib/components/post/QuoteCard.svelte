<script lang="ts">
  import type { Post } from '$lib/api/types.js';
  import { relativeTime, fullDateTime } from '$lib/utils/time.js';

  let {
    post,
  }: {
    post: Post;
  } = $props();

  let displayName = $derived(post.account.display_name || post.account.handle);
  let handle = $derived(`@${post.account.handle}`);
  let timeAgo = $derived(relativeTime(post.created_at));
  let fullDate = $derived(fullDateTime(post.created_at));

  function navigateToQuote(e: MouseEvent) {
    e.stopPropagation();
    window.location.href = `/post/${post.id}`;
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      e.stopPropagation();
      window.location.href = `/post/${post.id}`;
    }
  }
</script>

<div
  class="quote-card"
  role="article"
  tabindex="0"
  onclick={navigateToQuote}
  onkeydown={handleKeydown}
  aria-label="Quoted post by {displayName}"
>
  <div class="quote-header">
    {#if post.account.avatar_url}
      <img src={post.account.avatar_url} alt="" class="quote-avatar" loading="lazy" />
    {:else}
      <div class="quote-avatar-placeholder" aria-hidden="true">
        {displayName.charAt(0).toUpperCase()}
      </div>
    {/if}
    <span class="quote-name">{displayName}</span>
    <span class="quote-handle">{handle}</span>
    <span class="quote-separator" aria-hidden="true">&middot;</span>
    <time class="quote-time" datetime={post.created_at} title={fullDate}>{timeAgo}</time>
  </div>

  {#if post.content_html}
    <div class="quote-content">
      {@html post.content_html}
    </div>
  {:else if post.content}
    <div class="quote-content">
      <p>{post.content}</p>
    </div>
  {/if}
</div>

<style>
  .quote-card {
    margin-block-start: var(--space-3);
    padding: var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    cursor: pointer;
    transition: background-color var(--transition-fast);
  }

  .quote-card:hover {
    background: var(--color-bg-secondary);
  }

  .quote-card:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 1px;
  }

  .quote-header {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    margin-block-end: var(--space-2);
    font-size: var(--text-sm);
  }

  .quote-avatar {
    width: 20px;
    height: 20px;
    border-radius: var(--radius-full);
    object-fit: cover;
  }

  .quote-avatar-placeholder {
    width: 20px;
    height: 20px;
    border-radius: var(--radius-full);
    background: var(--color-primary);
    color: var(--color-text-inverse);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: var(--text-xs);
    font-weight: var(--font-semibold);
  }

  .quote-name {
    font-weight: var(--font-semibold);
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .quote-handle {
    color: var(--color-text-tertiary);
  }

  .quote-separator {
    color: var(--color-text-tertiary);
  }

  .quote-time {
    color: var(--color-text-tertiary);
  }

  .quote-content {
    font-size: var(--text-sm);
    line-height: var(--leading-relaxed);
    color: var(--color-text);
    overflow: hidden;
    display: -webkit-box;
    -webkit-line-clamp: 4;
    -webkit-box-orient: vertical;
  }

  .quote-content :global(a) {
    color: var(--color-primary);
  }
</style>
