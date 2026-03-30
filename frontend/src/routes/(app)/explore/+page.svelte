<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import type { Post, Identity, TrendingTag } from '$lib/api/types.js';
  import { search } from '$lib/api/search.js';
  import { getTrending } from '$lib/api/instance.js';
  import { getPublicTimeline } from '$lib/api/timelines.js';
  import { api } from '$lib/api/client.js';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import FeedList from '$lib/components/feed/FeedList.svelte';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Skeleton from '$lib/components/ui/Skeleton.svelte';

  type ExploreTab = 'local' | 'global' | 'trending';

  let query = $state('');
  let exploreTab = $state<ExploreTab>('local');
  let searchTab = $state('posts');
  let searching = $state(false);
  let hasSearched = $state(false);

  // Search results
  let searchPosts: Post[] = $state([]);
  let searchAccounts: Identity[] = $state([]);
  let searchHashtags: TrendingTag[] = $state([]);

  // Feed state per tab
  let feedPosts: Post[] = $state([]);
  let feedLoading = $state(true);
  let feedHasMore = $state(true);
  let feedCursor: string | null = $state(null);

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
      } else if (searchHashtags.length > 0 && searchPosts.length === 0 && searchAccounts.length === 0) {
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

  function handleSearchSubmit(e: Event) {
    e.preventDefault();
    handleSearch();
  }

  let searchDebounce: ReturnType<typeof setTimeout> | null = null;

  function handleSearchInput() {
    if (searchDebounce) clearTimeout(searchDebounce);
    const q = query.trim();
    if (!q) {
      hasSearched = false;
      return;
    }
    searchDebounce = setTimeout(handleSearch, 300);
  }

  async function loadFeed(reset = false) {
    if (reset) {
      feedPosts = [];
      feedCursor = null;
      feedHasMore = true;
    }
    feedLoading = true;
    try {
      const params: Record<string, string> = {};
      if (feedCursor) params.max_id = feedCursor;

      let endpoint: string;
      if (exploreTab === 'local') {
        endpoint = '/api/v1/timelines/public?local=true';
      } else if (exploreTab === 'global') {
        endpoint = '/api/v1/timelines/global';
      } else {
        endpoint = '/api/v1/timelines/public?algorithm=trending';
      }

      if (feedCursor) endpoint += (endpoint.includes('?') ? '&' : '?') + `max_id=${feedCursor}`;

      const items: Post[] = await api.get(endpoint);
      const result = Array.isArray(items) ? items : [];

      if (reset) {
        feedPosts = result;
      } else {
        feedPosts = [...feedPosts, ...result];
      }
      feedCursor = result.length > 0 ? result[result.length - 1]?.id : null;
      feedHasMore = result.length >= 20;
    } catch {
      // Handle silently
    } finally {
      feedLoading = false;
    }
  }

  function switchTab(tab: ExploreTab) {
    if (tab !== exploreTab) {
      exploreTab = tab;
      loadFeed(true);
    }
  }

  onMount(() => {
    loadFeed(true);
  });

  // React to URL query param changes
  let lastUrlQuery = '';

  $effect(() => {
    const urlQuery = page.url.searchParams.get('q') || '';
    if (urlQuery && urlQuery !== lastUrlQuery) {
      lastUrlQuery = urlQuery;
      query = urlQuery;
      handleSearch();
    }
  });

  function clearSearch() {
    query = '';
    hasSearched = false;
    searchPosts = [];
    searchAccounts = [];
    searchHashtags = [];
  }
</script>

<svelte:head>
  <title>Explore - HybridSocial</title>
</svelte:head>

<div class="explore-page">
  <form class="search-bar" onsubmit={handleSearchSubmit}>
    <svg class="search-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
      <circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>
    </svg>
    <input
      type="search"
      class="search-input"
      placeholder="Search posts, people, and hashtags..."
      bind:value={query}
      oninput={handleSearchInput}
    />
    {#if searching}
      <div class="search-bar-spinner">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5">
          <circle cx="12" cy="12" r="10" stroke-opacity="0.2" />
          <path d="M12 2a10 10 0 0 1 10 10" stroke-linecap="round" />
        </svg>
      </div>
    {:else if query}
      <button class="search-clear" type="button" onclick={clearSearch} aria-label="Clear search">
        <svg width="16" height="16" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2">
          <line x1="4" y1="4" x2="16" y2="16" /><line x1="16" y1="4" x2="4" y2="16" />
        </svg>
      </button>
    {/if}
  </form>

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
          <FeedList posts={searchPosts} loading={false} hasMore={false} />
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
                  <span class="account-name">{account.display_name || account.acct || account.handle}</span>
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
    <!-- Explore tabs: Local / Global / Trending -->
    <div class="explore-tabs" role="tablist" aria-label="Explore feeds">
      <button
        type="button"
        role="tab"
        class="explore-tab"
        class:explore-tab-active={exploreTab === 'local'}
        aria-selected={exploreTab === 'local'}
        onclick={() => switchTab('local')}
      >
        <span class="material-symbols-outlined tab-icon">home</span>
        Local
      </button>
      <button
        type="button"
        role="tab"
        class="explore-tab"
        class:explore-tab-active={exploreTab === 'global'}
        aria-selected={exploreTab === 'global'}
        onclick={() => switchTab('global')}
      >
        <span class="material-symbols-outlined tab-icon">public</span>
        Global
      </button>
      <button
        type="button"
        role="tab"
        class="explore-tab"
        class:explore-tab-active={exploreTab === 'trending'}
        aria-selected={exploreTab === 'trending'}
        onclick={() => switchTab('trending')}
      >
        <span class="material-symbols-outlined tab-icon">trending_up</span>
        Trending
      </button>
    </div>

    <FeedList
      posts={feedPosts}
      loading={feedLoading}
      hasMore={feedHasMore}
      onloadmore={() => loadFeed(false)}
      emptyMessage={exploreTab === 'local' ? 'No local posts yet' : exploreTab === 'global' ? 'No posts from the fediverse yet' : 'Nothing trending right now'}
    />
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

  .search-bar-spinner {
    position: absolute;
    inset-inline-end: var(--space-3);
    display: flex;
    align-items: center;
    justify-content: center;
    animation: spin 0.8s linear infinite;
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

  /* Explore tabs */
  .explore-tabs {
    display: flex;
    gap: 2px;
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: 14px;
    padding: 3px;
  }

  .explore-tab {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    padding: 8px 12px;
    background: transparent;
    border: none;
    border-radius: 11px;
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: all 150ms ease;
  }

  .explore-tab:hover {
    color: var(--color-text);
    background: var(--color-surface);
  }

  .explore-tab-active {
    background: var(--color-primary);
    color: var(--color-on-primary);
  }

  .explore-tab-active:hover {
    background: var(--color-primary);
    color: var(--color-on-primary);
  }

  .tab-icon {
    font-size: 18px;
  }
</style>
