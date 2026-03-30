<script lang="ts">
  import { onMount } from 'svelte';
  import type { Post } from '$lib/api/types.js';
  import { api } from '$lib/api/client.js';
  import FeedList from '$lib/components/feed/FeedList.svelte';

  let posts: Post[] = $state([]);
  let loading = $state(true);
  let hasMore = $state(true);
  let cursor: string | null = $state(null);

  async function loadFavourites(reset = false) {
    if (reset) { posts = []; cursor = null; hasMore = true; }
    loading = true;
    try {
      const params: Record<string, string> = {};
      if (cursor) params.max_id = cursor;
      const items: Post[] = await api.get('/api/v1/accounts/favourites', params);
      const result = Array.isArray(items) ? items : [];
      posts = reset ? result : [...posts, ...result];
      cursor = result.length > 0 ? result[result.length - 1]?.id : null;
      hasMore = result.length >= 20;
    } catch { /* */ }
    finally { loading = false; }
  }

  onMount(() => loadFavourites(true));
</script>

<svelte:head>
  <title>Favourites - HybridSocial</title>
</svelte:head>

<div class="favourites-page">
  <h1 class="page-title">Favourites</h1>
  <FeedList
    {posts}
    {loading}
    {hasMore}
    onloadmore={() => loadFavourites(false)}
    emptyMessage="You haven't reacted to any posts yet."
  />
</div>

<style>
  .favourites-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }
  .page-title {
    font-size: var(--text-xl);
    font-weight: 700;
  }
</style>
