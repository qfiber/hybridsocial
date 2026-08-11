<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import type { Post, MediaAttachment } from '$lib/api/types.js';
  import Modal from '$lib/components/ui/Modal.svelte';
  import ThreadedReplies from '$lib/components/post/ThreadedReplies.svelte';
  import StreamPlayer from '$lib/components/streams/StreamPlayer.svelte';
  import { getPostContext } from '$lib/api/statuses.js';
  import { instanceName } from '$lib/stores/instance.js';
  import { t } from '$lib/stores/i18n.js';

  let posts = $state<Post[]>([]);
  let loading = $state(true);
  let error = $state('');

  // Infinite scroll: the feed keeps a keyset cursor (last item's id) and loads
  // the next page as the viewer nears the end, instead of stopping after one
  // page. `hasMore` goes false once a page comes back short.
  const PAGE_SIZE = 20;
  let cursor = $state<string | null>(null);
  let hasMore = $state(true);
  let loadingMore = $state(false);
  let feedEl = $state<HTMLDivElement | null>(null);

  // Streams autoplay by default (the whole point of the format); still
  // toggleable and remembered across visits.
  const AUTOPLAY_KEY = 'hs-streams-autoplay';
  let autoplay = $state(true);

  function toggleAutoplay() {
    autoplay = !autoplay;
    try {
      localStorage.setItem(AUTOPLAY_KEY, autoplay ? '1' : '0');
    } catch {
      /* storage unavailable — the toggle just won't persist */
    }
  }

  // Mute is a single GLOBAL state shared by every clip, not per-video: unmute
  // one and every clip (including the next you scroll to) plays with sound.
  // Starts muted (browsers block sound-on autoplay until a gesture) and is
  // remembered across visits.
  const MUTED_KEY = 'hs-streams-muted';
  let muted = $state(true);

  function toggleMuted() {
    muted = !muted;
    try {
      localStorage.setItem(MUTED_KEY, muted ? '1' : '0');
    } catch {
      /* storage unavailable — the choice just won't persist */
    }
  }

  // Per-user opt-in: when on, the feed also includes videos from the wider
  // fediverse (not just local + locally-boosted). Remembered per device and
  // re-fetches the feed on toggle. Off by default.
  const FEDERATED_KEY = 'hs-streams-federated';
  let showFederated = $state(false);

  function toggleFederated() {
    showFederated = !showFederated;
    try {
      localStorage.setItem(FEDERATED_KEY, showFederated ? '1' : '0');
    } catch {
      /* storage unavailable — the toggle just won't persist */
    }
    loadStreams();
  }

  // Aspect-ratio filter. Default is vertical 9:16 (`orientation=portrait`, the
  // native Streams format); toggling on asks the server for clips of every
  // orientation (`orientation=all`). Remembered per device.
  const ASPECT_KEY = 'hs-streams-aspect';
  let showAllAspect = $state(false);

  function toggleAspect() {
    showAllAspect = !showAllAspect;
    try {
      localStorage.setItem(ASPECT_KEY, showAllAspect ? '1' : '0');
    } catch {
      /* storage unavailable — the toggle just won't persist */
    }
    loadStreams();
  }

  // Sort + free-text/hashtag filter. `trending` is the server default so it's
  // omitted from the query on the happy path. The choice is remembered per
  // device — the page component remounts on every navigation, so without this
  // the sort snaps back to trending each visit.
  const SORT_KEY = 'hs-streams-sort';
  const SORT_VALUES = ['trending', 'newest', 'oldest'] as const;
  let sort = $state<(typeof SORT_VALUES)[number]>('trending');
  let search = $state('');
  let searchTimer: ReturnType<typeof setTimeout> | undefined;
  // The immersive layout keeps the clip full-bleed; search + sort open as
  // overlays on demand instead of stacking rows above the feed.
  let searchOpen = $state(false);
  let sortOpen = $state(false);

  const SORTS: { value: (typeof SORT_VALUES)[number]; label: string }[] = [
    { value: 'trending', label: 'Trending' },
    { value: 'newest', label: 'Newest' },
    { value: 'oldest', label: 'Oldest' },
  ];

  // The feed carries clips of every orientation (the server is asked for
  // `orientation=all`), so the only client-side requirement is that the post
  // actually has a video to play. The player handles fitting a horizontal or
  // square clip into the frame.
  function streamVideo(post: Post): MediaAttachment | undefined {
    return post.media_attachments?.find((m) => m.type === 'video');
  }

  let streams = $derived(posts.filter((p) => streamVideo(p)));

  // --- View reporting ------------------------------------------------------
  async function reportView(
    postId: string,
    watchDuration: number,
    totalDuration: number,
    completed: boolean,
    replayed: boolean,
  ) {
    try {
      await api.post(`/api/v1/statuses/${postId}/view`, {
        watch_duration: watchDuration,
        total_duration: totalDuration,
        completed,
        replayed,
        source: 'streams_feed',
      });
    } catch {
      // Best-effort — never block playback on view reporting.
    }
  }

  // Shared query params for the current filters (orientation / sort / federated
  // / search). Pagination adds the cursor on top.
  function streamParams(): Record<string, string> {
    // Default to the native 9:16 vertical format; the aspect toggle opts into
    // clips of every orientation/size.
    const params: Record<string, string> = { orientation: showAllAspect ? 'all' : 'portrait' };
    if (sort !== 'trending') params.sort = sort;
    if (showFederated) params.include_federated = 'true';
    const q = search.trim();
    if (q) params.q = q;
    return params;
  }

  async function loadStreams() {
    loading = true;
    error = '';
    cursor = null;
    hasMore = true;
    try {
      const result = await api.get<any>('/api/v1/timelines/streams', streamParams());
      const data: Post[] = Array.isArray(result) ? result : (result as any)?.data || [];
      posts = data;
      cursor = data.length > 0 ? data[data.length - 1].id : null;
      hasMore = data.length >= PAGE_SIZE;
      // If the first page was all filtered out client-side but the server may
      // have more, keep trying to fill the viewport.
      if (feedEl) maybeLoadMore();
    } catch {
      error = 'Failed to load streams.';
    } finally {
      loading = false;
    }
  }

  async function loadMore() {
    if (loadingMore || !hasMore || !cursor || loading) return;
    loadingMore = true;
    try {
      const params = streamParams();
      // Oldest is ascending → page forward with min_id; every other sort is
      // descending → max_id (older).
      params[sort === 'oldest' ? 'min_id' : 'max_id'] = cursor;
      const result = await api.get<any>('/api/v1/timelines/streams', params);
      const data: Post[] = Array.isArray(result) ? result : (result as any)?.data || [];
      const seen = new Set(posts.map((p) => p.id));
      const fresh = data.filter((p) => !seen.has(p.id));
      posts = [...posts, ...fresh];
      cursor = data.length > 0 ? data[data.length - 1].id : cursor;
      hasMore = data.length >= PAGE_SIZE;
    } catch {
      // Best-effort — leave hasMore so a later scroll can retry.
    } finally {
      loadingMore = false;
    }
  }

  // Trigger a page load when the viewer is within ~2 clips of the end.
  function maybeLoadMore() {
    if (!feedEl || !hasMore || loadingMore) return;
    const remaining = feedEl.scrollHeight - feedEl.scrollTop - feedEl.clientHeight;
    if (remaining < feedEl.clientHeight * 2) loadMore();
  }

  function changeSort(next: (typeof SORT_VALUES)[number]) {
    if (sort === next) return;
    sort = next;
    try {
      localStorage.setItem(SORT_KEY, next);
    } catch {
      /* storage unavailable — the choice just won't persist */
    }
    loadStreams();
  }

  function onSearchInput() {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => loadStreams(), 300);
  }

  // --- Comments sheet (a full-bleed vertical feed has no room for an inline
  // thread, so the comment button opens a sheet instead). -------------------
  let commentsOpen = $state(false);
  let commentsPost = $state<Post | null>(null);
  let commentsDescendants = $state<Post[]>([]);
  let commentsLoading = $state(false);
  let commentsError = $state('');

  async function openComments(post: Post) {
    commentsPost = post;
    commentsOpen = true;
    commentsError = '';
    commentsDescendants = [];
    commentsLoading = true;
    try {
      const context = await getPostContext(post.id);
      commentsDescendants = context.descendants ?? [];
    } catch {
      commentsError = 'Failed to load comments.';
    } finally {
      commentsLoading = false;
    }
  }

  function closeComments() {
    commentsOpen = false;
    commentsPost = null;
    commentsDescendants = [];
  }

  function addComment() {
    if (!commentsPost) return;
    window.dispatchEvent(
      new CustomEvent('open-composer', { detail: { replyTo: commentsPost } }),
    );
  }

  function handleNewComment(e: Event) {
    const newPost = (e as CustomEvent<Post>).detail;
    if (!newPost || !commentsPost) return;
    const belongsHere =
      newPost.parent_id === commentsPost.id ||
      newPost.root_id === commentsPost.id ||
      commentsDescendants.some((d) => d.id === newPost.parent_id);
    if (belongsHere && !commentsDescendants.some((d) => d.id === newPost.id)) {
      commentsDescendants = [...commentsDescendants, newPost];
    }
  }

  onMount(() => {
    try {
      const v = localStorage.getItem(AUTOPLAY_KEY);
      if (v !== null) autoplay = v === '1';
      muted = localStorage.getItem(MUTED_KEY) !== '0';
      showFederated = localStorage.getItem(FEDERATED_KEY) === '1';
      showAllAspect = localStorage.getItem(ASPECT_KEY) === '1';
      const savedSort = localStorage.getItem(SORT_KEY);
      if (savedSort && (SORT_VALUES as readonly string[]).includes(savedSort)) {
        sort = savedSort as (typeof SORT_VALUES)[number];
      }
    } catch {
      /* ignore */
    }
    loadStreams();
    window.addEventListener('new-post', handleNewComment);
    return () => window.removeEventListener('new-post', handleNewComment);
  });
