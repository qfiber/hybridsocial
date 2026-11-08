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
  import { t } from '$lib/stores/i18n.js';

  // Session cache → scroll restoration on back-nav from a post detail.
  const cache: TimelineCache = { read: readHomeFeed, write: writeHomeFeed };

  async function loadHome(cursor: string | null, algorithm?: string): Promise<Post[]> {
    const params: Record<string, string> = {};
    if (cursor) params.max_id = cursor;
    if (algorithm) params.algorithm = algorithm;
    const result = await getHomeTimeline(params);
    return Array.isArray(result) ? result : ((result as any).data ?? []);
  }

  // Latest and For You share the personal 'home' stream: a new post from
  // someone you follow prepends to either.
  // Derived so the labels re-resolve when the locale changes (as Explore does).
  let tabs = $derived<TimelineTab[]>([
    {
      id: 'latest',
      label: $t('home.tab_latest'),
      load: (c) => loadHome(c),
      stream: { kind: 'home' },
      emptyMessage: $t('home.empty'),
    },
    {
      id: 'foryou',
      label: $t('home.tab_foryou'),
      load: (c) => loadHome(c, 'true'),
      stream: { kind: 'home' },
      emptyMessage: $t('home.empty'),
    },
    {
      id: 'top',
      label: $t('home.tab_top'),
      load: (c) => loadHome(c, 'trending'),
      // The precomputed Trending feed, like Explore's tab: neither live posts
      // nor the composer's optimistic post belong at the top of a ranking.
      stream: null,
      accepts: () => false,
      emptyMessage: $t('home.empty'),
    },
  ]);
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
