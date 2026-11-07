<script lang="ts">
  import { instanceName } from '$lib/stores/instance.js';
  import type { Post } from '$lib/api/types.js';
  import { getHomeTimeline } from '$lib/api/timelines.js';
  import StoriesCarousel from '$lib/components/stories/StoriesCarousel.svelte';
  import TimelineFeed, {
    type TimelineTab,
    type TimelineCache,
  } from '$lib/components/feed/TimelineFeed.svelte';
  import { readHomeFeed, writeHomeFeed } from '$lib/stores/home-feed-cache.js';

  // Session cache → scroll restoration on back-nav from a post detail.
  const cache: TimelineCache = { read: readHomeFeed, write: writeHomeFeed };

  const EMPTY = 'Your timeline is empty. Follow some people to see their posts here.';

  async function loadHome(cursor: string | null, algorithm?: string): Promise<Post[]> {
    const params: Record<string, string> = {};
    if (cursor) params.max_id = cursor;
    if (algorithm) params.algorithm = algorithm;
    const result = await getHomeTimeline(params);
    return Array.isArray(result) ? result : ((result as any).data ?? []);
  }

  // Latest and For You share the personal 'home' stream: a new post from
  // someone you follow prepends to either.
  const tabs: TimelineTab[] = [
    {
      id: 'latest',
      label: 'Latest',
      load: (c) => loadHome(c),
      stream: { kind: 'home' },
      emptyMessage: EMPTY,
    },
    {
      id: 'foryou',
      label: 'For You',
      load: (c) => loadHome(c, 'true'),
      stream: { kind: 'home' },
      emptyMessage: EMPTY,
    },
    {
      id: 'top',
      label: 'Top',
      load: (c) => loadHome(c, 'trending'),
      // The precomputed Trending feed, like Explore's tab: neither live posts
      // nor the composer's optimistic post belong at the top of a ranking.
      stream: null,
      accepts: () => false,
      emptyMessage: EMPTY,
    },
  ];
</script>

<svelte:head>
  <title>Home - {$instanceName}</title>
</svelte:head>

<div class="home-page">
  <StoriesCarousel />
  <TimelineFeed {tabs} {cache} filterContext="home" />
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
