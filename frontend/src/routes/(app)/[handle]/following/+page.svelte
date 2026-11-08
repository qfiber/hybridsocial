<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';
  import type { Identity, Group } from '$lib/api/types.js';
  import { lookupAccount, getFollowing, follow, unfollow } from '$lib/api/accounts.js';
  import { getGroups } from '$lib/api/groups.js';
  import { api } from '$lib/api/client.js';
  import { authStore } from '$lib/stores/auth.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';
  import { instanceName } from '$lib/stores/instance.js';

  // Section identifier — drives the modal title and which item-renderer
  // gets used. Keeping this explicit (instead of just a label) lets the
  // modal stay generic.
  type SectionKey = 'people' | 'pages' | 'groups' | 'hashtags' | 'bots';

  interface HashtagItem {
    name: string;
    url?: string;
  }

  let handle = $state('');
  let account: Identity | null = $state(null);
  let loading = $state(true);
  let error = $state('');

  // Raw follows (people + pages + bots in a single list — backend
  // returns Identity rows; we partition client-side by type / is_bot).
  let allFollowing = $state<Identity[]>([]);
  let myGroups = $state<Group[]>([]);
  let followedHashtags = $state<HashtagItem[]>([]);

  // Per-section collapse state. People + Pages start expanded since
  // those are the most-used; the rest fold by default to keep the
  // page short on first paint.
  let expanded = $state<Record<SectionKey, boolean>>({
    people: true,
    pages: true,
    groups: false,
    hashtags: false,
    bots: false,
  });

  let isSelf = $derived.by(() => {
    if (!account) return false;
    return get(authStore).user?.id === account.id;
  });

  const unsub = page.subscribe(($page) => {
    // The URL segment for /@tester/... is captured verbatim including
    // the leading "@", so the raw param is "@tester". Strip it once
    // here so every consumer (display, lookupAccount, back-link)
    // sees the bare handle and doesn't end up double-prefixing.
    const raw = $page.params.handle ?? '';
    handle = raw.startsWith('@') ? raw.slice(1) : raw;
  });

  // Pull every page of /following so the buckets are accurate. Cap at
  // ~500 to keep memory bounded — accounts with thousands of follows
  // will still see a full page-1 of each bucket and can use the modal
  // search to find specifics.
  async function loadAllFollowing(accountId: string): Promise<Identity[]> {
    const out: Identity[] = [];
    let cursor: string | undefined;
    for (let i = 0; i < 25; i++) {
      const result = await getFollowing(accountId, cursor);
      const data = Array.isArray(result) ? result : (result.data ?? []);
      out.push(...data);
      const next = Array.isArray(result) ? null : result.next_cursor;
      if (!next || data.length === 0) break;
      cursor = next;
    }
    return out;
  }

  async function loadAll() {
    loading = true;
    error = '';
    try {
      account = await lookupAccount(handle);
      const tasks: Promise<unknown>[] = [
        loadAllFollowing(account.id).then((rows) => {
          allFollowing = rows;
        }),
      ];

      // Groups + hashtag follows are private state — only the viewer's
      // own lists are exposed. Other profiles see a placeholder section
      // so the layout stays consistent.
      if (get(authStore).user?.id === account.id) {
        tasks.push(
          getGroups('member')
            .then((res) => {
              myGroups = Array.isArray(res) ? res : (res.data ?? []);
            })
            .catch(() => {
              myGroups = [];
            }),
        );
        tasks.push(
          api
            .get<HashtagItem[] | { name: string }[]>('/api/v1/accounts/followed_tags')
            .then((res) => {
              followedHashtags = Array.isArray(res) ? (res as HashtagItem[]) : [];
            })
            .catch(() => {
              followedHashtags = [];
            }),
        );
      }

      await Promise.all(tasks);
    } catch {
      error = 'Failed to load following.';
    } finally {
      loading = false;
    }
  }

  // Buckets — derived so the sections re-render reactively when an
  // unfollow toggles `allFollowing`. type === 'page' is the
  // canonical page marker (pages are Identity rows with that type),
  // is_bot trumps a bare `user` type so a "user that is a bot" lands
  // under Bots, not People.
  let people = $derived(
    allFollowing.filter((a) => a.type !== 'page' && !a.is_bot),
  );
  let pages = $derived(allFollowing.filter((a) => a.type === 'page'));
  let bots = $derived(
    allFollowing.filter((a) => a.is_bot && a.type !== 'page'),
  );

  // Show-more modal
  let modalOpen = $state(false);
  let modalSection = $state<SectionKey>('people');
  let modalQuery = $state('');
  let modalPage = $state(0);
  const MODAL_PAGE_SIZE = 20;

  function openModal(section: SectionKey) {
    modalSection = section;
    modalQuery = '';
    modalPage = 0;
    modalOpen = true;
  }

  function modalTitle(section: SectionKey): string {
    return {
      people: 'People',
      pages: 'Pages',
      groups: 'Groups',
      hashtags: 'Hashtags',
      bots: 'Bots',
    }[section];
  }

  let modalSourceItems = $derived.by<unknown[]>(() => {
    switch (modalSection) {
      case 'people':
        return people;
      case 'pages':
        return pages;
      case 'groups':
        return myGroups;
      case 'hashtags':
        return followedHashtags;
      case 'bots':
        return bots;
    }
  });

  let modalFiltered = $derived.by<unknown[]>(() => {
    const q = modalQuery.trim().toLowerCase();
    if (!q) return modalSourceItems;
    return modalSourceItems.filter((item) => modalMatches(item, q));
  });

  let modalTotalPages = $derived(
    Math.max(1, Math.ceil(modalFiltered.length / MODAL_PAGE_SIZE)),
  );

  let modalSlice = $derived(
    modalFiltered.slice(
      modalPage * MODAL_PAGE_SIZE,
      modalPage * MODAL_PAGE_SIZE + MODAL_PAGE_SIZE,
    ),
  );

  // Clamp the page index whenever filtering trims the result set so a
  // search that empties the current page doesn't show a blank list.
  $effect(() => {
    if (modalPage >= modalTotalPages) modalPage = modalTotalPages - 1;
    if (modalPage < 0) modalPage = 0;
  });

  function modalMatches(item: unknown, q: string): boolean {
    const i = item as Record<string, unknown>;
    const haystack = [
      i.name,
      i.display_name,
      i.handle,
      i.acct,
      i.bio,
      i.description,
    ]
      .filter(Boolean)
      .join(' ')
      .toLowerCase();
    return haystack.includes(q);
  }

  // Unfollow flow for People / Pages / Bots — toggles the row out of
  // allFollowing without re-fetching the whole list.
  let unfollowingIds = $state<Set<string>>(new Set());

  async function handleUnfollow(id: string) {
    const next = new Set(unfollowingIds);
    next.add(id);
    unfollowingIds = next;
    try {
      await unfollow(id);
      allFollowing = allFollowing.filter((a) => a.id !== id);
    } catch {
      // Surface in the page error banner if needed; silent for now.
    } finally {
      const after = new Set(unfollowingIds);
      after.delete(id);
      unfollowingIds = after;
    }
  }

  async function handleUnfollowHashtag(name: string) {
    try {
      await api.delete(`/api/v1/accounts/followed_tags/${encodeURIComponent(name)}`);
      followedHashtags = followedHashtags.filter((t) => t.name !== name);
    } catch {
      // ignore
    }
  }

  async function handleLeaveGroup(id: string) {
    try {
      await api.post(`/api/v1/groups/${id}/leave`);
      myGroups = myGroups.filter((g) => g.id !== id);
    } catch {
      // ignore
    }
  }

  function toggleSection(key: SectionKey) {
    expanded[key] = !expanded[key];
  }

  onMount(() => {
    loadAll();
    return () => unsub();
  });
