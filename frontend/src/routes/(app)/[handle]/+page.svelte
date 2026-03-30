<script lang="ts">
  import { page } from '$app/stores';
  import { get } from 'svelte/store';
  import { onMount } from 'svelte';
  import type { Identity, Relationship, Post } from '$lib/api/types.js';
  import { lookupAccount, getRelationship, follow, unfollow, block, unblock, mute, unmute } from '$lib/api/accounts.js';
  import { getAccountStatuses } from '$lib/api/statuses.js';
  import { api } from '$lib/api/client.js';
  import { authStore, isStaffMember } from '$lib/stores/auth.js';
  import ProfileHeader from '$lib/components/profile/ProfileHeader.svelte';
  import AdminProfileActions from '$lib/components/admin/AdminProfileActions.svelte';
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
  let confirmAction: 'block' | 'unblock' | 'mute' | 'unmute' | null = $state(null);
  let familiarFollowers = $state<Identity[]>([]);
  let vouchStatus = $state<{ count: number; required: number; vouches: any[] } | null>(null);
  let hasVouched = $state(false);
  let vouchLoading = $state(false);

  const unsub = page.subscribe(($page) => {
    handle = $page.params.handle!;
  });

  let tabs = $derived(
    isOwnProfile
      ? [
          { id: 'posts', label: 'Posts' },
          { id: 'replies', label: 'Replies' },
          { id: 'media', label: 'Media' },
          { id: 'direct', label: 'Direct' },
        ]
      : [
          { id: 'posts', label: 'Posts' },
          { id: 'replies', label: 'Replies' },
          { id: 'media', label: 'Media' },
        ]
  );

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
        // Load familiar followers and vouch status
        try {
          familiarFollowers = await api.get<Identity[]>(`/api/v1/accounts/${account.id}/familiar_followers`);
        } catch { familiarFollowers = []; }
        try {
          const vs = await api.get<{ count: number; required: number; vouches: any[] }>(`/api/v1/verification/vouches/${account.id}`);
          if (vs.count > 0 || vs.vouches?.length > 0) {
            vouchStatus = vs;
            hasVouched = vs.vouches?.some((v: any) => v.voucher?.id === auth.user?.id) ?? false;
          }
        } catch { vouchStatus = null; }
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
      const params: { only_media?: boolean; pinned?: boolean; cursor?: string; exclude_replies?: boolean; only_direct?: boolean } = {};
      if (activeTab === 'posts') params.exclude_replies = true;
      if (activeTab === 'media') params.only_media = true;
      if (activeTab === 'direct') params.only_direct = true;
      if (cursor) params.cursor = cursor;

      const result = await getAccountStatuses(account.id, params);
      const items = Array.isArray(result) ? result : (result as any).data || [];
      if (reset) {
        posts = items;
      } else {
        posts = [...posts, ...items];
      }
      cursor = items.length > 0 ? items[items.length - 1]?.id : null;
      hasMore = items.length >= 20;
    } catch {
      // Silently handle feed errors
    } finally {
      feedLoading = false;
    }
  }

  function handleTabChange() {
    loadPosts(true);
  }

  async function handleVouch() {
    if (!account) return;
    vouchLoading = true;
    try {
      const result = await api.post<{ status: string; vouch_count: number; required: number }>(`/api/v1/verification/vouch/${account.id}`);
      hasVouched = true;
      if (vouchStatus) {
        vouchStatus = { ...vouchStatus, count: result.vouch_count };
      }
    } catch { /* already vouched or error */ }
    finally { vouchLoading = false; }
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

  function handleBlock() {
    if (!account || !relationship) return;
    confirmAction = relationship.blocking ? 'unblock' : 'block';
  }

  function handleMute() {
    if (!account || !relationship) return;
    confirmAction = relationship.muting ? 'unmute' : 'mute';
  }

  async function executeConfirmedAction() {
    if (!account || !relationship || !confirmAction) return;
    try {
      switch (confirmAction) {
        case 'block':
          relationship = await block(account.id);
          break;
        case 'unblock':
          relationship = await unblock(account.id);
          break;
        case 'mute':
          relationship = await mute(account.id);
          break;
        case 'unmute':
          relationship = await unmute(account.id);
          break;
      }
    } catch { /* handle error */ }
    confirmAction = null;
  }

  const confirmMessages: Record<string, { title: string; message: string; button: string }> = {
    block: { title: 'Block this account?', message: 'They will not be able to see your posts or interact with you. You can unblock them at any time.', button: 'Block' },
    unblock: { title: 'Unblock this account?', message: 'They will be able to see your posts and interact with you again.', button: 'Unblock' },
    mute: { title: 'Mute this account?', message: 'Their posts will be hidden from your feeds. They will not be notified.', button: 'Mute' },
    unmute: { title: 'Unmute this account?', message: 'Their posts will appear in your feeds again.', button: 'Unmute' },
  };

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

    {#if familiarFollowers.length > 0}
      <div class="familiar-followers">
        <div class="familiar-avatars">
          {#each familiarFollowers.slice(0, 3) as ff (ff.id)}
            <a href="/@{ff.handle}" class="familiar-avatar-link">
              {#if ff.avatar_url}
                <img src={ff.avatar_url} alt={ff.display_name || ff.handle} class="familiar-avatar" />
              {:else}
                <div class="familiar-avatar familiar-avatar-placeholder">
                  {(ff.display_name || ff.handle).charAt(0).toUpperCase()}
                </div>
              {/if}
            </a>
          {/each}
        </div>
        <span class="familiar-text">
          Followed by
          {#each familiarFollowers.slice(0, 2) as ff, i (ff.id)}
            {#if i > 0}, {/if}
            <a href="/@{ff.handle}" class="familiar-link">{ff.display_name || ff.handle}</a>
          {/each}
          {#if familiarFollowers.length > 2}
            and {familiarFollowers.length - 2} more you follow
          {/if}
        </span>
      </div>
    {/if}

    {#if vouchStatus && !isOwnProfile}
      <div class="vouch-banner card">
        <div class="vouch-info">
          <span class="material-symbols-outlined vouch-icon">verified</span>
          <div>
            <strong>{account.display_name || account.handle}</strong> is requesting peer verification
            <span class="vouch-progress">{vouchStatus.count} / {vouchStatus.required} vouches</span>
          </div>
        </div>
        {#if hasVouched}
          <span class="vouch-done">You vouched</span>
        {:else}
          <button class="btn btn-outline btn-sm" type="button" onclick={handleVouch} disabled={vouchLoading}>
            {vouchLoading ? 'Vouching...' : 'Vouch for identity'}
          </button>
        {/if}
      </div>
    {/if}

    {#if $isStaffMember && !isOwnProfile}
      <AdminProfileActions {account} />
    {/if}

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

{#if confirmAction}
  <div class="dialog-overlay" onclick={() => confirmAction = null} role="dialog" aria-modal="true" aria-label={confirmMessages[confirmAction].title}>
    <div class="dialog-panel" onclick={(e) => e.stopPropagation()}>
      <h3 class="dialog-title">{confirmMessages[confirmAction].title}</h3>
      <p class="dialog-message">{confirmMessages[confirmAction].message}</p>
      <div class="dialog-actions">
        <button type="button" class="dialog-cancel" onclick={() => confirmAction = null}>Cancel</button>
        <button
          type="button"
          class={confirmAction === 'block' || confirmAction === 'mute' ? 'dialog-confirm-danger' : 'dialog-confirm'}
          onclick={executeConfirmedAction}
        >
          {confirmMessages[confirmAction].button}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .profile-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .vouch-banner {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-3) var(--space-4);
    gap: var(--space-3);
  }

  .vouch-info {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    color: var(--color-on-surface);
  }

  .vouch-icon {
    color: var(--color-primary);
    font-size: 20px;
  }

  .vouch-progress {
    color: var(--color-on-surface-variant);
    margin-inline-start: var(--space-1);
  }

  .vouch-done {
    font-size: var(--text-sm);
    color: var(--color-success, #22c55e);
    font-weight: 600;
    white-space: nowrap;
  }

  .btn-sm {
    padding: var(--space-1) var(--space-3);
    font-size: var(--text-sm);
    white-space: nowrap;
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

  .dialog-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.6);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    padding: var(--space-4);
  }

  .dialog-panel {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-6);
    max-width: 400px;
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .dialog-title {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--color-text);
    margin: 0;
  }

  .dialog-message {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.5;
    margin: 0;
  }

  .dialog-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    margin-top: var(--space-2);
  }

  .dialog-cancel {
    padding: var(--space-2) var(--space-4);
    border-radius: var(--radius-md);
    border: 1px solid var(--color-border);
    background: transparent;
    color: var(--color-text);
    font-size: var(--text-sm);
    cursor: pointer;
  }

  .dialog-cancel:hover {
    background: var(--color-surface-hover);
  }

  .dialog-confirm-danger {
    padding: var(--space-2) var(--space-4);
    border-radius: var(--radius-md);
    border: none;
    background: var(--color-danger);
    color: white;
    font-size: var(--text-sm);
    font-weight: 500;
    cursor: pointer;
  }

  .dialog-confirm-danger:hover {
    opacity: 0.9;
  }

  .dialog-confirm {
    padding: var(--space-2) var(--space-4);
    border-radius: var(--radius-md);
    border: none;
    background: var(--color-primary);
    color: white;
    font-size: var(--text-sm);
    font-weight: 500;
    cursor: pointer;
  }

  .dialog-confirm:hover {
    opacity: 0.9;
  }

  /* Familiar followers */
  .familiar-followers {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 16px;
    font-size: 0.8125rem;
    color: var(--color-text-secondary);
  }

  .familiar-avatars {
    display: flex;
  }

  .familiar-avatar-link {
    margin-inline-end: -8px;
  }

  .familiar-avatar-link:last-child {
    margin-inline-end: 0;
  }

  .familiar-avatar {
    width: 24px;
    height: 24px;
    border-radius: 50%;
    object-fit: cover;
    border: 2px solid var(--color-surface-container-lowest);
  }

  .familiar-avatar-placeholder {
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--color-primary-soft);
    color: var(--color-primary);
    font-size: 0.6rem;
    font-weight: 700;
  }

  .familiar-text {
    line-height: 1.3;
  }

  .familiar-link {
    color: var(--color-text);
    font-weight: 600;
    text-decoration: none;
  }

  .familiar-link:hover {
    text-decoration: underline;
  }
</style>
