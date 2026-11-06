<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import type { Post, FeedEntry, BoostEntry } from '$lib/api/types.js';
  import DisplayName from '$lib/components/DisplayName.svelte';
  import PostCard from '$lib/components/post/PostCard.svelte';
  import SkeletonPost from './SkeletonPost.svelte';
  import { matchFilters } from '$lib/stores/content-filters.js';
  import { setFeedPosts, clearFeedPosts } from '$lib/stores/focused-post.js';
  import { t } from '$lib/stores/i18n.js';

  function isBoostEntry(entry: FeedEntry): entry is BoostEntry {
    return entry.type === 'boost';
  }

  let {
    posts = [],
    loading = false,
    hasMore = true,
    compact = false,
    emptyMessage = '',
    emptyAction,
    collapseAuthorRunsAfter = 0,
    filterContext = 'home',
    viewerContext = null,
    removeOnEvents = [],
    onloadmore,
  }: {
    posts?: FeedEntry[];
    loading?: boolean;
    hasMore?: boolean;
    compact?: boolean;
    emptyMessage?: string;
    emptyAction?: { label: string; onclick: () => void };
    /**
     * After this many consecutive posts by one author, fold the rest of the
     * run behind a "show more" button, so one prolific account can't push
     * everyone else off the feed. 0 keeps every post.
     */
    collapseAuthorRunsAfter?: number;
    filterContext?: string;
    // Threaded through to PostCard so the pin badge / Unpin entry are
    // scope-correct. See PostCard.viewerContext.
    viewerContext?: 'profile' | 'group' | 'page' | null;
    /**
     * Additional window events that should trigger the
     * post-disolve animation (besides the always-on `post-deleted`).
     * Used by /bookmarks to react to `bookmark-removed`.
     */
    removeOnEvents?: string[];
    onloadmore?: () => void;
  } = $props();

  let sentinelEl: HTMLDivElement | undefined = $state();
  let newPostsCount = $state(0);
  let showStagger = $state(true);
  let newIds = $state(new Set<string>());
  let deletingIds = $state(new Set<string>());
  let hiddenIds = $state(new Set<string>());

  // --- Windowing: bound the mounted-card count on long feeds ----------------
  //
  // The feed appends on infinite scroll and never unmounts, so the live DOM
  // grew without limit — worst on low-memory mobile GPUs (the growth that #108
  // was masking with `content-visibility`). We keep the keyed {#each} over
  // every entry (so ids, dedupe, animations and keyboard order are untouched)
  // but swap a card that has scrolled FAR ABOVE the viewport for a placeholder
  // of its measured height. Only above-viewport cards are detached: they've
  // been seen, so their media is loaded and the measured height is exact, so
  // the swap never shifts scroll. Cards near or below the viewport always
  // render in full (no unmeasured/lazy card is ever collapsed). Windowing only
  // engages for coarse pointers; desktop keeps every card mounted (no memory
  // pressure, and the j/k cursor walks a fully rendered list) — behaviour there
  // is byte-for-byte unchanged.
  const KEEPALIVE_ABOVE = 1200; // px above the viewport kept fully rendered

  let detached = $state(new Set<string>());
  const measuredHeights = new Map<string, number>(); // id -> last measured px
  const slotEls = new Map<string, HTMLElement>(); // id -> live post-slot node
  let windowObserver: IntersectionObserver | undefined;
  let windowingChecked = false;
  let windowingEnabled = false;

  function ensureWindowObserver() {
    if (windowingChecked) return;
    windowingChecked = true;
    if (typeof IntersectionObserver === 'undefined' || typeof matchMedia === 'undefined') return;
    windowingEnabled = matchMedia('(pointer: coarse)').matches;
    if (!windowingEnabled) return;
    windowObserver = new IntersectionObserver(onWindowIntersect, {
      rootMargin: `${KEEPALIVE_ABOVE}px 0px 0px 0px`,
    });
  }

  function onWindowIntersect(entries: IntersectionObserverEntry[]) {
    let changed = false;
    const next = new Set(detached);
    for (const e of entries) {
      const id = (e.target as HTMLElement).dataset.postId;
      if (!id) continue;
      if (e.isIntersecting) {
        // Back inside the keep-alive window: render the card again.
        if (next.has(id)) {
          next.delete(id);
          changed = true;
        }
      } else if (e.rootBounds && e.boundingClientRect.bottom <= e.rootBounds.top) {
        // Left the window off the TOP (scrolled past). Capture the live
        // card's height, then collapse it to a placeholder. Never detach
        // with a zero height — a collapsed card would jump scroll and
        // bounce straight back into view.
        const el = slotEls.get(id);
        const h = el ? el.offsetHeight : (measuredHeights.get(id) ?? 0);
        if (h > 0 && !next.has(id)) {
          measuredHeights.set(id, h);
          next.add(id);
          changed = true;
        }
      }
      // Off the bottom: leave fully rendered (bounded by pagination).
    }
    if (changed) detached = next;
  }

  function observeItem(node: HTMLElement) {
    ensureWindowObserver();
    windowObserver?.observe(node);
    return {
      destroy() {
        windowObserver?.unobserve(node);
      },
    };
  }

  function registerSlot(node: HTMLElement, id: string) {
    slotEls.set(id, node);
    return {
      destroy() {
        slotEls.delete(id);
      },
    };
  }

  function placeholderHeight(id: string): number {
    return measuredHeights.get(id) ?? 0;
  }

  // Posts someone has chosen to unfold. Tracked per post rather than per run,
  // so a new post arriving at the top doesn't fold a run back up.
  let expandedIds = $state(new Set<string>());

  let filteredPosts: FeedEntry[] = $derived(
    (() => {
      // Dedupe by id at the render layer. Multiple call sites push
      // into `posts` (pagination append, optimistic insert, SSE
      // prepend, queue flush, …) and any of them slipping a duplicate
      // through used to crash the keyed each block with
      // `each_key_duplicate`. Belt-and-braces dedupe here is cheap
      // and guarantees the render never sees a repeat.
      const seen = new Set<string>();
      const result: FeedEntry[] = [];
      for (const p of posts) {
        if (seen.has(p.id)) continue;
        if (hiddenIds.has(p.id)) continue;
        const post = isBoostEntry(p) ? p.post : p;
        const matched = matchFilters(post.content, post.spoiler_text, filterContext);
        if (matched && matched.action === 'hide') continue;
        seen.add(p.id);
        result.push(p);
      }
      return result;
    })(),
  );

  type FoldedRun = { ids: string[]; name: string };

  // `folded` is keyed by the last post shown before the run's hidden part, which
  // is where its "show more" button goes.
  let folding = $derived(
    (() => {
      const shown: FeedEntry[] = [];
      const folded = new Map<string, FoldedRun>();
      if (collapseAuthorRunsAfter <= 0) return { shown: filteredPosts, folded };

      let author: string | undefined;
      let runLength = 0;
      let lastShownId = '';
      for (const entry of filteredPosts) {
        const account = (isBoostEntry(entry) ? entry.post : entry).account;
        const authorId = account?.id ?? entry.id;
        runLength = authorId === author ? runLength + 1 : 1;
        author = authorId;

        if (runLength <= collapseAuthorRunsAfter || expandedIds.has(entry.id)) {
          shown.push(entry);
          lastShownId = entry.id;
        } else {
          const run = folded.get(lastShownId) ?? {
            ids: [],
            name: account?.display_name || account?.handle || '',
          };
          run.ids.push(entry.id);
          folded.set(lastShownId, run);
        }
      }
      return { shown, folded };
    })(),
  );

  let visiblePosts: FeedEntry[] = $derived(folding.shown);

  function unfold(run: FoldedRun) {
    expandedIds = new Set([...expandedIds, ...run.ids]);
  }

  // Folding can leave a loaded page adding little or no height. The scroll
  // observer only fires when the sentinel crosses into view, so if it never left
  // the feed would stop here. Keep loading while it's still in range.
  $effect(() => {
    if (collapseAuthorRunsAfter <= 0 || loading || !hasMore || !sentinelEl || !onloadmore) return;
    void visiblePosts.length;
    const load = onloadmore;
    const frame = requestAnimationFrame(() => {
      if (sentinelEl && sentinelEl.getBoundingClientRect().top < window.innerHeight + 200) load();
    });
    return () => cancelAnimationFrame(frame);
  });

  // Non-reactive tracker — avoids $effect infinite loop
  let _knownIds = new Set<string>();

  $effect(() => {
    const currentPosts = posts;
    const fresh = new Set<string>();
    for (const p of currentPosts) {
      if (!_knownIds.has(p.id)) {
        fresh.add(p.id);
      }
    }

    // If most posts are new (tab switch / full reload), re-trigger stagger
    const isFullReplace = fresh.size > 0 && fresh.size >= currentPosts.length * 0.8;

    _knownIds = new Set(currentPosts.map(p => p.id));

    if (isFullReplace) {
      showStagger = true;
      setTimeout(() => { showStagger = false; }, 800);
    } else if (fresh.size > 0 && !showStagger) {
      newIds = fresh;
      setTimeout(() => { newIds = new Set(); }, 500);
    }
  });

  // IntersectionObserver for infinite scroll
  onMount(() => {
    if (!sentinelEl) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && hasMore && !loading && onloadmore) {
          onloadmore();
        }
      },
      { rootMargin: '200px' }
    );

    observer.observe(sentinelEl);

    // Disable stagger after initial load
    setTimeout(() => { showStagger = false; }, 800);

    return () => observer.disconnect();
  });

  // Listen for new posts from SSE
  onMount(() => {
    function handleNewPost() {
      newPostsCount += 1;
    }

    function handlePostDeleted(e: Event) {
      const detail = (e as CustomEvent).detail;
      const id = detail?.id;
      if (!id || !posts.some(p => p.id === id)) return;

      // Animate out, then hide permanently
      deletingIds = new Set([...deletingIds, id]);

      setTimeout(() => {
        hiddenIds = new Set([...hiddenIds, id]);
        deletingIds = new Set([...deletingIds].filter(x => x !== id));
      }, 400);
    }

    window.addEventListener('feed-new-post', handleNewPost);
    window.addEventListener('post-deleted', handlePostDeleted);
    for (const ev of removeOnEvents) {
      window.addEventListener(ev, handlePostDeleted);
    }
    return () => {
      window.removeEventListener('feed-new-post', handleNewPost);
      window.removeEventListener('post-deleted', handlePostDeleted);
      for (const ev of removeOnEvents) {
        window.removeEventListener(ev, handlePostDeleted);
      }
    };
  });

  function showNewPosts() {
    // Trigger a refresh of the feed
    window.dispatchEvent(new CustomEvent('feed-refresh'));
    newPostsCount = 0;
  }

  // Publish the rendered post ids to the focused-post store so j/k
  // shortcuts can walk the feed in render order. Boost rows surface
  // the original post's id, matching what the keyboard cursor would
  // navigate to.
  $effect(() => {
    const ids: string[] = [];
    for (const entry of visiblePosts) {
      const post = isBoostEntry(entry) ? entry.post : (entry as Post);
      if (post?.id) ids.push(post.id);
    }
    setFeedPosts(ids);
  });

  onDestroy(() => {
    clearFeedPosts();
    windowObserver?.disconnect();
  });
