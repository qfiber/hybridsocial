<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';
  import type { Identity } from '$lib/api/types.js';
  import { lookupAccount, getFollowing, follow, unfollow } from '$lib/api/accounts.js';
  import { authStore } from '$lib/stores/auth.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let handle = $state('');
  let account: Identity | null = $state(null);
  let following: Identity[] = $state([]);
  let loading = $state(true);
  let loadingMore = $state(false);
  let hasMore = $state(true);
  let cursor: string | null = $state(null);
  let error = $state('');
  let followingSet: Set<string> = $state(new Set());
  let followLoading: Set<string> = $state(new Set());

  const unsub = page.subscribe(($page) => {
    handle = $page.params.handle;
  });

  async function loadFollowing(reset = false) {
    if (reset) {
      following = [];
      cursor = null;
      hasMore = true;
      loading = true;
    } else {
      loadingMore = true;
    }
    error = '';

    try {
      if (!account) {
        account = await lookupAccount(handle);
      }
      const result = await getFollowing(account.id, cursor || undefined);
      const data = Array.isArray(result) ? result : result.data || [];
      if (reset) {
        following = data;
        // Mark all as followed since this is the following list
        followingSet = new Set(data.map((a: Identity) => a.id));
      } else {
        following = [...following, ...data];
        const s = new Set(followingSet);
        data.forEach((a: Identity) => s.add(a.id));
        followingSet = s;
      }
      cursor = Array.isArray(result) ? null : result.next_cursor;
      hasMore = Array.isArray(result) ? data.length >= 20 : !!result.next_cursor;
    } catch {
      error = 'Failed to load following.';
    } finally {
      loading = false;
      loadingMore = false;
    }
  }

  async function toggleFollow(id: string, isFollowingUser: boolean) {
    const next = new Set(followLoading);
    next.add(id);
    followLoading = next;
    try {
      if (isFollowingUser) {
        await unfollow(id);
        const s = new Set(followingSet);
        s.delete(id);
        followingSet = s;
      } else {
        await follow(id);
        const s = new Set(followingSet);
        s.add(id);
        followingSet = s;
      }
    } catch {
      // Error handled silently
    } finally {
      const n = new Set(followLoading);
      n.delete(id);
      followLoading = n;
    }
  }

  function isOwnAccount(id: string): boolean {
    const state = get(authStore);
    return state.user?.id === id;
  }

  onMount(() => {
    loadFollowing(true);
    return () => unsub();
  });
</script>

<svelte:head>
  <title>Following - {handle} - HybridSocial</title>
</svelte:head>

<div class="following-page">
  <div class="page-header">
    <a href="/@{handle}" class="back-link" aria-label="Back to profile">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <polyline points="15 18 9 12 15 6"/>
      </svg>
    </a>
    <div>
      <h1 class="page-title">Following</h1>
      <p class="page-subtitle">@{handle}</p>
    </div>
  </div>

  {#if loading}
    <div class="loading-state">
      <Spinner />
    </div>
  {:else if error}
    <div class="error-state">
      <p>{error}</p>
      <button type="button" class="btn btn-outline" onclick={() => loadFollowing(true)}>Retry</button>
    </div>
  {:else if following.length === 0}
    <div class="empty-state">
      <p class="empty-text">Not following anyone yet</p>
    </div>
  {:else}
    <div class="account-list">
      {#each following as acct (acct.id)}
        <div class="account-card">
          <a href="/@{acct.handle}" class="account-info-link">
            <Avatar src={acct.avatar_url} name={acct.display_name || acct.handle} size="md" />
            <div class="account-info">
              <span class="account-name">{acct.display_name || acct.handle}</span>
              <span class="account-handle">@{acct.handle}</span>
            </div>
          </a>
          {#if !isOwnAccount(acct.id)}
            <button
              type="button"
              class="btn {followingSet.has(acct.id) ? 'btn-outline' : 'btn-primary'} btn-sm"
              onclick={() => toggleFollow(acct.id, followingSet.has(acct.id))}
              disabled={followLoading.has(acct.id)}
            >
              {followingSet.has(acct.id) ? 'Following' : 'Follow'}
            </button>
          {/if}
        </div>
      {/each}
    </div>

    {#if hasMore}
      <div class="load-more">
        <button
          type="button"
          class="btn btn-outline"
          onclick={() => loadFollowing(false)}
          disabled={loadingMore}
        >
          {loadingMore ? 'Loading...' : 'Load more'}
        </button>
      </div>
    {/if}
  {/if}
</div>

<style>
  .following-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
  }

  .page-header {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    margin-block-end: var(--space-4);
  }

  .back-link {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    border-radius: var(--radius-full);
    color: var(--color-text);
    text-decoration: none;
    transition: background var(--transition-fast);
  }

  .back-link:hover {
    background: var(--color-surface);
    text-decoration: none;
  }

  .page-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
    line-height: 1.2;
  }

  .page-subtitle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .loading-state {
    display: flex;
    justify-content: center;
    padding: var(--space-16);
  }

  .error-state,
  .empty-state {
    text-align: center;
    padding: var(--space-16) var(--space-4);
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-3);
  }

  .empty-text {
    font-size: var(--text-base);
    color: var(--color-text-tertiary);
  }

  .account-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .account-card {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-3) var(--space-4);
    border-radius: var(--radius-lg);
    transition: background var(--transition-fast);
  }

  .account-card:hover {
    background: var(--color-surface);
  }

  .account-info-link {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    text-decoration: none;
    color: var(--color-text);
    min-width: 0;
    flex: 1;
  }

  .account-info-link:hover {
    text-decoration: none;
  }

  .account-info {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .account-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .account-handle {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .load-more {
    display: flex;
    justify-content: center;
    padding: var(--space-4);
  }

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

  .btn-sm {
    padding: var(--space-1) var(--space-3);
    font-size: var(--text-xs);
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

  .btn-outline:hover:not(:disabled) {
    background: var(--color-surface);
  }

  .btn-outline:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>
