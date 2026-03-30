<script lang="ts">
  import { onMount } from 'svelte';
  import type { Post, FeedEntry, BoostEntry } from '$lib/api/types.js';
  import PostCard from '$lib/components/post/PostCard.svelte';
  import SkeletonPost from './SkeletonPost.svelte';

  function isBoostEntry(entry: FeedEntry): entry is BoostEntry {
    return entry.type === 'boost';
  }

  let {
    posts = [],
    loading = false,
    hasMore = true,
    compact = false,
    emptyMessage = 'No posts yet',
    onloadmore,
  }: {
    posts?: FeedEntry[];
    loading?: boolean;
    hasMore?: boolean;
    compact?: boolean;
    emptyMessage?: string;
    onloadmore?: () => void;
  } = $props();

  let sentinelEl: HTMLDivElement | undefined = $state();
  let newPostsCount = $state(0);
  let showStagger = $state(true);
  let newIds = $state(new Set<string>());
  let deletingIds = $state(new Set<string>());
  let hiddenIds = $state(new Set<string>());

  let visiblePosts: FeedEntry[] = $derived(posts.filter(p => !hiddenIds.has(p.id)));

  // Non-reactive tracker — avoids $effect infinite loop
  let _knownIds = new Set<string>();

  $effect(() => {
    const currentPosts = posts;
    const fresh = new Set<string>();
    for (const p of currentPosts) {
      if (!_knownIds.has(p.id)) {
        fresh.add(p.id);
      }
    }

    // If most posts are new (tab switch / full reload), re-trigger stagger
    const isFullReplace = fresh.size > 0 && fresh.size >= currentPosts.length * 0.8;

    _knownIds = new Set(currentPosts.map(p => p.id));

    if (isFullReplace) {
      showStagger = true;
      setTimeout(() => { showStagger = false; }, 800);
    } else if (fresh.size > 0 && !showStagger) {
      newIds = fresh;
      setTimeout(() => { newIds = new Set(); }, 500);
    }
  });

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

    function handlePostDeleted(e: Event) {
      const detail = (e as CustomEvent).detail;
      const id = detail?.id;
      if (!id || !posts.some(p => p.id === id)) return;

      // Animate out, then hide permanently
      deletingIds = new Set([...deletingIds, id]);

      setTimeout(() => {
        hiddenIds = new Set([...hiddenIds, id]);
        deletingIds = new Set([...deletingIds].filter(x => x !== id));
      }, 400);
    }

    window.addEventListener('feed-new-post', handleNewPost);
    window.addEventListener('post-deleted', handlePostDeleted);
    return () => {
      window.removeEventListener('feed-new-post', handleNewPost);
      window.removeEventListener('post-deleted', handlePostDeleted);
    };
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

  {#if visiblePosts.length === 0 && !loading}
    <div class="feed-empty">
      <p class="feed-empty-text">{emptyMessage}</p>
    </div>
  {/if}

  {#each visiblePosts as entry, i (entry.id)}
    {@const boost = isBoostEntry(entry) ? entry : null}
    {@const post = boost ? boost.post : entry as Post}
    {#if post && post.content !== undefined}
      <div
        class="feed-item"
        style={showStagger ? `animation-delay: ${i * 60}ms` : ''}
        class:stagger={showStagger}
        class:feed-item-new={newIds.has(entry.id)}
        class:feed-item-deleting={deletingIds.has(entry.id)}
      >
        {#if boost}
          <div class="boost-label">
            <span class="material-symbols-outlined boost-icon">cached</span>
            <span>{boost.account?.display_name || boost.account?.handle || 'Someone'} boosted</span>
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

  /* New post fade-in from top */
  .feed-item-new {
    animation: new-post-enter 0.4s ease both;
  }

  @keyframes new-post-enter {
    from {
      opacity: 0;
      transform: translateY(-20px) scale(0.98);
    }
    to {
      opacity: 1;
      transform: translateY(0) scale(1);
    }
  }

  /* Dissolve out animation for deleted posts */
  .feed-item-deleting {
    animation: post-dissolve 0.4s ease forwards;
    pointer-events: none;
  }

  @keyframes post-dissolve {
    0% {
      opacity: 1;
      transform: scale(1);
      filter: blur(0);
      max-height: 600px;
    }
    40% {
      opacity: 0.5;
      transform: scale(0.97);
      filter: blur(1px);
    }
    70% {
      opacity: 0;
      transform: scale(0.94);
      filter: blur(3px);
      max-height: 600px;
    }
    100% {
      opacity: 0;
      transform: scale(0.9);
      filter: blur(4px);
      max-height: 0;
      margin: 0;
      padding: 0;
      overflow: hidden;
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
