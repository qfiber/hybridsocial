<script lang="ts">
  import { instanceName } from '$lib/stores/instance.js';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import { get } from 'svelte/store';
  import { onMount } from 'svelte';
  import type { Identity, Relationship, Post } from '$lib/api/types.js';
  import { lookupAccount, getRelationship, follow, unfollow, block, unblock, mute, unmute } from '$lib/api/accounts.js';
  import { getAccountStatuses } from '$lib/api/statuses.js';
  import { api } from '$lib/api/client.js';
  import { authStore, currentUser, isStaffMember } from '$lib/stores/auth.js';
  import ProfileHeader from '$lib/components/profile/ProfileHeader.svelte';
  import AdminProfileActions from '$lib/components/admin/AdminProfileActions.svelte';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';
  import FeedList from '$lib/components/feed/FeedList.svelte';
  import { createEntityFeed } from '$lib/feed/entity-feed.svelte.js';

  import Skeleton from '$lib/components/ui/Skeleton.svelte';

  let handle = $state('');
  let account = $state<Identity | null>(null);
  let relationship: Relationship | null = $state(null);
  let pinnedPosts: Post[] = $state([]);
  let loading = $state(true);
  let error: string | null = $state(null);
  let activeTab = $state('posts');

  // Shared paginated post feed (tab-aware fetch). Reactions hits the
  // favourites endpoint; every other tab hits account statuses with the
  // matching filter. Pinned posts (Posts tab) are handled separately below.
  const feed = createEntityFeed(async (cursor) => {
    if (!account) return [];
    if (activeTab === 'reactions') {
      const params: Record<string, string> = {};
      if (cursor) params.max_id = cursor;
      const items = await api.get<Post[]>('/api/v1/accounts/favourites', params);
      return Array.isArray(items) ? items : [];
    }
    const params: {
      only_media?: boolean;
      cursor?: string;
      exclude_replies?: boolean;
      only_direct?: boolean;
    } = {};
    if (activeTab === 'posts') params.exclude_replies = true;
    if (activeTab === 'media') params.only_media = true;
    if (activeTab === 'direct') params.only_direct = true;
    if (cursor) params.cursor = cursor;
    const result = await getAccountStatuses(account.id, params);
    return Array.isArray(result) ? result : ((result as any).data ?? []);
  });

  // Reactive identity of the signed-in user. Snapshotting
  // `get(authStore)` inside `loadProfile` races with auth
  // hydration — on first navigation the store can still be empty
  // when the profile finishes loading, which left the Direct tab
  // hidden on the user's own profile. Subscribing keeps this in
  // sync regardless of ordering.
  let viewerId = $state<string | null>(null);
  currentUser.subscribe((u) => {
    viewerId = u?.id ?? null;
  });

  let isOwnProfile = $derived(
    account !== null && viewerId !== null && account.id === viewerId,
  );
  let confirmAction: 'block' | 'unblock' | 'mute' | 'unmute' | null = $state(null);
  let showConfirmModal = $state(false);
  let familiarFollowers = $state<Identity[]>([]);
  let vouchStatus = $state<{ count: number; required: number; vouches: any[] } | null>(null);
  let hasVouched = $state(false);
  let vouchLoading = $state(false);

  const unsub = page.subscribe(($page) => {
    handle = $page.params.handle!;
  });

  // Re-fetch the profile whenever the URL handle changes. Without
  // this, navigating from /@alice to /@bob via a same-route link
  // (e.g. the New Members widget on the sidebar) only updates the
  // address bar — the page component is reused, the loader was
  // pinned to the original handle, and the user kept staring at the
  // previous profile. Skip the very first run because onMount also
  // fires loadProfile() and we don't want a duplicate request.
  let firstHandleEffect = true;
  $effect(() => {
    // Reading `handle` registers the dependency.
    const h = handle;
    if (!h) return;
    if (firstHandleEffect) {
      firstHandleEffect = false;
      return;
    }
    loadProfile();
  });

  let tabs = $derived(
    isOwnProfile
      ? [
          { id: 'posts', label: 'Posts' },
          { id: 'replies', label: 'Replies' },
          { id: 'media', label: 'Media' },
          { id: 'direct', label: 'Direct' },
          { id: 'reactions', label: 'Reactions' },
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

      // Pages are organization identities with their own page-aware route
      // (composer + manage gear for managers, Follow for visitors). Reaching a
      // page by its @handle — via a post's author link, a mention, or search —
      // must land on that same canonical view, not the generic account profile
      // that showed a stray Follow button and hid the composer/manage controls
      // from the owner. The page id IS the identity id, so route straight there.
      if (account?.type === 'page') {
        await goto(`/pages/${account.id}`, { replaceState: true });
        return;
      }

      retryCount = 0;
      const auth = get(authStore);
      const ownProfile = !!account && !!auth.user && auth.user.id === account.id;

      if (!ownProfile && auth.user) {
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

      await reloadFeed();
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

  // Reset the feed for the current tab. Pinned posts are only meaningful
  // on the main "Posts" tab; fetch them in parallel with the first page
  // so they show at the top without an extra round-trip on paginate.
  async function reloadFeed() {
    if (!account) return;
    pinnedPosts = [];
    const pinnedPromise =
      activeTab === 'posts'
        ? getAccountStatuses(account.id, { pinned: true }).catch(() => [] as Post[])
        : Promise.resolve(null as Post[] | null);
    const [, pinnedResult] = await Promise.all([feed.reset(), pinnedPromise]);
    if (pinnedResult) pinnedPosts = Array.isArray(pinnedResult) ? pinnedResult : [];
  }

  // Pinned posts render at the top of the Posts tab. Filter them out of
  // the regular feed so the same post doesn't appear twice.
  let displayPosts = $derived.by(() => {
    if (activeTab !== 'posts' || pinnedPosts.length === 0) return feed.posts;
    const pinnedIds = new Set(pinnedPosts.map((p) => p.id));
    return [...pinnedPosts, ...feed.posts.filter((p) => !pinnedIds.has(p.id))];
  });

  function handleTabChange() {
    reloadFeed();
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

  // After any relationship change (follow / unfollow / block /
  // unblock / mute / unmute) the profile's counts can shift and the
  // server may now answer the show endpoint differently (e.g. a
  // block hides the whole row). Re-pull both the relationship and
  // the account so the header doesn't desync from server state.
  async function refreshRelationshipAndAccount() {
    if (!account) return;
    try {
      const [rel, fresh] = await Promise.all([
        getRelationship(account.id),
        lookupAccount(handle).catch(() => null),
      ]);
      relationship = rel;
      if (fresh) account = fresh;
    } catch {
      /* best-effort refresh */
    }
  }

  async function handleFollow() {
    if (!account) return;
    try {
      relationship = await follow(account.id);
      await refreshRelationshipAndAccount();
    } catch { /* handle error */ }
  }

  async function handleUnfollow() {
    if (!account) return;
    try {
      relationship = await unfollow(account.id);
      await refreshRelationshipAndAccount();
    } catch { /* handle error */ }
  }

  function handleBlock() {
    if (!account || !relationship) return;
    confirmAction = relationship.blocking ? 'unblock' : 'block';
    showConfirmModal = true;
  }

  function handleMute() {
    if (!account || !relationship) return;
    confirmAction = relationship.muting ? 'unmute' : 'mute';
    showConfirmModal = true;
  }

  async function executeConfirmedAction() {
    if (!account || !relationship || !confirmAction) return;
    try {
      switch (confirmAction) {
        case 'block':
          relationship = await block(account.id);
          // Blocking the account: the profile is now hidden from the
          // viewer per the server gate, so route home rather than
          // sit on a 404'd profile.
          showConfirmModal = false;
          confirmAction = null;
          await goto('/home', { replaceState: true });
          return;
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
      await refreshRelationshipAndAccount();
    } catch { /* handle error */ }
    showConfirmModal = false;
    confirmAction = null;
  }

  const confirmMessages: Record<string, { title: string; message: string; button: string }> = {
    block: { title: 'Block this account?', message: 'They will not be able to see your posts or interact with you. You can unblock them at any time.', button: 'Block' },
    unblock: { title: 'Unblock this account?', message: 'They will be able to see your posts and interact with you again.', button: 'Unblock' },
    mute: { title: 'Mute this account?', message: 'Their posts will be hidden from your feeds. They will not be notified.', button: 'Mute' },
    unmute: { title: 'Unmute this account?', message: 'Their posts will appear in your feeds again.', button: 'Unmute' },
  };

  function handleMessage() {
    if (!account) return;
    // Remote accounts carry `@host` in `acct`; locals don't. The
    // new-conversation page reads `?to=` and resolves against whichever
    // form it gets. Use the fully-qualified handle when available so
    // DMs to @alice@mastodon.social find the right identity.
    const a = account as { acct?: string; handle: string };
    const handle = a.acct || a.handle;
    window.location.href = `/messages/new?to=${encodeURIComponent(handle)}`;
  }

  function handleEdit() {
    window.location.href = '/settings/profile';
  }

  // Show a freshly-posted status on the author's own profile feed
  // immediately, without waiting for a reload. Same event shape the
  // home timeline uses — composer dispatches `new-post` with an
  // optimistic (pending: true) post, then `post-replace` once the
  // server confirms.
  function handleNewPost(e: Event) {
    const newPost = (e as CustomEvent<Post>).detail;
    if (!newPost || !isOwnProfile) return;
    // Skip replies on the main "Posts" tab — they belong under a
    // reply tab or the parent post page.
    if (newPost.parent_id && activeTab === 'posts') return;
    feed.prepend(newPost);
  }

  function handlePostReplace(e: Event) {
    const { oldId, post } = (e as CustomEvent<{ oldId: string; post: Post }>).detail;
    if (!oldId || !post) return;
    feed.replaceById(oldId, post);
  }

  // Reflect a pin/unpin from the menu without reloading the whole tab.
  function handlePinChanged(e: Event) {
    const { id, pinned, post: updated } = (e as CustomEvent<{
      id: string;
      pinned: boolean;
      post: Post;
    }>).detail;
    if (!id || !isOwnProfile) return;
    if (pinned) {
      // Move it into the pinned list (newest pin first) and stamp
      // is_pinned=true in the regular array so the indicator shows
      // even before the next refetch.
      pinnedPosts = [updated, ...pinnedPosts.filter((p) => p.id !== id)];
      feed.set(feed.posts.map((p) => (p.id === id ? { ...p, is_pinned: true } : p)));
    } else {
      pinnedPosts = pinnedPosts.filter((p) => p.id !== id);
      feed.set(feed.posts.map((p) => (p.id === id ? { ...p, is_pinned: false } : p)));
    }
  }

  onMount(() => {
    loadProfile();

    window.addEventListener('chat-event', handleRealtimeEvent as EventListener);
    window.addEventListener('new-post', handleNewPost);
    window.addEventListener('post-replace', handlePostReplace);
    window.addEventListener('post-pin-changed', handlePinChanged);
    return () => {
      window.removeEventListener('chat-event', handleRealtimeEvent as EventListener);
      window.removeEventListener('new-post', handleNewPost);
      window.removeEventListener('post-replace', handlePostReplace);
      window.removeEventListener('post-pin-changed', handlePinChanged);
      unsub();
    };
  });

  // Direct-post SSE fan-out. Fires for every direct post the viewer
  // is a participant of, whether they authored it locally or it
  // was just ingested from a federated peer. We only prepend when
  // the Direct tab is the active one — otherwise the post already
  // shows up the next time the user switches tabs (loadPosts runs
  // on tab change).
  function handleRealtimeEvent(ev: Event) {
    const detail = (ev as CustomEvent<{ type: string; data: Post }>).detail;
    if (!detail || detail.type !== 'direct.new_post') return;
    if (activeTab !== 'direct') return;
    if (!isOwnProfile) return;

    // prepend dedupes against optimistic local inserts.
    feed.prepend(detail.data);
  }

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
  <title>{account ? (account.display_name || account.handle) : 'Profile'} - {$instanceName}</title>
</svelte:head>

<div class="profile-page">
  {#if loading}
    <div class="profile-skeleton">
      <Skeleton width="100%" height="210px" />
      <div class="profile-skeleton-info">
        <Skeleton width="104px" height="104px" rounded />
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
    >
      {#snippet staffActions()}
        {#if $isStaffMember && !isOwnProfile && account}
          <AdminProfileActions {account} />
        {/if}
      {/snippet}
    </ProfileHeader>

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

    <div class="profile-feed-section">
      <Tabs {tabs} bind:active={activeTab}>
        {#if activeTab === 'posts' || activeTab === 'replies' || activeTab === 'media' || activeTab === 'reactions'}
          <FeedList
            posts={displayPosts}
            loading={feed.loading}
            hasMore={feed.hasMore}
            viewerContext="profile"
            onloadmore={feed.loadMore}
            emptyMessage={
              activeTab === 'media'
                ? 'No media posts yet'
                : activeTab === 'reactions'
                  ? "You haven't reacted to any posts yet."
                  : 'No posts yet'
            }
          />
        {/if}
      </Tabs>
    </div>
  {/if}
</div>

<Modal
  bind:open={showConfirmModal}
  title={confirmAction ? confirmMessages[confirmAction].title : ''}
  onclose={() => (confirmAction = null)}
>
  {#if confirmAction}
    <p class="dialog-message">{confirmMessages[confirmAction].message}</p>
    <div class="dialog-actions">
      <button type="button" class="dialog-cancel" onclick={() => (showConfirmModal = false)}>Cancel</button>
      <button
        type="button"
        class={confirmAction === 'block' || confirmAction === 'mute' ? 'dialog-confirm-danger' : 'dialog-confirm'}
        onclick={executeConfirmedAction}
      >
        {confirmMessages[confirmAction].button}
      </button>
    </div>
  {/if}
</Modal>

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
    border-radius: var(--radius-2xl);
    box-shadow: var(--shadow-md);
    overflow: hidden;
  }

  .profile-skeleton-info {
    padding: var(--space-6);
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    margin-block-start: -44px;
  }

  .profile-feed-section {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-2xl);
    box-shadow: var(--shadow-md);
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

  .dialog-message {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.5;
    margin: 0 0 var(--space-4);
  }

  .dialog-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
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
