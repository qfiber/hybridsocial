<script lang="ts">
  import { page } from '$app/stores';
  import { get } from 'svelte/store';
  import { onMount } from 'svelte';
  import type { Identity, Relationship, Post } from '$lib/api/types.js';
  import { lookupAccount, getRelationship, follow, unfollow, block, unblock, mute, unmute } from '$lib/api/accounts.js';
  import { getAccountStatuses } from '$lib/api/statuses.js';
  import { authStore } from '$lib/stores/auth.js';
  import ProfileHeader from '$lib/components/profile/ProfileHeader.svelte';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import FeedList from '$lib/components/feed/FeedList.svelte';

  import Skeleton from '$lib/components/ui/Skeleton.svelte';

  let handle = $state('');
  let account: Identity | null = $state(null);
  let relationship: Relationship | null = $state(null);
  let posts: Post[] = $state([]);
  let loading = $state(true);
  let feedLoading = $state(false);
  let hasMore = $state(true);
  let cursor: string | null = $state(null);
  let error: string | null = $state(null);
  let activeTab = $state('posts');
  let isOwnProfile = $state(false);

  const unsub = page.subscribe(($page) => {
    handle = $page.params.handle;
  });

  const tabs = [
    { id: 'posts', label: 'Posts' },
    { id: 'replies', label: 'Posts & Replies' },
    { id: 'media', label: 'Media' },
  ];

  let retryCount = 0;

  async function loadProfile() {
    loading = true;
    error = null;
    try {
      account = await lookupAccount(handle);
      retryCount = 0;
      const auth = get(authStore);
      isOwnProfile = auth.user?.id === account.id;

      if (!isOwnProfile && auth.user) {
        relationship = await getRelationship(account.id);
      }

      await loadPosts(true);
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'Failed to load profile';
      // Auto-retry on network errors (server might be restarting)
      if (msg === 'Failed to fetch' && retryCount < 3) {
        retryCount++;
        setTimeout(() => loadProfile(), 2000);
        return;
      }
      error = msg === 'Failed to fetch' ? 'Could not reach the server. Please try again.' : msg;
    } finally {
      loading = false;
    }
  }

  async function loadPosts(reset = false) {
    if (!account) return;
    if (reset) {
      posts = [];
      cursor = null;
      hasMore = true;
    }
    feedLoading = true;
    try {
      const params: { only_media?: boolean; cursor?: string } = {};
      if (activeTab === 'media') params.only_media = true;
      if (cursor) params.cursor = cursor;

      const result = await getAccountStatuses(account.id, params);
      if (reset) {
        posts = result.data;
      } else {
        posts = [...posts, ...result.data];
      }
      cursor = result.next_cursor;
      hasMore = !!result.next_cursor;
    } catch {
      // Silently handle feed errors
    } finally {
      feedLoading = false;
    }
  }

  function handleTabChange() {
    loadPosts(true);
  }

  async function handleFollow() {
    if (!account) return;
    try {
      relationship = await follow(account.id);
    } catch { /* handle error */ }
  }

  async function handleUnfollow() {
    if (!account) return;
    try {
      relationship = await unfollow(account.id);
    } catch { /* handle error */ }
  }

  async function handleBlock() {
    if (!account || !relationship) return;
    try {
      if (relationship.blocking) {
        relationship = await unblock(account.id);
      } else {
        relationship = await block(account.id);
      }
    } catch { /* handle error */ }
  }

  async function handleMute() {
    if (!account || !relationship) return;
    try {
      if (relationship.muting) {
        relationship = await unmute(account.id);
      } else {
        relationship = await mute(account.id);
      }
    } catch { /* handle error */ }
  }

  function handleMessage() {
    if (account) {
      window.location.href = `/messages?to=${account.handle}`;
    }
  }

  function handleEdit() {
    window.location.href = '/settings';
  }

  onMount(() => {
    loadProfile();
    return () => unsub();
  });

  // Reload when tab changes (not on initial mount)
  let prevTab = $state(activeTab);
  $effect(() => {
    if (activeTab !== prevTab && account) {
      prevTab = activeTab;
      handleTabChange();
    }
  });
</script>

<svelte:head>
  <title>{account ? (account.display_name || account.handle) : 'Profile'} - HybridSocial</title>
</svelte:head>

<div class="profile-page">
  {#if loading}
    <div class="profile-skeleton">
      <Skeleton width="100%" height="180px" />
      <div class="profile-skeleton-info">
        <Skeleton width="80px" height="80px" rounded />
        <Skeleton width="200px" height="24px" />
        <Skeleton width="140px" height="16px" />
        <Skeleton width="100%" height="40px" />
        <Skeleton width="200px" height="16px" />
      </div>
    </div>
  {:else if error}
    <div class="profile-error card">
      <p class="error-title">Could not load profile</p>
      <p class="error-message">{error}</p>
      <button class="btn btn-outline" type="button" onclick={loadProfile}>Try again</button>
    </div>
  {:else if account}
    <ProfileHeader
      {account}
      {relationship}
      {isOwnProfile}
      onfollow={handleFollow}
      onunfollow={handleUnfollow}
      onblock={handleBlock}
      onmute={handleMute}
      onmessage={handleMessage}
      onedit={handleEdit}
    />

    <div class="profile-feed-section">
      <Tabs {tabs} bind:active={activeTab}>
        {#if activeTab === 'posts' || activeTab === 'replies' || activeTab === 'media'}
          <FeedList
            {posts}
            loading={feedLoading}
            {hasMore}
            onloadmore={() => loadPosts(false)}
            emptyMessage={activeTab === 'media' ? 'No media posts yet' : 'No posts yet'}
          />
        {/if}
      </Tabs>
    </div>
  {/if}
</div>

<style>
  .profile-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .profile-skeleton {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow: hidden;
  }

  .profile-skeleton-info {
    padding: var(--space-6);
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    margin-block-start: -40px;
  }

  .profile-feed-section {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: 0 var(--space-4) var(--space-4);
  }

  .profile-error {
    text-align: center;
    padding: var(--space-16) var(--space-4);
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-3);
  }

  .error-title {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--color-text);
  }

  .error-message {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }
</style>
