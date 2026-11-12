<script lang="ts">
  import { instanceName } from '$lib/stores/instance.js';
  import { page } from '$app/state';
  import type { Post, Identity, TrendingTag } from '$lib/api/types.js';
  import { search } from '$lib/api/search.js';
  import { api } from '$lib/api/client.js';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import DisplayName from '$lib/components/DisplayName.svelte';
  import FeedList from '$lib/components/feed/FeedList.svelte';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Skeleton from '$lib/components/ui/Skeleton.svelte';
  import TimelineFeed, {
    type TimelineTab,
  } from '$lib/components/feed/TimelineFeed.svelte';
  import FeedTabs from '$lib/components/feed/FeedTabs.svelte';
  import { exploreFeedCache } from '$lib/stores/explore-feed-cache.js';
  import { t } from '$lib/stores/i18n.js';

  // ── Public feeds (Local / Global / Trending) ─────────────────────────
  async function loadPublic(base: string, cursor: string | null): Promise<Post[]> {
    let endpoint = base;
    if (cursor) {
      endpoint += `${endpoint.includes('?') ? '&' : '?'}max_id=${encodeURIComponent(cursor)}`;
    }
    const items = await api.get<Post[]>(endpoint);
    return Array.isArray(items) ? items : [];
  }

  // Local tab shows only posts authored on this instance. Remote federated
  // authors (acct contains '@', or a foreign URL host) belong on Global.
  function isLocalPost(p: Post): boolean {
    const host = typeof window !== 'undefined' ? window.location.host : '';
    const acct = (p.account as any)?.acct ?? '';
    if (!acct.includes('@')) return true;
    const authorHost = (p.account as any)?.url ? new URL((p.account as any).url).host : host;
    return authorHost === host;
  }

  type TopTab = 'local' | 'global' | 'trending';
  const isTopTab = (id: string | null): id is TopTab =>
    id === 'local' || id === 'global' || id === 'trending';

  const TOP_TAB_KEY = 'hs-explore-tab';

  // A link's choice, then the visitor's last tab, then Trending, the best first
  // impression for someone who doesn't follow anyone yet. Read up front rather
  // than in onMount, so the feed never starts loading the wrong tab.
  function initialTab(): TopTab {
    const linked = page.url.searchParams.get('tab');
    if (isTopTab(linked)) return linked;
    try {
      const saved = localStorage.getItem(TOP_TAB_KEY);
      if (isTopTab(saved)) return saved;
    } catch {
      /* storage unavailable */
    }
    return 'trending';
  }

  let topTab = $state<TopTab>(initialTab());

  function changeTopTab(id: string) {
    if (id === topTab || !isTopTab(id)) return;
    topTab = id;
    try {
      localStorage.setItem(TOP_TAB_KEY, id);
    } catch {
      /* storage unavailable — the choice just won't persist */
    }
  }

  // A link followed while already on this page (the sidebar's "See what's
  // trending"). Tracks the param, so it doesn't undo a later tab click.
  let lastLinkedTab = page.url.searchParams.get('tab');
  $effect(() => {
    const linked = page.url.searchParams.get('tab');
    if (linked === lastLinkedTab) return;
    lastLinkedTab = linked;
    if (isTopTab(linked)) changeTopTab(linked);
  });

  // Admin-tunable (`feed_collapse_author_runs_after`), 0 turns it off.
  let collapseAfter = $derived(
    Number(
      (page.data as { instance?: { configuration?: { feeds?: { collapse_author_runs_after?: number } } } })
        .instance?.configuration?.feeds?.collapse_author_runs_after ?? 0,
    ),
  );

  let exploreTabs = $derived<TimelineTab[]>([
    {
      id: 'local',
      label: $t('explore.tab_local'),
      icon: 'home',
      load: (c) => loadPublic('/api/v1/timelines/public?local=true', c),
      stream: {
        kind: 'public',
        filter: (p) => !(((p.account as any)?.acct ?? '') as string).includes('@'),
      },
      accepts: isLocalPost,
      emptyMessage: $t('explore.empty_local'),
      collapseAuthorRunsAfter: collapseAfter,
    },
    {
      id: 'global',
      label: $t('explore.tab_global'),
      icon: 'public',
      load: (c) => loadPublic('/api/v1/timelines/global', c),
      stream: { kind: 'public' },
      emptyMessage: $t('explore.empty_global'),
    },
    {
      // A ranked feed: neither live posts nor the composer's optimistic post
      // belong at the top of it.
      id: 'trending',
      label: $t('explore.tab_trending'),
      icon: 'trending_up',
      load: (c) => loadPublic('/api/v1/timelines/trending', c),
      stream: null,
      accepts: () => false,
      emptyMessage: $t('explore.trending_empty'),
      emptyAction: { label: $t('explore.see_latest'), onclick: () => changeTopTab('local') },
    },
  ]);

  let feedTab = $derived(exploreTabs.find((tab) => tab.id === topTab) ?? exploreTabs[0]);


  // ── Search ───────────────────────────────────────────────────────────
  let query = $state('');
  let searchTab = $state('posts');
  let searching = $state(false);
  let hasSearched = $state(false);

  let searchPosts: Post[] = $state([]);
  let searchAccounts: Identity[] = $state([]);
  let searchHashtags: TrendingTag[] = $state([]);

  const searchTabs = [
    { id: 'posts', label: 'Posts' },
    { id: 'accounts', label: 'Accounts' },
    { id: 'hashtags', label: 'Hashtags' },
  ];

  async function handleSearch() {
    const q = query.trim();
    if (!q) {
      hasSearched = false;
      return;
    }

    searching = true;
    hasSearched = true;
    try {
      const results = await search(q, { resolve: true });
      searchPosts = results.posts || (results as any).statuses || [];
      searchAccounts = results.accounts || [];
      searchHashtags = results.hashtags || [];

      if (searchAccounts.length > 0 && searchPosts.length === 0) {
        searchTab = 'accounts';
      } else if (
        searchHashtags.length > 0 &&
        searchPosts.length === 0 &&
        searchAccounts.length === 0
      ) {
        searchTab = 'hashtags';
      } else {
        searchTab = 'posts';
      }
    } catch {
      // Handle silently
    } finally {
      searching = false;
    }
  }

  // React to URL query param changes (the search box lives in the header).
  let lastUrlQuery = '';
  $effect(() => {
    const urlQuery = page.url.searchParams.get('q') || '';
    if (urlQuery && urlQuery !== lastUrlQuery) {
      lastUrlQuery = urlQuery;
      query = urlQuery;
      handleSearch();
    }
  });

  // Height of the sticky Local/Global/Trending bar, so the feed's "new posts"
  // pill sits below it instead of covering it (#256).
  let topTabsHeight = $state(0);
