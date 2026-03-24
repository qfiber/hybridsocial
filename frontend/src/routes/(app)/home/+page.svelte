<script lang="ts">
  import { onMount } from 'svelte';
  import type { Post } from '$lib/api/types.js';
  import { getHomeTimeline } from '$lib/api/timelines.js';
  import FeedList from '$lib/components/feed/FeedList.svelte';
  import FeedToggle from '$lib/components/feed/FeedToggle.svelte';
  import PostComposer from '$lib/components/post/PostComposer.svelte';

  let posts: Post[] = $state([]);
  let loading = $state(true);
  let hasMore = $state(true);
  let cursor: string | null = $state(null);
  let feedType: 'latest' | 'foryou' = $state('latest');

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

      const result = await getHomeTimeline(params);
      // Backend returns array directly, not paginated response
      const items: Post[] = Array.isArray(result) ? result : (result as any).data || [];
      if (reset) {
        posts = items;
      } else {
        posts = [...posts, ...items];
      }
      // Use last item ID as cursor
      cursor = items.length > 0 ? items[items.length - 1]?.id : null;
      hasMore = items.length >= 20;
    } catch {
      // Handle error silently
    } finally {
      loading = false;
    }
  }

  function handleFeedChange(tab: 'latest' | 'foryou') {
    feedType = tab;
    loadTimeline(true);
  }

  onMount(() => {
    loadTimeline(true);

    // Listen for feed refresh events from SSE
    function handleRefresh() {
      loadTimeline(true);
    }

    // Listen for new posts from the composer
    function handleNewPost(e: Event) {
      const post = (e as CustomEvent).detail;
      if (post) {
        posts = [post, ...posts];
      }
    }

    // Listen for deleted posts
    function handlePostDeleted(e: Event) {
      const { id } = (e as CustomEvent).detail;
      if (id) {
        posts = posts.filter(p => p.id !== id);
      }
    }

    window.addEventListener('feed-refresh', handleRefresh);
    window.addEventListener('new-post', handleNewPost);
    window.addEventListener('post-deleted', handlePostDeleted);
    return () => {
      window.removeEventListener('feed-refresh', handleRefresh);
      window.removeEventListener('new-post', handleNewPost);
      window.removeEventListener('post-deleted', handlePostDeleted);
    };
  });
</script>

<svelte:head>
  <title>Home - HybridSocial</title>
</svelte:head>

<div class="home-page">
  <FeedToggle active={feedType} onchange={handleFeedChange} />

  <PostComposer />

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
</style>
