<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { getPage } from '$lib/api/pages.js';
  import PageManageModal from '$lib/components/page/PageManageModal.svelte';
  import ComposerTrigger from '$lib/components/post/ComposerTrigger.svelte';
  import MediaGrid from '$lib/components/feed/MediaGrid.svelte';
  import { api } from '$lib/api/client.js';
  import { currentUser, isStaffMember } from '$lib/stores/auth.js';
  import type { Post } from '$lib/api/types.js';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import FeedList from '$lib/components/feed/FeedList.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import AdminProfileActions from '$lib/components/admin/AdminProfileActions.svelte';
  import EntityHeader from '$lib/components/entity/EntityHeader.svelte';
  import { createEntityFeed } from '$lib/feed/entity-feed.svelte.js';
  import { instanceName } from '$lib/stores/instance.js';

  let pageId = $state('');
  let pageData: any = $state(null);
  let loading = $state(true);
  let error = $state('');
  let activeTab = $state('posts');
  let isFollowing = $state(false);
  let followLoading = $state(false);

  // Shared paginated post feed (Posts + Media tabs). The endpoint
  // supports cursor pagination, so this also gives the page infinite
  // scroll that the previous one-shot fetch lacked.
  const feed = createEntityFeed(async (cursor) => {
    const result = await api.get<{ data?: Post[] } | Post[]>(
      `/api/v1/pages/${pageId}/statuses`,
      cursor ? { cursor } : undefined,
    );
    return Array.isArray(result) ? result : (result.data ?? []);
  });

  // Owner detection — backend serialize_page returns
  // organization.owner_id (the identity_id of the page's creator).
  // Compare against the current user so the Edit/Delete bar only
  // appears for the actual owner. Instance admins/mods see the
  // existing AdminProfileActions component on the page header
  // since pages are identities; their moderation tools live there.
  let isOwner = $derived(
    !!pageData &&
      !!$currentUser &&
      pageData.organization?.owner_id === $currentUser.id,
  );

  // The old Edit / Manage / Delete trio is collapsed into one icon
  // that opens PageManageModal. All editing, role grants, invites,
  // and the delete confirmation live inside the modal now.
  let manageModalOpen = $state(false);

  // Page *settings* are governance — only the page's own manager-tier roles
  // (owner / admin / editor / moderator). Instance staff do NOT get the
  // settings gear here: their powers (takedown, suspend, silence) live in the
  // separate AdminProfileActions panel above, per the "admin controls, not
  // entity settings" rule.
  let canManage = $derived(
    isOwner ||
      (typeof pageData?.viewer_role === 'string' &&
        ['admin', 'editor', 'moderator'].includes(pageData.viewer_role)),
  );

  // Posting AS the page is narrower than managing it: only roles the
  // backend's Pages.can_edit? accepts (owner / admin / editor) may author
  // in the page's name. Moderators and instance staff can moderate but not
  // post as the page, and ordinary visitors get no composer at all. This
  // mirrors the server guard in StatusController.create — the backend is
  // still authoritative; this just hides an affordance that would 403.
  let canPostAsPage = $derived(
    isOwner ||
      (typeof pageData?.viewer_role === 'string' &&
        ['owner', 'admin', 'editor'].includes(pageData.viewer_role)),
  );

  const tabs = [
    { id: 'posts', label: 'Posts' },
    { id: 'media', label: 'Media' },
    { id: 'about', label: 'About' },
  ];

  const unsub = page.subscribe(($page) => {
    pageId = $page.params.id!;
  });

  async function loadPage() {
    loading = true;
    error = '';
    try {
      pageData = await getPage(pageId);
      isFollowing = pageData?.is_following ?? false;
      await feed.reset();
    } catch {
      error = 'Failed to load page.';
    } finally {
      loading = false;
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
  <title>{pageData?.display_name || pageData?.name || 'Page'} - {$instanceName}</title>
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
    <EntityHeader
      name={pageData.display_name || pageData.name || pageData.handle}
      handle={pageData.handle}
      avatarUrl={pageData.avatar_url || pageData.logo_url}
      coverUrl={pageData.header_url || pageData.cover_url}
      description={pageData.description || pageData.bio}
    >
      {#snippet meta()}
        {#if pageData.category}
          <span class="page-category-badge">{pageData.category}</span>
        {/if}
      {/snippet}

      {#snippet adminActions()}
        {#if $isStaffMember && !isOwner && pageData}
          <AdminProfileActions
            account={pageData}
            entity={{ kind: 'page', id: pageData.id, name: pageData.display_name || pageData.handle }}
            ondeleted={() => goto('/pages')}
          />
        {/if}
        {#if canManage}
          <!-- One settings icon → PageManageModal (all admin actions). -->
          <button
            type="button"
            class="btn btn-ghost icon-btn"
            onclick={() => (manageModalOpen = true)}
            aria-label="Manage page"
            title="Manage page"
          >
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="12" cy="12" r="3" />
              <path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83-2.83l.06-.06A1.65 1.65 0 004.68 15a1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 012.83-2.83l.06.06A1.65 1.65 0 009 4.68a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 2.83l-.06.06A1.65 1.65 0 0019.4 9a1.65 1.65 0 001.51 1H21a2 2 0 010 4h-.09a1.65 1.65 0 00-1.51 1z" />
            </svg>
          </button>
        {/if}
      {/snippet}

      {#snippet primaryAction()}
        {#if !isOwner}
          <button
            type="button"
            class="btn {isFollowing ? 'btn-outline' : 'btn-primary'}"
            onclick={toggleFollow}
            disabled={followLoading}
          >
            {isFollowing ? 'Following' : 'Follow'}
          </button>
        {/if}
      {/snippet}

      {#snippet stats()}
        {#if pageData.followers_count !== undefined}
          <span class="stat-item">
            <strong>{pageData.followers_count}</strong>
            <span class="stat-label">Followers</span>
          </span>
        {/if}
      {/snippet}
    </EntityHeader>

    <div class="page-feed-section">
      <Tabs {tabs} bind:active={activeTab}>
        {#if activeTab === 'posts'}
          {#if canPostAsPage}
            <ComposerTrigger
              pageId={pageData.id}
              contextLabel={`Posting to ${pageData.title || pageData.name || pageData.display_name || 'page'}`}
              placeholder={`Share something with ${pageData.display_name || pageData.name || pageData.handle || 'this page'}…`}
            />
          {/if}
          <FeedList
            posts={feed.posts}
            loading={feed.loading}
            hasMore={feed.hasMore}
            viewerContext="page"
            emptyMessage="No posts yet"
            onloadmore={feed.loadMore}
          />
        {:else if activeTab === 'media'}
          <MediaGrid
            posts={feed.posts}
            loading={feed.loading}
            hasMore={feed.hasMore}
            onloadmore={feed.loadMore}
            emptyMessage="No photos or videos posted on this page yet"
          />
        {:else if activeTab === 'about'}
          <div class="about-section">
            {#if pageData.description || pageData.bio}
              <div class="about-block">
                <h3 class="about-heading">About</h3>
                <p class="about-text">{pageData.description || pageData.bio}</p>
              </div>
            {/if}

            {#if pageData.website || pageData.email || pageData.phone || pageData.address}
              <div class="about-block">
                <h3 class="about-heading">Contact</h3>
                <div class="business-details">
                  {#if pageData.website}
                    <div class="detail-item">
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                        <circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z"/>
                      </svg>
                      <a href={pageData.website} class="detail-link" target="_blank" rel="noopener">{pageData.website}</a>
                    </div>
                  {/if}
                  {#if pageData.email}
                    <div class="detail-item">
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                        <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/><polyline points="22,6 12,13 2,6"/>
                      </svg>
                      <a href="mailto:{pageData.email}" class="detail-link">{pageData.email}</a>
                    </div>
                  {/if}
                  {#if pageData.phone}
                    <div class="detail-item">
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                        <path d="M22 16.92v3a2 2 0 01-2.18 2 19.79 19.79 0 01-8.63-3.07 19.5 19.5 0 01-6-6 19.79 19.79 0 01-3.07-8.67A2 2 0 014.11 2h3a2 2 0 012 1.72 12.84 12.84 0 00.7 2.81 2 2 0 01-.45 2.11L8.09 9.91a16 16 0 006 6l1.27-1.27a2 2 0 012.11-.45 12.84 12.84 0 002.81.7A2 2 0 0122 16.92z"/>
                      </svg>
                      <span>{pageData.phone}</span>
                    </div>
                  {/if}
                  {#if pageData.address}
                    <div class="detail-item">
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                        <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z"/><circle cx="12" cy="10" r="3"/>
                      </svg>
                      <span>{pageData.address}</span>
                    </div>
                  {/if}
                </div>
              </div>
            {/if}

            {#if pageData.social_links && pageData.social_links.length > 0}
              <div class="about-block">
                <h3 class="about-heading">Links</h3>
                <div class="social-links">
                  {#each pageData.social_links as link (link.url || link)}
                    <a href={link.url || link} class="social-link" target="_blank" rel="noopener">
                      {link.label || link.url || link}
                    </a>
                  {/each}
                </div>
              </div>
            {/if}

            <div class="about-block">
              <h3 class="about-heading">Info</h3>
              <dl class="info-list">
                {#if pageData.category}
                  <div class="info-row">
                    <dt class="info-label">Category</dt>
                    <dd class="info-value" style="text-transform: capitalize">{pageData.category}</dd>
                  </div>
                {/if}
                {#if pageData.followers_count !== undefined}
                  <div class="info-row">
                    <dt class="info-label">Followers</dt>
                    <dd class="info-value">{pageData.followers_count.toLocaleString()}</dd>
                  </div>
                {/if}
                {#if pageData.created_at}
                  <div class="info-row">
                    <dt class="info-label">Created</dt>
                    <dd class="info-value">{new Date(pageData.created_at).toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' })}</dd>
                  </div>
                {/if}
              </dl>
            </div>
          </div>
        {/if}
      </Tabs>
    </div>
  {/if}
</div>

<PageManageModal
  bind:open={manageModalOpen}
  bind:page={pageData}
  ondeleted={() => goto('/pages')}
/>

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

  /* Structured info list — mirrors the group About for a consistent look. */
  .info-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .info-row {
    display: flex;
    gap: var(--space-3);
    font-size: var(--text-sm);
  }

  .info-label {
    flex-shrink: 0;
    width: 96px;
    color: var(--color-text-tertiary);
  }

  .info-value {
    color: var(--color-text);
    min-width: 0;
    word-break: break-word;
  }

  /* Icon-only button sizing (the manage gear). All other buttons use the
     global .btn system in app.css, so Pages and Groups match exactly. */
  .icon-btn {
    width: 40px;
    height: 40px;
    padding: 0;
  }

  /* --- Edit / Delete modal --- */
  .modal-overlay {
    position: fixed;
    inset: 0;
    background: var(--scrim-medium);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-4);
    z-index: 1000;
  }

  .modal-card {
    background: var(--color-surface-raised);
    border-radius: var(--radius-xl);
    padding: var(--space-6);
    max-width: 520px;
    width: 100%;
    max-height: 90vh;
    max-height: 90dvh;
    overflow-y: auto;
  }

  .modal-card-narrow {
    max-width: 420px;
  }

  .modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-end: var(--space-3);
  }

  .modal-header h3,
  .modal-title-danger {
    margin: 0;
    font-size: var(--text-lg);
    font-weight: 700;
  }

  .modal-title-danger {
    color: var(--color-danger);
    margin-block-end: var(--space-2);
  }

  .modal-message {
    color: var(--color-text-secondary);
    line-height: 1.5;
    margin-block-end: var(--space-4);
  }

  .modal-close {
    background: transparent;
    border: 0;
    font-size: 1rem;
    cursor: pointer;
    color: var(--color-text-tertiary);
  }

  .modal-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .modal-field {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .modal-field span {
    font-size: var(--text-xs);
    font-weight: 700;
    color: var(--color-text-secondary);
  }

  .modal-field input,
  .modal-field textarea {
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-bg);
    color: var(--color-text);
    font-size: var(--text-sm);
    font-family: inherit;
  }

  .modal-field input:focus,
  .modal-field textarea:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .modal-error {
    color: var(--color-danger);
    font-size: var(--text-sm);
    margin: 0;
  }

  .modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    margin-block-start: var(--space-3);
  }

</style>