</script>

<svelte:head>
  <title>Streams - {$instanceName}</title>
</svelte:head>

<div class="streams-page">
  <!-- On-demand overlays (opened from the controls on the clip), so the feed
       stays immersive and full-bleed instead of stacking rows above it. -->
  {#if searchOpen}
    <div class="streams-overlay-bar">
      <div class="streams-search">
        <svg class="streams-search-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <circle cx="11" cy="11" r="8" /><line x1="21" y1="21" x2="16.65" y2="16.65" />
        </svg>
        <!-- svelte-ignore a11y_autofocus -->
        <input
          type="search"
          class="streams-search-input"
          placeholder="Search clips or #tags…"
          aria-label="Search streams"
          autofocus
          bind:value={search}
          oninput={onSearchInput}
        />
      </div>
      <button type="button" class="streams-overlay-close" aria-label="Close search" onclick={() => (searchOpen = false)}>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
      </button>
    </div>
  {/if}

  {#if sortOpen}
    <div class="streams-sort-menu" role="group" aria-label="Sort clips by">
      {#each SORTS as s (s.value)}
        <button
          type="button"
          class="sort-chip"
          class:on={sort === s.value}
          aria-pressed={sort === s.value}
          onclick={() => { changeSort(s.value); sortOpen = false; }}
        >
          {s.label}
        </button>
      {/each}
    </div>
  {/if}

  {#if loading}
    <div class="streams-feed" aria-hidden="true">
      <div class="stream-skeleton"></div>
    </div>
  {:else if error}
    <div class="state">
      <p class="state-text">{error}</p>
      <button type="button" class="btn btn-outline" onclick={loadStreams}>Retry</button>
    </div>
  {:else if streams.length === 0}
    <div class="state">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--color-text-tertiary)" stroke-width="1.5" aria-hidden="true">
        <rect x="3" y="5" width="18" height="14" rx="2" /><path d="M10 13l4 2-4 2z" /><path d="M8 5v4M13 5v4M18 5v4" />
      </svg>
      <p class="state-text">No streams yet</p>
      <p class="state-sub">Video clips will appear here.</p>
    </div>
  {:else}
    <div class="streams-feed" bind:this={feedEl} onscroll={maybeLoadMore}>
      {#each streams as post (post.id)}
        {@const v = streamVideo(post)}
        {#if v}
          <StreamPlayer
            {post}
            video={v}
            {muted}
            {autoplay}
            federated={showFederated}
            allAspect={showAllAspect}
            onmutetoggle={toggleMuted}
            onautoplaytoggle={toggleAutoplay}
            onfederatedtoggle={toggleFederated}
            onaspecttoggle={toggleAspect}
            onsearch={() => { sortOpen = false; searchOpen = !searchOpen; }}
            onsort={() => { searchOpen = false; sortOpen = !sortOpen; }}
            oncomment={() => openComments(post)}
            onview={(w, t, c, r) => reportView(post.id, w, t, c, r)}
          />
        {/if}
      {/each}
      {#if loadingMore}
        <div class="streams-more" aria-live="polite">
          <span class="streams-more-spinner" aria-hidden="true"></span>
          <span>{$t('streams.loading_more')}</span>
        </div>
      {/if}
    </div>
  {/if}
</div>

<Modal open={commentsOpen} title="Comments" onclose={closeComments}>
  <div class="comments-sheet">
    <button type="button" class="comments-add" onclick={addComment}>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M12 5v14M5 12h14" />
      </svg>
      Add a comment
    </button>

    {#if commentsLoading}
      <p class="comments-status">Loading comments…</p>
    {:else if commentsError}
      <p class="comments-status">{commentsError}</p>
    {:else if !commentsPost || commentsDescendants.length === 0}
      <p class="comments-status">No comments yet. Be the first to comment.</p>
    {:else}
      <ThreadedReplies descendants={commentsDescendants} rootPostId={commentsPost.id} />
    {/if}
  </div>
</Modal>

<style>
  /* AppLayout's <main> already pads the content area (see AppLayout.svelte),
     so sizing this page to the raw viewport overflowed it — the page scrolled
     as a whole and the clip's bottom hid under the fixed BottomTabs bar.
     Cancel that padding exactly so the page fits the viewport and the feed
     scroll-snaps INTERNALLY, one clip at a time, with the nav always visible.
     Desktop <main>: top = header-height + space-8, bottom = space-12. */
  .streams-page {
    position: relative;
    display: flex;
    flex-direction: column;
    height: calc(
      100dvh - var(--header-height, 60px) - var(--space-8) - var(--space-12)
    );
    min-height: 0;
  }

  /* Mobile <main>: top = header-height + space-4,
     bottom = header-height (BottomTabs) + safe-area + space-2. */
  @media (max-width: 768px) {
    .streams-page {
      height: calc(
        100dvh - var(--header-height, 60px) - var(--space-4) -
          var(--header-height, 60px) - env(safe-area-inset-bottom, 0px) -
          var(--space-2)
      );
    }
  }

  /* --- On-demand overlays (opened from the on-clip controls) --- */
  .streams-overlay-bar {
    position: absolute;
    inset-block-start: var(--space-2);
    inset-inline: var(--space-2);
    z-index: 5;
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2);
    border-radius: var(--radius-full);
    background: color-mix(in oklab, var(--color-surface-base, #fff) 82%, transparent);
    backdrop-filter: saturate(1.4) blur(10px);
    -webkit-backdrop-filter: saturate(1.4) blur(10px);
    box-shadow: 0 6px 20px rgba(0, 0, 0, 0.18);
  }

  .streams-overlay-close {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    flex: 0 0 auto;
    padding: 0;
    border: none;
    border-radius: 50%;
    background: transparent;
    color: var(--color-text-secondary);
    cursor: pointer;
  }

  .streams-overlay-close:hover {
    color: var(--color-text);
    background: var(--color-surface-container-high);
  }

  .streams-sort-menu {
    position: absolute;
    inset-block-start: var(--space-2);
    inset-inline-end: var(--space-2);
    z-index: 5;
    display: flex;
    gap: var(--space-1);
    padding: var(--space-2);
    border-radius: var(--radius-full);
    background: color-mix(in oklab, var(--color-surface-base, #fff) 82%, transparent);
    backdrop-filter: saturate(1.4) blur(10px);
    -webkit-backdrop-filter: saturate(1.4) blur(10px);
    box-shadow: 0 6px 20px rgba(0, 0, 0, 0.18);
  }

  .streams-search {
    position: relative;
    flex: 1 1 auto;
    min-width: 0;
  }

  .streams-search-icon {
    position: absolute;
    inset-block-start: 50%;
    inset-inline-start: var(--space-3);
    transform: translateY(-50%);
    color: var(--color-text-tertiary);
    pointer-events: none;
  }

  .streams-search-input {
    width: 100%;
    padding: var(--space-2) var(--space-3) var(--space-2) calc(var(--space-3) + 24px);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full);
    background: var(--color-surface-container);
    color: var(--color-text);
    font-size: var(--text-sm);
  }

  .streams-search-input:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .sort-chip {
    padding: var(--space-1) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full);
    background: transparent;
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
    font-weight: 500;
    cursor: pointer;
    transition: background 150ms ease, color 150ms ease, border-color 150ms ease;
  }

  .sort-chip:hover {
    color: var(--color-text);
    border-color: var(--color-text-tertiary);
  }

  .sort-chip.on {
    background: var(--color-primary-soft, rgba(var(--color-primary-rgb), 0.12));
    color: var(--color-primary);
    border-color: transparent;
  }

  /* Vertical, snap-scrolling streams feed. */
  .streams-feed {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    scroll-snap-type: y mandatory;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    scrollbar-width: none;
  }

  .streams-feed::-webkit-scrollbar {
    display: none;
  }

  /* "Loading more" row at the tail of the feed. Not a snap target, so it
     doesn't count as a clip when the viewer flicks to the end. */
  .streams-more {
    flex: 0 0 auto;
    scroll-snap-align: none;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    padding: var(--space-4);
    color: var(--color-text-secondary);
    font-size: var(--text-sm, 0.875rem);
  }

  .streams-more-spinner {
    width: 18px;
    height: 18px;
    border-radius: 50%;
    border: 2px solid var(--color-border);
    border-top-color: var(--color-primary);
    animation: streams-spin 0.7s linear infinite;
  }

  @keyframes streams-spin {
    to {
      transform: rotate(360deg);
    }
  }

  .stream-skeleton {
    flex: 0 0 100%;
    height: 100%;
    background: var(--color-surface-container);
    border-radius: var(--radius-lg);
  }

  .state {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    text-align: center;
  }

  .state-text {
    color: var(--color-text);
    font-weight: 600;
    margin: 0;
  }

  .state-sub {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    margin: 0;
  }

  .btn-outline {
    display: inline-flex;
    align-items: center;
    padding: var(--space-2) var(--space-3);
    background: transparent;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    color: var(--color-text-secondary);
    cursor: pointer;
    font: inherit;
    font-size: var(--text-sm);
  }

  .comments-sheet {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .comments-status {
    color: var(--color-text-secondary);
    text-align: center;
    padding: var(--space-4);
  }

  .comments-add {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    width: 100%;
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full);
    background: transparent;
    color: var(--color-text-secondary);
    font: inherit;
    font-size: var(--text-sm);
    font-weight: 500;
    cursor: pointer;
  }

  .comments-add:hover {
    color: var(--color-text);
    border-color: var(--color-text-tertiary);
  }
</style>
