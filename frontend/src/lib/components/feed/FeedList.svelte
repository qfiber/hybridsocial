<script lang="ts">
  import { onMount } from 'svelte';
  import type { Post } from '$lib/api/types.js';
  import PostCard from '$lib/components/post/PostCard.svelte';
  import SkeletonPost from './SkeletonPost.svelte';

  let {
    posts = [],
    loading = false,
    hasMore = true,
    compact = false,
    emptyMessage = 'No posts yet',
    onloadmore,
  }: {
    posts?: Post[];
    loading?: boolean;
    hasMore?: boolean;
    compact?: boolean;
    emptyMessage?: string;
    onloadmore?: () => void;
  } = $props();

  let sentinelEl: HTMLDivElement | undefined = $state();
  let newPostsCount = $state(0);
  let showStagger = $state(true);

  // IntersectionObserver for infinite scroll
  onMount(() => {
    if (!sentinelEl) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && hasMore && !loading && onloadmore) {
          onloadmore();
        }
      },
      { rootMargin: '200px' }
    );

    observer.observe(sentinelEl);

    // Disable stagger after initial load
    setTimeout(() => { showStagger = false; }, 800);

    return () => observer.disconnect();
  });

  // Listen for new posts from SSE
  onMount(() => {
    function handleNewPost() {
      newPostsCount += 1;
    }

    window.addEventListener('feed-new-post', handleNewPost);
    return () => window.removeEventListener('feed-new-post', handleNewPost);
  });

  function showNewPosts() {
    // Trigger a refresh of the feed
    window.dispatchEvent(new CustomEvent('feed-refresh'));
    newPostsCount = 0;
  }
</script>

<div class="feed-list" role="feed" aria-label="Post feed">
  {#if newPostsCount > 0}
    <button
      type="button"
      class="new-posts-pill"
      onclick={showNewPosts}
    >
      {newPostsCount} new {newPostsCount === 1 ? 'post' : 'posts'}
    </button>
  {/if}

  {#if posts.length === 0 && !loading}
    <div class="feed-empty">
      <p class="feed-empty-text">{emptyMessage}</p>
    </div>
  {/if}

  {#each posts as entry, i (entry.id)}
    {@const isBoost = entry.type === 'boost'}
    {@const post = isBoost ? entry.post : entry}
    {#if post && post.content !== undefined}
      <div
        class="feed-item"
        style={showStagger ? `animation-delay: ${i * 60}ms` : ''}
        class:stagger={showStagger}
      >
        {#if isBoost}
          <div class="boost-label">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/>
              <polyline points="7 23 3 19 7 15"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/>
            </svg>
            <span>{entry.account?.display_name || entry.account?.handle || 'Someone'} boosted</span>
          </div>
        {/if}
        <PostCard {post} {compact} />
      </div>
    {/if}
  {/each}

  {#if loading}
    <div class="feed-loading">
      <SkeletonPost />
      <SkeletonPost />
      <SkeletonPost />
    </div>
  {/if}

  <div bind:this={sentinelEl} class="feed-sentinel" aria-hidden="true"></div>
</div>

<style>
  .boost-label {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: 0 var(--space-4);
    padding-block-start: var(--space-2);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .boost-label svg {
    color: var(--color-primary);
  }

  .feed-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    max-width: var(--feed-max-width);
    width: 100%;
    margin: 0 auto;
  }

  .new-posts-pill {
    position: sticky;
    inset-block-start: var(--header-height);
    align-self: center;
    padding: var(--space-2) var(--space-4);
    background: var(--color-primary);
    color: var(--color-text-inverse);
    border: none;
    border-radius: var(--radius-full);
    font-size: var(--text-sm);
    font-weight: var(--font-semibold);
    cursor: pointer;
    box-shadow: var(--shadow-md);
    z-index: var(--z-sticky);
    transition: background-color var(--transition-fast), transform var(--transition-fast);
    animation: pill-enter 0.3s ease;
  }

  .new-posts-pill:hover {
    background: var(--color-primary-hover);
    transform: scale(1.02);
  }

  @keyframes pill-enter {
    from {
      opacity: 0;
      transform: translateY(-10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .feed-item.stagger {
    animation: slide-up 0.3s ease both;
  }

  @keyframes slide-up {
    from {
      opacity: 0;
      transform: translateY(16px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .feed-empty {
    padding: var(--space-16) var(--space-4);
    text-align: center;
  }

  .feed-empty-text {
    font-size: var(--text-base);
    color: var(--color-text-tertiary);
  }

  .feed-loading {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .feed-sentinel {
    height: 1px;
  }
</style>
