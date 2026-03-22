<script lang="ts">
  import { onMount } from 'svelte';
  import type { Post, Identity, TrendingTag } from '$lib/api/types.js';
  import { search } from '$lib/api/search.js';
  import { getTrending } from '$lib/api/instance.js';
  import { getPublicTimeline } from '$lib/api/timelines.js';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import FeedList from '$lib/components/feed/FeedList.svelte';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Skeleton from '$lib/components/ui/Skeleton.svelte';


  let query = $state('');
  let activeTab = $state('posts');
  let searching = $state(false);
  let hasSearched = $state(false);

  // Search results
  let searchPosts: Post[] = $state([]);
  let searchAccounts: Identity[] = $state([]);
  let searchHashtags: TrendingTag[] = $state([]);

  // Trending / public timeline
  let trendingTags: TrendingTag[] = $state([]);
  let publicPosts: Post[] = $state([]);
  let publicLoading = $state(true);
  let publicHasMore = $state(true);
  let publicCursor: string | null = $state(null);
  let trendingLoading = $state(true);

  const tabs = [
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
      searchPosts = results.statuses || results.posts || [];
      searchAccounts = results.accounts || [];
      searchHashtags = results.hashtags || [];
    } catch {
      // Handle silently
    } finally {
      searching = false;
    }
  }

  function handleSearchKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') {
      handleSearch();
    }
  }

  async function loadPublicTimeline(reset = false) {
    if (reset) {
      publicPosts = [];
      publicCursor = null;
      publicHasMore = true;
    }
    publicLoading = true;
    try {
      const params: { cursor?: string } = {};
      if (publicCursor) params.cursor = publicCursor;
      const result = await getPublicTimeline(params);
      if (reset) {
        publicPosts = result.data;
      } else {
        publicPosts = [...publicPosts, ...result.data];
      }
      publicCursor = result.next_cursor;
      publicHasMore = !!result.next_cursor;
    } catch {
      // Handle silently
    } finally {
      publicLoading = false;
    }
  }

  async function loadTrending() {
    trendingLoading = true;
    try {
      trendingTags = await getTrending();
    } catch {
      // Handle silently
    } finally {
      trendingLoading = false;
    }
  }

  onMount(() => {
    loadTrending();
    loadPublicTimeline(true);
  });

  function clearSearch() {
    query = '';
    hasSearched = false;
  }
</script>

<svelte:head>
  <title>Explore - HybridSocial</title>
</svelte:head>

<div class="explore-page">
  <div class="search-bar">
    <svg class="search-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
      <circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>
    </svg>
    <input
      type="search"
      class="search-input"
      placeholder="Search posts, people, and hashtags..."
      bind:value={query}
      onkeydown={handleSearchKeydown}
    />
    {#if query}
      <button class="search-clear" type="button" onclick={clearSearch} aria-label="Clear search">
        <svg width="16" height="16" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2">
          <line x1="4" y1="4" x2="16" y2="16" /><line x1="16" y1="4" x2="4" y2="16" />
        </svg>
      </button>
    {/if}
  </div>

  {#if hasSearched}
    <Tabs {tabs} bind:active={activeTab}>
      {#if searching}
        <div class="search-loading">
          <Skeleton width="100%" height="60px" />
          <Skeleton width="100%" height="60px" />
          <Skeleton width="100%" height="60px" />
        </div>
      {:else if activeTab === 'posts'}
        {#if searchPosts.length === 0}
          <div class="empty-results">
            <p>No posts found for "{query}"</p>
          </div>
        {:else}
          <FeedList posts={searchPosts} loading={false} hasMore={false} />
        {/if}
      {:else if activeTab === 'accounts'}
        {#if searchAccounts.length === 0}
          <div class="empty-results">
            <p>No accounts found for "{query}"</p>
          </div>
        {:else}
          <div class="accounts-list">
            {#each searchAccounts as account (account.id)}
              <a href="/{account.handle}" class="account-item">
                <Avatar src={account.avatar_url} name={account.display_name || account.handle} size="md" />
                <div class="account-info">
                  <span class="account-name">{account.display_name || account.handle}</span>
                  <span class="account-handle">@{account.handle}</span>
                  {#if account.bio}
                    <p class="account-bio">{account.bio}</p>
                  {/if}
                </div>
              </a>
            {/each}
          </div>
        {/if}
      {:else if activeTab === 'hashtags'}
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
    <!-- Trending + Public Timeline -->
    {#if trendingTags.length > 0}
      <div class="trending-section">
        <h2 class="section-heading">Trending</h2>
        <div class="trending-list">
          {#each trendingTags.slice(0, 5) as tag (tag.name)}
            <a href="/tags/{tag.name}" class="trending-item">
              <span class="trending-name">#{tag.name}</span>
              {#if (tag.history || []).length > 0}
                <span class="trending-stat">{(tag.history || [])[0].uses} posts &middot; {(tag.history || [])[0].accounts} people</span>
              {/if}
            </a>
          {/each}
        </div>
      </div>
    {:else if trendingLoading}
      <div class="trending-section">
        <h2 class="section-heading">Trending</h2>
        <div class="trending-list">
          {#each Array(3) as _}
            <div class="trending-skeleton">
              <Skeleton width="120px" height="16px" />
              <Skeleton width="80px" height="12px" />
            </div>
          {/each}
        </div>
      </div>
    {/if}

    <div class="public-section">
      <h2 class="section-heading">Public Timeline</h2>
      <FeedList
        posts={publicPosts}
        loading={publicLoading}
        hasMore={publicHasMore}
        onloadmore={() => loadPublicTimeline(false)}
        emptyMessage="No public posts yet"
      />
    </div>
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

  .search-bar {
    position: relative;
    display: flex;
    align-items: center;
  }

  .search-icon {
    position: absolute;
    inset-inline-start: var(--space-3);
    color: var(--color-text-tertiary);
    pointer-events: none;
  }

  .search-input {
    display: block;
    width: 100%;
    padding: var(--space-3) var(--space-10);
    padding-inline-start: calc(var(--space-3) + 24px);
    font-size: var(--text-sm);
    color: var(--color-text);
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
  }

  .search-input:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px var(--color-primary-soft);
  }

  .search-input::placeholder {
    color: var(--color-text-tertiary);
  }

  .search-clear {
    position: absolute;
    inset-inline-end: var(--space-3);
    display: flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    border: none;
    background: none;
    color: var(--color-text-tertiary);
    cursor: pointer;
    border-radius: var(--radius-full);
    padding: 0;
  }

  .search-clear:hover {
    color: var(--color-text);
    background: var(--color-surface);
  }

  .search-loading {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
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

  /* Trending section */
  .trending-section {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-4);
  }

  .section-heading {
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-3);
  }

  .trending-list {
    display: flex;
    flex-direction: column;
  }

  .trending-item {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    text-decoration: none;
    transition: background var(--transition-fast);
  }

  .trending-item:hover {
    background: var(--color-surface);
    text-decoration: none;
  }

  .trending-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-primary);
  }

  .trending-stat {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .trending-skeleton {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
    padding: var(--space-2) var(--space-3);
  }

  .public-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }
</style>
