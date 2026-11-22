<script lang="ts">
  import { onMount } from 'svelte';
  import { getBookmarks } from '$lib/api/timelines.js';
  import { addToast } from '$lib/stores/toast.js';
  import FeedList from '$lib/components/feed/FeedList.svelte';
  import { createEntityFeed } from '$lib/feed/entity-feed.svelte.js';
  import { instanceName } from '$lib/stores/instance.js';

  // Bookmarks paginate on a server `next_cursor` envelope.
  const feed = createEntityFeed(
    async (cursor) => {
      const result = await getBookmarks(cursor ? { cursor } : {});
      return { items: result.data, nextCursor: result.next_cursor };
    },
    20,
    // A failed load otherwise looks identical to an empty bookmark list
    // (FeedList shows "Nothing here yet"), so surface it.
    { onError: () => addToast('Could not load bookmarks', 'error') },
  );

  onMount(() => {
    feed.reset();
  });
</script>

<svelte:head>
  <title>Bookmarks - {$instanceName}</title>
</svelte:head>

<div class="bookmarks-page">
  <h1 class="sticky-section-head bookmarks-title">Bookmarks</h1>

  <FeedList
    posts={feed.posts}
    loading={feed.loading}
    hasMore={feed.hasMore}
    onloadmore={feed.loadMore}
    emptyMessage="You haven't bookmarked any posts yet"
    removeOnEvents={['bookmark-removed']}
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
