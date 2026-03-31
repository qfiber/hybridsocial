<script lang="ts">
  import { onMount } from 'svelte';
  import type { Post } from '$lib/api/types.js';
  import { getHomeTimeline } from '$lib/api/timelines.js';
  import FeedList from '$lib/components/feed/FeedList.svelte';
  import FeedToggle, { type FeedTab } from '$lib/components/feed/FeedToggle.svelte';
  import {
    queuedCount,
    flushQueue,
    setAtTop,
    connectTimelineStream,
    disconnectTimelineStream,
    maybeTruncate,
  } from '$lib/stores/timeline-stream.js';

  let posts: Post[] = $state([]);
  let loading = $state(true);
  let hasMore = $state(true);
  let cursor: string | null = $state(null);
  let feedType: FeedTab = $state('latest');

  async function loadTimeline(reset = false) {
    if (reset) {
      posts = [];
      cursor = null;
      hasMore = true;
      loading = true;
    }

    try {
      const params: Record<string, string> = {};
      if (cursor) params.max_id = cursor;
      if (feedType === 'foryou') params.algorithm = 'true';
      if (feedType === 'top') params.algorithm = 'trending';

      const result = await getHomeTimeline(params);
      const items: Post[] = Array.isArray(result) ? result : (result as any).data || [];
      if (reset) {
        posts = items;
      } else {
        posts = [...posts, ...items];
      }
      cursor = items.length > 0 ? items[items.length - 1]?.id : null;
      hasMore = items.length >= 20;
    } catch {
      // Handle error silently
    } finally {
      loading = false;
    }
  }

  function handleFeedChange(tab: FeedTab) {
    feedType = tab;
    loadTimeline(true);
  }

  function mergeQueuedPosts() {
    const queued = flushQueue();
    if (queued.length > 0) {
      // Deduplicate
      const existingIds = new Set(posts.map(p => p.id));
      const newPosts = queued.filter(p => !existingIds.has(p.id));
      posts = maybeTruncate([...newPosts, ...posts]);
    }
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function handleScroll() {
    const atTop = window.scrollY < 50;
    setAtTop(atTop);
  }

  onMount(() => {
    loadTimeline(true);

    // Connect streaming (auth via httpOnly cookie)
    const apiBase = import.meta.env.VITE_API_URL || '';
    connectTimelineStream(apiBase);

    // Listen for real-time updates when at top
    function handleTimelineUpdate(e: Event) {
      const post = (e as CustomEvent<Post>).detail;
      if (post && !posts.some(p => p.id === post.id)) {
        posts = maybeTruncate([post, ...posts]);
      }
    }

    // Listen for status edits
    function handleStatusUpdate(e: Event) {
      const updated = (e as CustomEvent<Post>).detail;
      if (updated) {
        posts = posts.map(p => p.id === updated.id ? updated : p);
      }
    }

    // Listen for new posts from the composer
    function handleNewPost(e: Event) {
      const newPost = (e as CustomEvent).detail;
      if (newPost && !newPost.parent_id) {
        // Only add top-level posts to the feed (not replies)
        posts = [newPost, ...posts];
      }
    }

    // Replace optimistic post with real server response
    function handlePostReplace(e: Event) {
      const { oldId, post } = (e as CustomEvent).detail;
      if (oldId && post) {
        posts = posts.map(p => p.id === oldId ? post : p);
      }
    }

    window.addEventListener('scroll', handleScroll, { passive: true });
    window.addEventListener('timeline-update', handleTimelineUpdate);
    window.addEventListener('timeline-status-update', handleStatusUpdate);
    window.addEventListener('new-post', handleNewPost);
    window.addEventListener('post-replace', handlePostReplace);

    return () => {
      disconnectTimelineStream();
      window.removeEventListener('scroll', handleScroll);
      window.removeEventListener('timeline-update', handleTimelineUpdate);
      window.removeEventListener('timeline-status-update', handleStatusUpdate);
      window.removeEventListener('new-post', handleNewPost);
      window.removeEventListener('post-replace', handlePostReplace);
    };
  });
</script>

<svelte:head>
  <title>Home - HybridSocial</title>
</svelte:head>

<div class="home-page">
  <FeedToggle active={feedType} onchange={handleFeedChange} />

  {#if $queuedCount > 0}
    <button type="button" class="new-posts-banner" onclick={mergeQueuedPosts}>
      <span class="material-symbols-outlined banner-icon">arrow_upward</span>
      {$queuedCount} new {$queuedCount === 1 ? 'post' : 'posts'}
    </button>
  {/if}

  <FeedList
    {posts}
    {loading}
    {hasMore}
    onloadmore={() => loadTimeline(false)}
    emptyMessage="Your timeline is empty. Follow some people to see their posts here."
  />
</div>

<style>
  .home-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .new-posts-banner {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    width: 100%;
    padding: 10px;
    background: var(--color-primary);
    color: white;
    border: none;
    border-radius: 12px;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 150ms ease;
    animation: banner-slide-in 0.3s ease;
  }

  .new-posts-banner:hover {
    opacity: 0.9;
  }

  .banner-icon {
    font-size: 18px;
  }

  @keyframes banner-slide-in {
    from {
      opacity: 0;
      transform: translateY(-8px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }
</style>