</script>

<svelte:head>
  <title>Following - {handle} - {$instanceName}</title>
</svelte:head>

<div class="following-page">
  <div class="page-header">
    <a href="/@{handle}" class="back-link" aria-label="Back to profile">
      <svg class="rtl-mirror" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
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
      <button type="button" class="btn btn-outline" onclick={loadAll}>Retry</button>
    </div>
  {:else}
    {@render section(
      'people',
      'People',
      people.length,
      'Following: real human accounts you follow.',
    )}
    {#if expanded.people}
      <div class="section-body">
        {#if people.length === 0}
          <p class="section-empty">Not following any people yet.</p>
        {:else}
          <ul class="account-list">
            {#each people.slice(0, 10) as acct (acct.id)}
              {@render accountRow(acct)}
            {/each}
          </ul>
          {#if people.length > 10}
            <button type="button" class="show-more" onclick={() => openModal('people')}>
              Show all {people.length} people
            </button>
          {/if}
        {/if}
      </div>
    {/if}

    {@render section('pages', 'Pages', pages.length, 'Pages you follow.')}
    {#if expanded.pages}
      <div class="section-body">
        {#if pages.length === 0}
          <p class="section-empty">No followed pages yet.</p>
        {:else}
          <ul class="account-list">
            {#each pages.slice(0, 10) as acct (acct.id)}
              {@render accountRow(acct)}
            {/each}
          </ul>
          {#if pages.length > 10}
            <button type="button" class="show-more" onclick={() => openModal('pages')}>
              Show all {pages.length} pages
            </button>
          {/if}
        {/if}
      </div>
    {/if}

    {@render section('groups', 'Groups', myGroups.length, 'Groups you belong to.')}
    {#if expanded.groups}
      <div class="section-body">
        {#if !isSelf}
          <p class="section-empty">Group memberships are private.</p>
        {:else if myGroups.length === 0}
          <p class="section-empty">Not part of any groups yet.</p>
        {:else}
          <ul class="account-list">
            {#each myGroups.slice(0, 10) as g (g.id)}
              {@render groupRow(g)}
            {/each}
          </ul>
          {#if myGroups.length > 10}
            <button type="button" class="show-more" onclick={() => openModal('groups')}>
              Show all {myGroups.length} groups
            </button>
          {/if}
        {/if}
      </div>
    {/if}

    {@render section(
      'hashtags',
      'Hashtags',
      followedHashtags.length,
      'Hashtags you follow.',
    )}
    {#if expanded.hashtags}
      <div class="section-body">
        {#if !isSelf}
          <p class="section-empty">Followed hashtags are private.</p>
        {:else if followedHashtags.length === 0}
          <p class="section-empty">No followed hashtags yet.</p>
        {:else}
          <ul class="hashtag-list">
            {#each followedHashtags.slice(0, 10) as tag (tag.name)}
              {@render hashtagRow(tag)}
            {/each}
          </ul>
          {#if followedHashtags.length > 10}
            <button type="button" class="show-more" onclick={() => openModal('hashtags')}>
              Show all {followedHashtags.length} hashtags
            </button>
          {/if}
        {/if}
      </div>
    {/if}

    {@render section(
      'bots',
      'Bots',
      bots.length,
      'Automated accounts you follow.',
    )}
    {#if expanded.bots}
      <div class="section-body">
        {#if bots.length === 0}
          <p class="section-empty">No followed bots yet.</p>
        {:else}
          <ul class="account-list">
            {#each bots.slice(0, 10) as acct (acct.id)}
              {@render accountRow(acct)}
            {/each}
          </ul>
          {#if bots.length > 10}
            <button type="button" class="show-more" onclick={() => openModal('bots')}>
              Show all {bots.length} bots
            </button>
          {/if}
        {/if}
      </div>
    {/if}
  {/if}
</div>

{#snippet section(key: SectionKey, label: string, count: number, hint: string)}
  <button
    type="button"
    class="section-header"
    onclick={() => toggleSection(key)}
    aria-expanded={expanded[key]}
  >
    <span class="section-caret" class:open={expanded[key]} aria-hidden="true">▶</span>
    <span class="section-label">{label}</span>
    <span class="section-count">{count}</span>
    <span class="section-hint">{hint}</span>
  </button>
{/snippet}

{#snippet accountRow(acct: Identity)}
  <li class="account-card">
    <a href="/@{acct.acct || acct.handle}" class="account-info-link">
      <Avatar src={acct.avatar_url} name={acct.display_name || acct.handle} size="md" />
      <div class="account-info">
        <span class="account-name">{acct.display_name || acct.handle}</span>
        <!-- `acct` is the webfinger-form handle ("user@domain"); fall
             back to the bare local handle when not present. The DB
             `handle` column stores a munged local-part for remote
             identities, which made every row read like
             `@user_otherinstance_e2c8` instead of `@user@otherinstance`. -->
        <span class="account-handle">@{acct.acct || acct.handle}</span>
      </div>
    </a>
    {#if isSelf}
      <button
        type="button"
        class="btn btn-outline btn-sm"
        onclick={() => handleUnfollow(acct.id)}
        disabled={unfollowingIds.has(acct.id)}
      >
        {unfollowingIds.has(acct.id) ? '…' : 'Unfollow'}
      </button>
    {/if}
  </li>
{/snippet}

{#snippet groupRow(g: Group)}
  <li class="account-card">
    <a href="/groups/{g.id}" class="account-info-link">
      <Avatar src={g.avatar_url} name={g.name} size="md" />
      <div class="account-info">
        <span class="account-name">{g.name}</span>
        <span class="account-handle">{g.member_count} {g.member_count === 1 ? 'member' : 'members'}</span>
      </div>
    </a>
    {#if isSelf}
      <button type="button" class="btn btn-outline btn-sm" onclick={() => handleLeaveGroup(g.id)}>Leave</button>
    {/if}
  </li>
{/snippet}

{#snippet hashtagRow(tag: HashtagItem)}
  <li class="hashtag-card">
    <a href="/tags/{encodeURIComponent(tag.name)}" class="account-info-link">
      <span class="hashtag-symbol" aria-hidden="true">#</span>
      <span class="account-name">{tag.name}</span>
    </a>
    {#if isSelf}
      <button type="button" class="btn btn-outline btn-sm" onclick={() => handleUnfollowHashtag(tag.name)}>Unfollow</button>
    {/if}
  </li>
{/snippet}

<Modal bind:open={modalOpen} title="All {modalTitle(modalSection)} ({modalFiltered.length})">
  <div class="modal-search">
    <input
      type="search"
      class="modal-search-input"
      placeholder="Search…"
      bind:value={modalQuery}
      aria-label="Search {modalTitle(modalSection)}"
    />
  </div>

  {#if modalFiltered.length === 0}
    <p class="modal-empty">No matches.</p>
  {:else}
    <ul class="modal-list">
      {#each modalSlice as item (modalSection === 'hashtags' ? (item as HashtagItem).name : (item as { id: string }).id)}
        {#if modalSection === 'groups'}
          {@render groupRow(item as Group)}
        {:else if modalSection === 'hashtags'}
          {@render hashtagRow(item as HashtagItem)}
        {:else}
          {@render accountRow(item as Identity)}
        {/if}
      {/each}
    </ul>
  {/if}

  <div class="modal-pager">
    <button
      type="button"
      class="btn btn-outline btn-sm"
      disabled={modalPage === 0}
      onclick={() => (modalPage = Math.max(0, modalPage - 1))}
    >Prev</button>
    <span class="modal-page-label">Page {modalPage + 1} of {modalTotalPages}</span>
    <button
      type="button"
      class="btn btn-outline btn-sm"
      disabled={modalPage >= modalTotalPages - 1}
      onclick={() => (modalPage = Math.min(modalTotalPages - 1, modalPage + 1))}
    >Next</button>
  </div>
</Modal>

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
  }

  .back-link:hover {
    background: var(--color-surface);
    text-decoration: none;
  }

  .page-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
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

  .error-state {
    text-align: center;
    padding: var(--space-12) var(--space-4);
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    align-items: center;
  }

  /* Section header — clickable bar that toggles the body. Painted
     with the theme's configured gradient (admin → Theme → Start/End)
     plus a soft dark overlay to lift white-on-gradient contrast over
     the WCAG 2.1 AA 4.5:1 threshold for normal text. Type sizes are
     also bumped so the label + count + hint qualify as large text
     (≥14pt bold) where bold is used. */
  .section-header {
    position: relative;
    display: flex;
    align-items: center;
    gap: var(--space-3);
    width: 100%;
    padding: var(--space-3) var(--space-4);
    margin-block-start: var(--space-3);
    background: linear-gradient(
      var(--gradient-direction, 135deg),
      var(--gradient-start, var(--color-primary)),
      var(--gradient-end, var(--color-primary-hover, var(--color-primary)))
    );
    border: 0;
    border-radius: var(--radius-lg);
    cursor: pointer;
    text-align: start;
    color: #fff;
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.05);
    transition: filter 150ms ease, transform 150ms ease;
    overflow: hidden;
  }

  /* Subtle dark overlay sits above the gradient and behind the text.
     Bumps effective contrast from ~3.7:1 (raw teal) to ~4.7:1 — clears
     AA for normal text on every brand gradient that includes a
     reasonably saturated color. */
  .section-header::before {
    content: '';
    position: absolute;
    inset: 0;
    background: rgba(0, 0, 0, 0.18);
    pointer-events: none;
  }

  .section-header > * {
    position: relative;
    z-index: 1;
  }

  .section-header:hover {
    filter: brightness(1.05);
    transform: translateY(-1px);
  }

  .section-caret {
    font-size: 12px;
    color: #fff;
    transition: transform 150ms ease;
  }

  .section-caret.open {
    transform: rotate(90deg);
  }

  .section-label {
    /* 18px bold → AA "large text" threshold (3:1) cleanly passes
       even before the dark overlay; with the overlay it clears AA
       for normal text too. */
    font-size: var(--text-lg, 1.125rem);
    font-weight: 700;
    color: #fff;
  }

  /* Solid white pill — the brand-color text inside reads at >7:1
     against white regardless of which gradient stops the operator
     picks, so the count is unambiguous on any palette. */
  .section-count {
    font-size: var(--text-sm);
    font-weight: 800;
    background: var(--color-surface-container-lowest);
    color: var(--gradient-start, var(--color-primary));
    padding: 2px 10px;
    border-radius: 999px;
    line-height: 1.4;
  }

  .section-hint {
    /* 14px bold qualifies as AA "large text" (3:1). With the dark
       overlay above it lands closer to 4.7:1 — clears AA for normal
       text outright. No more 0.85 opacity. */
    font-size: var(--text-sm);
    font-weight: 600;
    color: #fff;
    margin-inline-start: auto;
    text-align: end;
  }

  .section-body {
    padding-block: var(--space-2);
  }

  .section-empty {
    padding: var(--space-3) var(--space-4);
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
  }

  .account-list,
  .hashtag-list,
  .modal-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
  }

  .account-card,
  .hashtag-card {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-3) var(--space-4);
    border-radius: var(--radius-lg);
  }

  .account-card:hover,
  .hashtag-card:hover {
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

  .hashtag-symbol {
    font-size: 1.5rem;
    font-weight: 700;
    color: var(--color-primary);
    width: 32px;
    text-align: center;
  }

  .show-more {
    width: 100%;
    margin-block-start: var(--space-2);
    padding: var(--space-2);
    background: transparent;
    color: var(--color-primary);
    border: 0;
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-weight: 600;
    cursor: pointer;
  }

  .show-more:hover {
    background: var(--color-primary-soft);
  }

  /* Modal */
  .modal-search {
    margin-block-end: var(--space-3);
  }

  .modal-search-input {
    width: 100%;
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    color: var(--color-text);
    background: var(--color-bg);
  }

  .modal-search-input:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .modal-empty {
    text-align: center;
    color: var(--color-text-tertiary);
    padding: var(--space-6);
    font-size: var(--text-sm);
  }

  .modal-pager {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-start: var(--space-3);
    padding-block-start: var(--space-3);
    border-block-start: 1px solid var(--color-border);
  }

  .modal-page-label {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  /* Buttons */
  .btn {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    font-weight: 500;
    cursor: pointer;
    border: 0;
    transition: background var(--transition-fast);
  }

  .btn-sm {
    padding: var(--space-1) var(--space-3);
    font-size: var(--text-xs);
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
