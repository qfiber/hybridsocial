<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import { getPage } from '$lib/api/pages.js';
  import { api } from '$lib/api/client.js';
  import type { Post } from '$lib/api/types.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import FeedList from '$lib/components/feed/FeedList.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let pageId = $state('');
  let pageData: any = $state(null);
  let loading = $state(true);
  let error = $state('');
  let activeTab = $state('posts');
  let posts: Post[] = $state([]);
  let postsLoading = $state(false);
  let isFollowing = $state(false);
  let followLoading = $state(false);

  const tabs = [
    { id: 'posts', label: 'Posts' },
    { id: 'about', label: 'About' },
  ];

  const unsub = page.subscribe(($page) => {
    pageId = $page.params.id;
  });

  async function loadPage() {
    loading = true;
    error = '';
    try {
      pageData = await getPage(pageId);
      isFollowing = pageData?.is_following ?? false;
      await loadPosts();
    } catch {
      error = 'Failed to load page.';
    } finally {
      loading = false;
    }
  }

  async function loadPosts() {
    if (!pageData) return;
    postsLoading = true;
    try {
      const result = await api.get<Post[]>(`/api/v1/pages/${pageId}/statuses`);
      posts = Array.isArray(result) ? result : [];
    } catch {
      posts = [];
    } finally {
      postsLoading = false;
    }
  }

  async function toggleFollow() {
    if (!pageData) return;
    followLoading = true;
    try {
      if (isFollowing) {
        await api.post(`/api/v1/pages/${pageId}/unfollow`);
        isFollowing = false;
      } else {
        await api.post(`/api/v1/pages/${pageId}/follow`);
        isFollowing = true;
      }
    } catch {
      // Error handled silently
    } finally {
      followLoading = false;
    }
  }

  onMount(() => {
    loadPage();
    return () => unsub();
  });
</script>

<svelte:head>
  <title>{pageData?.display_name || pageData?.name || 'Page'} - HybridSocial</title>
</svelte:head>

