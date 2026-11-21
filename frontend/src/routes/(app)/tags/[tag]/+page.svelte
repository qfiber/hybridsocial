<script lang="ts">
  import { instanceName } from '$lib/stores/instance.js';
  import { untrack } from 'svelte';
  import { page } from '$app/state';
  import { api } from '$lib/api/client.js';
  import { getHashtagTimeline } from '$lib/api/timelines.js';
  import FeedList from '$lib/components/feed/FeedList.svelte';
  import { createEntityFeed } from '$lib/feed/entity-feed.svelte.js';

  let tag = $derived(page.params.tag!);
  let isFollowing = $state(false);
  let followLoading = $state(false);
  let isMuted = $state(false);
  let muteLoading = $state(false);

  // The closure reads the current `tag` at call time, so a reset after a
  // /tags/a -> /tags/b navigation fetches the new tag.
  const feed = createEntityFeed(async (cursor) => {
    const result = await getHashtagTimeline(tag, cursor ? { cursor } : {});
    return Array.isArray(result) ? result : ((result as any).data ?? []);
  });

  async function checkTagStatus() {
    // Single round-trip for both "following" and "muted" flags so the
    // header buttons render the correct label on first paint.
    try {
      const status = await api.get<{ following: boolean; muted: boolean }>(
        `/api/v1/accounts/tags/${encodeURIComponent(tag)}/status`
      );
      isFollowing = !!status.following;
      isMuted = !!status.muted;
    } catch { /* */ }
  }

  async function toggleMute() {
    muteLoading = true;
    try {
      if (isMuted) {
        await api.delete(`/api/v1/accounts/muted_tags/${encodeURIComponent(tag)}`);
        isMuted = false;
      } else {
        await api.post(`/api/v1/accounts/muted_tags/${encodeURIComponent(tag)}`);
        isMuted = true;
      }
    } catch { /* */ }
    finally { muteLoading = false; }
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

  // Re-load whenever the route's tag changes. SvelteKit reuses this
  // component across /tags/a -> /tags/b navigations, so a plain onMount
  // (fires once) left the previous tag's posts on screen even though the
  // URL and title updated (issue #36). Reading `tag` registers it as the
  // only dependency; untrack keeps the cursor/posts the loaders touch from
  // retriggering the effect (which would re-fetch on every pagination).
  $effect(() => {
    if (tag) {
      untrack(() => {
        feed.reset();
        checkTagStatus();
      });
    }
  });
</script>

<svelte:head>
  <title>#{tag} - {$instanceName}</title>
</svelte:head>

<div class="tag-page">
  <div class="sticky-section-head tag-header">
    <h1 class="tag-title">#{tag}</h1>
    <div class="tag-actions">
      <button
        type="button"
        class="tag-action-btn"
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
      <button
        type="button"
        class="tag-action-btn"
        class:muted-tag={isMuted}
        onclick={toggleMute}
        disabled={muteLoading}
        title={isMuted ? 'Unmute — posts with this tag will surface again' : 'Mute — hide posts with this tag from your feeds and notifications'}
      >
        {#if isMuted}
          <span class="material-symbols-outlined" style="font-size: 18px">notifications_active</span>
          Unmute
        {:else}
          <span class="material-symbols-outlined" style="font-size: 18px">notifications_off</span>
          Mute
        {/if}
      </button>
    </div>
  </div>

  <FeedList
    posts={feed.posts}
    loading={feed.loading}
    hasMore={feed.hasMore}
    onloadmore={feed.loadMore}
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

  .tag-actions {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
  }

  .tag-action-btn {
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

  .tag-action-btn:hover {
    background: var(--color-primary);
    color: white;
  }

  .tag-action-btn.following {
    background: var(--color-primary);
    color: white;
  }

  .tag-action-btn.following:hover {
    background: transparent;
    color: var(--color-primary);
  }

  /* Muted state uses the danger palette instead of primary so the
     "Unmute" button reads as an opt-out destination of a
     destructive-toward-signal action. */
  .tag-action-btn.muted-tag {
    border-color: var(--color-danger, #ef4444);
    background: var(--color-danger, #ef4444);
    color: white;
  }

  .tag-action-btn.muted-tag:hover {
    background: transparent;
    color: var(--color-danger, #ef4444);
  }

  .tag-action-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>