</script>

<div class="feed-list" role="feed" aria-label={$t('feed.post_feed')}>
  {#if newPostsCount > 0}
    <button
      type="button"
      class="new-posts-pill"
      onclick={showNewPosts}
    >
      {$t('feed.show_new_posts', { count: newPostsCount })}
    </button>
  {/if}

  {#if visiblePosts.length === 0 && !loading}
    <div class="feed-empty">
      <div class="feed-empty-icon" aria-hidden="true">
        <svg viewBox="0 0 24 24" width="30" height="30" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
          <path d="M12 4l1.7 4.6L18 10.3l-4.3 1.7L12 16.6l-1.7-4.6L6 10.3l4.3-1.7L12 4Z" />
          <path d="M18.5 14l.9 2.4 2.4.9-2.4.9-.9 2.4-.9-2.4-2.4-.9 2.4-.9.9-2.4Z" />
        </svg>
      </div>
      <h2 class="feed-empty-title">{$t('feed.empty_title')}</h2>
      <p class="feed-empty-text">{emptyMessage || $t('feed.no_posts')}</p>
      {#if emptyAction}
        <button type="button" class="feed-empty-action" onclick={emptyAction.onclick}>
          {emptyAction.label}
        </button>
      {/if}
    </div>
  {/if}

  {#each visiblePosts as entry, i (entry.id)}
    {@const boost = isBoostEntry(entry) ? entry : null}
    {@const post = boost ? boost.post : entry as Post}
    {#if post && post.content !== undefined}
      <!-- data-post-anchor lives on this wrapper, not on PostCard: windowing
           unmounts the card, and the j/k scroll target has to outlive that or
           `scrollPostIntoView` finds nothing and silently no-ops. Note the two
           ids differ on a boost — `data-post-id` keys the windowing observer by
           feed entry, while the anchor must carry the original post id, which
           is what `setFeedPosts` publishes to the focused-post store. -->
      <div
        class="feed-item"
        data-post-id={entry.id}
        data-post-anchor={post.id}
        use:observeItem
        style={showStagger ? `animation-delay: ${i * 60}ms` : ''}
        class:stagger={showStagger}
        class:feed-item-new={newIds.has(entry.id)}
        class:feed-item-deleting={deletingIds.has(entry.id)}
      >
        {#if boost}
          <div class="boost-label">
            <span class="material-symbols-outlined boost-icon">cached</span>
            <span><DisplayName name={boost.account?.display_name || boost.account?.handle || 'Someone'} emojis={boost.account?.emojis} /> boosted</span>
          </div>
        {/if}
        {#if detached.has(entry.id)}
          <!-- Windowed out: card scrolled far above the viewport. Reserve its
               measured height so scroll position and total height are exact;
               it re-mounts (below) as it scrolls back into the keep-alive band. -->
          <div class="post-placeholder" style="height: {placeholderHeight(entry.id)}px" aria-hidden="true"></div>
        {:else}
          <div class="post-slot" use:registerSlot={entry.id}>
            <PostCard {post} {compact} {filterContext} {viewerContext} />
          </div>
        {/if}
      </div>
      {#if folding.folded.has(entry.id)}
        {@const run = folding.folded.get(entry.id)!}
        <button type="button" class="feed-unfold" onclick={() => unfold(run)}>
          {$t('feed.show_more_from', { count: run.ids.length, name: run.name })}
        </button>
      {/if}
    {/if}
  {/each}

  {#if loading && visiblePosts.length === 0}
    <div class="feed-loading">
      <SkeletonPost />
      <SkeletonPost />
      <SkeletonPost />
    </div>
  {:else if loading}
    <!-- Pagination spinner: shown when loading more on top of an
         already-rendered feed. Three full skeletons would be visually
         loud at the bottom of the list, so we use a single inline
         spinner with a "Loading more" label so the user knows the
         scroll is doing something. -->
    <div class="feed-loadmore" role="status" aria-live="polite">
      <span class="feed-loadmore-spinner" aria-hidden="true"></span>
      <span class="feed-loadmore-label">{$t('feed.loading_more')}</span>
    </div>
  {/if}

  <div bind:this={sentinelEl} class="feed-sentinel" aria-hidden="true"></div>
</div>

<style>
  .feed-list {
    display: flex;
    flex-direction: column;
    gap: 28px;
    max-width: var(--feed-max-width);
    width: 100%;
    margin: 0 auto;
  }

  /* Reserves the exact height of a windowed-out card (see observeItem) so
     detaching a far-above card leaves scroll position and total height
     untouched. Never painted content, just space. */
  .post-placeholder {
    width: 100%;
  }

  .boost-label {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 24px;
    padding-block-end: 4px;
    font-size: 0.875rem;
    color: var(--color-text-secondary);
    font-weight: 500;
  }

  .boost-icon {
    font-size: 16px;
    color: var(--color-primary);
  }

  .new-posts-pill {
    position: sticky;
    inset-block-start: var(--header-height);
    align-self: center;
    padding: 8px 20px;
    background: var(--color-primary);
    color: var(--color-on-primary);
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    box-shadow: 0 4px 12px rgba(var(--color-primary-rgb), 0.25);
    z-index: var(--z-sticky);
    transition: background-color 150ms ease, transform 150ms ease;
    animation: pill-enter 0.3s ease;
  }

  .new-posts-pill:hover {
    background: var(--color-primary-hover);
    transform: scale(1.02);
  }

  @keyframes pill-enter {
    from {
      opacity: 0;
      transform: translateY(-10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .feed-item.stagger {
    animation: slide-up 0.3s ease both;
  }

  @keyframes slide-up {
    from {
      opacity: 0;
      transform: translateY(16px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  /* New post fade-in from top */
  .feed-item-new {
    animation: new-post-enter 0.4s ease both;
  }

  @keyframes new-post-enter {
    from {
      opacity: 0;
      transform: translateY(-20px) scale(0.98);
    }
    to {
      opacity: 1;
      transform: translateY(0) scale(1);
    }
  }

  /* Dissolve out animation for deleted posts */
  .feed-item-deleting {
    animation: post-dissolve 0.4s ease forwards;
    pointer-events: none;
  }

  @keyframes post-dissolve {
    0% {
      opacity: 1;
      transform: scale(1);
      filter: blur(0);
      max-height: 600px;
    }
    40% {
      opacity: 0.5;
      transform: scale(0.97);
      filter: blur(1px);
    }
    70% {
      opacity: 0;
      transform: scale(0.94);
      filter: blur(3px);
      max-height: 600px;
    }
    100% {
      opacity: 0;
      transform: scale(0.9);
      filter: blur(4px);
      max-height: 0;
      margin: 0;
      padding: 0;
      overflow: hidden;
    }
  }

  .feed-empty {
    padding: 72px 24px;
    text-align: center;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .feed-empty-icon {
    width: 72px;
    height: 72px;
    border-radius: var(--radius-full);
    display: grid;
    place-items: center;
    color: var(--color-primary);
    background: var(--color-secondary-container);
    box-shadow: 0 8px 24px rgba(var(--color-primary-rgb), 0.12);
    margin-block-end: var(--space-5);
  }

  .feed-empty-title {
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .feed-unfold {
    align-self: center;
    margin-block-start: -12px;
    padding: 6px 14px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full);
    background: transparent;
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
    font-weight: 600;
    cursor: pointer;
  }

  .feed-unfold:hover {
    background: var(--color-surface-hover, rgba(0, 0, 0, 0.06));
  }

  /* A taller tap target on touch, without changing how the button looks. */
  @media (pointer: coarse) {
    .feed-unfold {
      position: relative;
    }

    .feed-unfold::after {
      content: '';
      position: absolute;
      inset: -8px 0;
    }
  }

  .feed-empty-action {
    margin-block-start: var(--space-3);
    padding: var(--space-2) var(--space-4);
    border: none;
    border-radius: var(--radius-full);
    background: var(--color-primary);
    color: var(--color-on-primary, #fff);
    font-weight: 600;
    cursor: pointer;
  }

  .feed-empty-text {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    max-width: 320px;
    line-height: 1.55;
  }

  .feed-loading {
    display: flex;
    flex-direction: column;
    gap: 28px;
  }

  .feed-sentinel {
    height: 1px;
  }

  .feed-loadmore {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    padding: 16px 0 8px;
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
  }

  .feed-loadmore-spinner {
    width: 18px;
    height: 18px;
    border-radius: 50%;
    border: 2px solid var(--color-border);
    border-top-color: var(--color-primary);
    animation: feed-loadmore-spin 0.8s linear infinite;
  }

  @keyframes feed-loadmore-spin {
    to { transform: rotate(360deg); }
  }
</style>
