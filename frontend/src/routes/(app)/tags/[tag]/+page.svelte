<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import type { Post } from '$lib/api/types.js';
  import { api } from '$lib/api/client.js';
  import { getHashtagTimeline } from '$lib/api/timelines.js';
  import FeedList from '$lib/components/feed/FeedList.svelte';

  let tag = $derived(page.params.tag!);
  let posts: Post[] = $state([]);
  let loading = $state(true);
  let hasMore = $state(true);
  let cursor: string | null = $state(null);
  let isFollowing = $state(false);
  let followLoading = $state(false);

  async function loadTimeline(reset = false) {
    if (reset) { posts = []; cursor = null; hasMore = true; }
    loading = true;
    try {
      const params: Record<string, string> = {};
      if (cursor) params.cursor = cursor;
      const result = await getHashtagTimeline(tag, params);
      const items = Array.isArray(result) ? result : (result as any).data || [];
      posts = reset ? items : [...posts, ...items];
      cursor = items.length > 0 ? items[items.length - 1]?.id : null;
      hasMore = items.length >= 20;
    } catch { /* */ }
    finally { loading = false; }
  }

  async function checkFollowing() {
    try {
      const tags: { name: string }[] = await api.get('/api/v1/accounts/followed_tags');
      isFollowing = tags.some(t => t.name === tag.toLowerCase());
    } catch { /* */ }
  }

  async function toggleFollow() {
    followLoading = true;
    try {
      if (isFollowing) {
        await api.delete(`/api/v1/accounts/followed_tags/${encodeURIComponent(tag)}`);
        isFollowing = false;
      } else {
        await api.post('/api/v1/accounts/followed_tags', { name: tag });
        isFollowing = true;
      }
    } catch { /* */ }
    finally { followLoading = false; }
  }

  onMount(() => {
    loadTimeline(true);
    checkFollowing();
  });
</script>

<svelte:head>
  <title>#{tag} - HybridSocial</title>
</svelte:head>

<div class="tag-page">
  <div class="tag-header">
    <h1 class="tag-title">#{tag}</h1>
    <button
      type="button"
      class="follow-tag-btn"
      class:following={isFollowing}
      onclick={toggleFollow}
      disabled={followLoading}
    >
      {#if isFollowing}
        <span class="material-symbols-outlined" style="font-size: 18px">check</span>
        Following
      {:else}
        <span class="material-symbols-outlined" style="font-size: 18px">add</span>
        Follow
      {/if}
    </button>
  </div>

  <FeedList
    {posts}
    {loading}
    {hasMore}
    onloadmore={() => loadTimeline(false)}
    emptyMessage="No posts with #{tag} yet."
  />
</div>

<style>
  .tag-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .tag-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .tag-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    color: var(--color-primary);
  }

  .follow-tag-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 8px 18px;
    border: 2px solid var(--color-primary);
    border-radius: 9999px;
    background: transparent;
    color: var(--color-primary);
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 150ms ease;
  }

  .follow-tag-btn:hover {
    background: var(--color-primary);
    color: white;
  }

  .follow-tag-btn.following {
    background: var(--color-primary);
    color: white;
  }

  .follow-tag-btn.following:hover {
    background: transparent;
    color: var(--color-primary);
  }

  .follow-tag-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>
