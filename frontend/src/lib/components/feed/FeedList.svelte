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
            <span class="material-symbols-outlined boost-icon">cached</span>
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
  .feed-list {
    display: flex;
    flex-direction: column;
    gap: 28px;
    max-width: var(--feed-max-width);
    width: 100%;
    margin: 0 auto;
  }

  .boost-label {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 24px;
    padding-block-end: 4px;
    font-size: 0.875rem;
    color: var(--color-text-secondary);
    font-weight: 500;
  }

  .boost-icon {
    font-size: 16px;
    color: var(--color-primary);
  }

  .new-posts-pill {
    position: sticky;
    inset-block-start: var(--header-height);
    align-self: center;
    padding: 8px 20px;
    background: var(--color-primary);
    color: var(--color-on-primary);
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    box-shadow: 0 4px 12px rgba(0, 106, 105, 0.25);
    z-index: var(--z-sticky);
    transition: background-color 150ms ease, transform 150ms ease;
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
    padding: 80px 16px;
    text-align: center;
  }

  .feed-empty-text {
    font-size: 1rem;
    color: var(--color-text-tertiary);
  }

  .feed-loading {
    display: flex;
    flex-direction: column;
    gap: 28px;
  }

  .feed-sentinel {
    height: 1px;
  }
</style>
