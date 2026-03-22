<script lang="ts">
  import { onMount } from 'svelte';
  import type { Post } from '$lib/api/types.js';
  import { getBookmarks } from '$lib/api/timelines.js';
  import FeedList from '$lib/components/feed/FeedList.svelte';

  let posts: Post[] = $state([]);
  let loading = $state(true);
  let hasMore = $state(true);
  let cursor: string | null = $state(null);

  async function loadBookmarks(reset = false) {
    if (reset) {
      posts = [];
      cursor = null;
      hasMore = true;
      loading = true;
    }

    try {
      const params: { cursor?: string } = {};
      if (cursor) params.cursor = cursor;

      const result = await getBookmarks(params);
      if (reset) {
        posts = result.data;
      } else {
        posts = [...posts, ...result.data];
      }
      cursor = result.next_cursor;
      hasMore = !!result.next_cursor;
    } catch {
      // Handle error silently
    } finally {
      loading = false;
    }
  }

  onMount(() => {
    loadBookmarks(true);
  });
</script>

<svelte:head>
  <title>Bookmarks - HybridSocial</title>
</svelte:head>

<div class="bookmarks-page">
  <h1 class="bookmarks-title">Bookmarks</h1>

  <FeedList
    {posts}
    {loading}
    {hasMore}
    onloadmore={() => loadBookmarks(false)}
    emptyMessage="You haven't bookmarked any posts yet"
  />
</div>

<style>
  .bookmarks-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .bookmarks-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
  }
</style>