</script>

<svelte:head>
  <title>Explore - {$instanceName}</title>
</svelte:head>

<div class="explore-page">
  {#if hasSearched}
    <Tabs tabs={searchTabs} bind:active={searchTab}>
      {#if searching}
        <div class="search-loading">
          <div class="search-spinner">
            <svg class="spinner-svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5">
              <circle cx="12" cy="12" r="10" stroke-opacity="0.2" />
              <path d="M12 2a10 10 0 0 1 10 10" stroke-linecap="round" />
            </svg>
            <span>Searching...</span>
          </div>
          <div class="search-skeleton">
            <Skeleton width="100%" height="56px" />
            <Skeleton width="100%" height="56px" />
            <Skeleton width="100%" height="56px" />
          </div>
        </div>
      {:else if searchTab === 'posts'}
        {#if searchPosts.length === 0}
          <div class="empty-results">
            <p>No posts found for "{query}"</p>
          </div>
        {:else}
          <FeedList posts={searchPosts} loading={false} hasMore={false} filterContext="public" />
        {/if}
      {:else if searchTab === 'accounts'}
        {#if searchAccounts.length === 0}
          <div class="empty-results">
            <p>No accounts found for "{query}"</p>
          </div>
        {:else}
          <div class="accounts-list">
            {#each searchAccounts as account (account.id)}
              <a href="/{account.acct || account.handle}" class="account-item">
                <Avatar src={account.avatar_url} name={account.display_name || account.acct || account.handle} size="md" />
                <div class="account-info">
                  <span class="account-name"><DisplayName name={account.display_name || account.acct || account.handle} emojis={account.emojis} /></span>
                  <span class="account-handle">@{account.acct || account.handle}</span>
                  {#if account.bio}
                    <p class="account-bio">{@html account.bio}</p>
                  {/if}
                </div>
              </a>
            {/each}
          </div>
        {/if}
      {:else if searchTab === 'hashtags'}
        {#if searchHashtags.length === 0}
          <div class="empty-results">
            <p>No hashtags found for "{query}"</p>
          </div>
        {:else}
          <div class="hashtags-list">
            {#each searchHashtags as tag (tag.name)}
              <a href="/tags/{tag.name}" class="hashtag-item">
                <span class="hashtag-name">#{tag.name}</span>
                {#if (tag.history || []).length > 0}
                  <span class="hashtag-count">{(tag.history || [])[0].uses} posts today</span>
                {/if}
              </a>
            {/each}
          </div>
        {/if}
      {/if}
    </Tabs>
  {:else}
    <div class="explore-toptabs" bind:offsetHeight={topTabsHeight}>
      <FeedTabs tabs={exploreTabs} active={topTab} onchange={changeTopTab} />
    </div>
    <!-- One feed at a time (its own tab bar hidden since a single tab is
         passed); keyed so switching tabs remounts with the right feed. -->
    {#key topTab}
      <TimelineFeed
        tabs={[feedTab]}
        filterContext="public"
        cache={exploreFeedCache(topTab)}
        bannerOffset={topTabsHeight}
      />
    {/key}
  {/if}
</div>

<style>
  .explore-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  /* Pin the Local/Global/Trending switcher under the header, like Home's
     Latest/For You/Top bar, so switching feeds deep in a timeline needs no
     scroll back up. (It used to hide on scroll-down; with the sort chips
     gone it's the only bar here, so it stays put, matching Home.) */
  .explore-toptabs {
    position: sticky;
    inset-block-start: var(--header-height);
    z-index: 21;
    background: var(--color-surface-base, var(--color-bg));
    padding-block: var(--space-2);
    /* Absorb the page's flex gap so the pinned bar has no seam above it. */
    margin-block-start: calc(-1 * var(--space-2));
  }

  .search-loading {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .search-spinner {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    padding: var(--space-4);
    font-size: var(--text-sm);
    color: var(--color-primary);
    font-weight: 500;
  }

  .spinner-svg {
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .search-skeleton {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    opacity: 0.5;
  }

  .empty-results {
    text-align: center;
    padding: var(--space-12);
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
  }

  /* Account results */
  .accounts-list {
    display: flex;
    flex-direction: column;
  }

  .account-item {
    display: flex;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border-radius: var(--radius-lg);
    text-decoration: none;
    transition: background var(--transition-fast);
  }

  .account-item:hover {
    background: var(--color-surface);
    text-decoration: none;
  }

  .account-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .account-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .account-handle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .account-bio {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-start: var(--space-1);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  /* Hashtag results */
  .hashtags-list {
    display: flex;
    flex-direction: column;
  }

  .hashtag-item {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: var(--space-3) var(--space-4);
    border-radius: var(--radius-lg);
    text-decoration: none;
    transition: background var(--transition-fast);
  }

  .hashtag-item:hover {
    background: var(--color-surface);
    text-decoration: none;
  }

  .hashtag-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-primary);
  }

  .hashtag-count {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }
</style>