<div class="page-detail">
  {#if loading}
    <div class="loading-state">
      <Spinner />
    </div>
  {:else if error}
    <div class="error-state">
      <p>{error}</p>
      <button type="button" class="btn btn-outline" onclick={loadPage}>Retry</button>
    </div>
  {:else if pageData}
    <div class="page-profile">
      <!-- Cover image -->
      <div class="page-cover">
        {#if pageData.header_url || pageData.cover_url}
          <img src={pageData.header_url || pageData.cover_url} alt="" class="cover-img" />
        {:else}
          <div class="cover-gradient" aria-hidden="true"></div>
        {/if}
      </div>

      <div class="page-info-section">
        <div class="page-avatar-row">
          <div class="page-avatar-wrapper">
            <Avatar
              src={pageData.avatar_url || pageData.logo_url}
              name={pageData.display_name || pageData.name || pageData.handle}
              size="xl"
            />
          </div>
          <div class="page-actions">
            <button
              type="button"
              class="btn {isFollowing ? 'btn-outline' : 'btn-primary'}"
              onclick={toggleFollow}
              disabled={followLoading}
            >
              {isFollowing ? 'Following' : 'Follow'}
            </button>
          </div>
        </div>

        <div class="page-identity">
          <h1 class="page-name">{pageData.display_name || pageData.name || pageData.handle}</h1>
          <span class="page-handle">@{pageData.handle}</span>
          {#if pageData.category}
            <span class="page-category-badge">{pageData.category}</span>
          {/if}
        </div>

        {#if pageData.description || pageData.bio}
          <p class="page-description">{pageData.description || pageData.bio}</p>
        {/if}

        <!-- Business details -->
        <div class="business-details">
          {#if pageData.website}
            <div class="detail-item">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                <circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z"/>
              </svg>
              <a href={pageData.website} class="detail-link" target="_blank" rel="noopener">{pageData.website}</a>
            </div>
          {/if}
          {#if pageData.email}
            <div class="detail-item">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/><polyline points="22,6 12,13 2,6"/>
              </svg>
              <a href="mailto:{pageData.email}" class="detail-link">{pageData.email}</a>
            </div>
          {/if}
          {#if pageData.phone}
            <div class="detail-item">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                <path d="M22 16.92v3a2 2 0 01-2.18 2 19.79 19.79 0 01-8.63-3.07 19.5 19.5 0 01-6-6 19.79 19.79 0 01-3.07-8.67A2 2 0 014.11 2h3a2 2 0 012 1.72 12.84 12.84 0 00.7 2.81 2 2 0 01-.45 2.11L8.09 9.91a16 16 0 006 6l1.27-1.27a2 2 0 012.11-.45 12.84 12.84 0 002.81.7A2 2 0 0122 16.92z"/>
              </svg>
              <span>{pageData.phone}</span>
            </div>
          {/if}
          {#if pageData.address}
            <div class="detail-item">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z"/><circle cx="12" cy="10" r="3"/>
              </svg>
              <span>{pageData.address}</span>
            </div>
          {/if}
        </div>

        {#if pageData.social_links && pageData.social_links.length > 0}
          <div class="social-links">
            {#each pageData.social_links.slice(0, 4) as link (link.url || link)}
              <a href={link.url || link} class="social-link" target="_blank" rel="noopener">
                {link.label || link.url || link}
              </a>
            {/each}
          </div>
        {/if}

        {#if pageData.followers_count !== undefined}
          <div class="page-stats">
            <span class="stat-item">
              <strong>{pageData.followers_count}</strong>
              <span class="stat-label">Followers</span>
            </span>
          </div>
        {/if}
      </div>
    </div>

    <div class="page-feed-section">
      <Tabs {tabs} bind:active={activeTab}>
        {#if activeTab === 'posts'}
          <FeedList
            {posts}
            loading={postsLoading}
            hasMore={false}
            emptyMessage="No posts yet"
          />
        {:else if activeTab === 'about'}
          <div class="about-section">
            {#if pageData.description || pageData.bio}
              <div class="about-block">
                <h3 class="about-heading">About</h3>
                <p class="about-text">{pageData.description || pageData.bio}</p>
              </div>
            {/if}
            {#if pageData.category}
              <div class="about-block">
                <h3 class="about-heading">Category</h3>
                <p class="about-text">{pageData.category}</p>
              </div>
            {/if}
            {#if pageData.created_at}
              <div class="about-block">
                <h3 class="about-heading">Created</h3>
                <p class="about-text">{new Date(pageData.created_at).toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' })}</p>
              </div>
            {/if}
          </div>
        {/if}
      </Tabs>
    </div>
  {/if}
</div>

<style>
  .page-detail {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .loading-state {
    display: flex;
    justify-content: center;
    padding: var(--space-16);
  }

  .error-state {
    text-align: center;
    padding: var(--space-16) var(--space-4);
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-3);
    color: var(--color-text-secondary);
  }

  .page-profile {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow: hidden;
  }

  .page-cover {
    height: 180px;
    overflow: hidden;
  }

  .cover-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .cover-gradient {
    width: 100%;
    height: 100%;
    background: linear-gradient(var(--gradient-direction, 135deg), var(--gradient-start, var(--color-primary)), var(--gradient-end, #0d9488));
  }

  .page-info-section {
    padding: 0 var(--space-6) var(--space-6);
  }

  .page-avatar-row {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    margin-block-start: -40px;
  }

  .page-avatar-wrapper {
    border: 4px solid var(--color-surface-raised);
    border-radius: var(--radius-full);
    background: var(--color-surface-raised);
  }

  .page-actions {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding-block-start: var(--space-10);
  }

  .page-identity {
    margin-block-start: var(--space-3);
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .page-name {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
  }

  .page-handle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .page-category-badge {
    display: inline-block;
    align-self: flex-start;
    font-size: var(--text-xs);
    color: var(--color-primary);
    background: var(--color-primary-soft);
    padding: 2px var(--space-2);
    border-radius: var(--radius-sm);
    margin-block-start: var(--space-1);
  }

  .page-description {
    margin-block-start: var(--space-3);
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: var(--leading-relaxed);
    white-space: pre-wrap;
  }

  .business-details {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin-block-start: var(--space-3);
  }

  .detail-item {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .detail-link {
    color: var(--color-primary);
    text-decoration: none;
  }

  .detail-link:hover {
    text-decoration: underline;
  }

  .social-links {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2);
    margin-block-start: var(--space-3);
  }

  .social-link {
    font-size: var(--text-xs);
    color: var(--color-primary);
    background: var(--color-primary-soft);
    padding: var(--space-1) var(--space-2);
    border-radius: var(--radius-sm);
    text-decoration: none;
  }

  .social-link:hover {
    text-decoration: underline;
  }

  .page-stats {
    display: flex;
    gap: var(--space-5);
    margin-block-start: var(--space-3);
  }

  .stat-item {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    font-size: var(--text-sm);
    color: var(--color-text);
  }

  .stat-item strong {
    font-weight: 700;
  }

  .stat-label {
    color: var(--color-text-secondary);
  }

  .page-feed-section {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: 0 var(--space-4) var(--space-4);
  }

  /* About */
  .about-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .about-block {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .about-heading {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .about-text {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: var(--leading-relaxed);
    white-space: pre-wrap;
  }

  /* Buttons */
  .btn {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    padding: var(--space-2) var(--space-3);
    border: none;
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-weight: 500;
    cursor: pointer;
    transition: background var(--transition-fast);
  }

  .btn-primary {
    background: var(--color-primary);
    color: var(--color-text-inverse);
  }

  .btn-primary:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .btn-primary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .btn-outline {
    background: transparent;
    border: 1px solid var(--color-border);
    color: var(--color-text);
  }

  .btn-outline:hover {
    background: var(--color-surface);
  }

  @media (max-width: 480px) {
    .page-cover {
      height: 120px;
    }

    .page-info-section {
      padding: 0 var(--space-4) var(--space-4);
    }
  }
</style>
