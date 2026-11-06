import type { Post } from '$lib/api/types.js';

/**
 * Reactive state + logic for a paginated post feed — the single
 * load → dedupe → cursor → paginate engine shared by EVERY feed
 * surface (home/explore via TimelineFeed, profile, group, page, tags,
 * bookmarks, lists). Each surface differs only in what it fetches and
 * which extra features (real-time, banners, scroll restore) it layers
 * on top; the pagination plumbing lives here, once.
 *
 * `fetchPage` may return either shape:
 *   - `Post[]` — the engine derives the next cursor from the LAST post's
 *     id and treats a full page (`>= pageSize`) as "there may be more".
 *   - `{ items, nextCursor }` — the server hands back an explicit cursor
 *     (e.g. bookmarks / lists `next_cursor`); `hasMore` is `nextCursor != null`.
 *
 * Usage (in a .svelte component):
 *   const feed = createEntityFeed((cursor) => getGroupTimeline(id, cursor ?? undefined));
 *   onMount(() => feed.reset());
 *   <FeedList posts={feed.posts} loading={feed.loading}
 *             hasMore={feed.hasMore} onloadmore={feed.loadMore} />
 *
 * The optimistic mutators (prepend / replaceById / updateById / set)
 * let callers layer composer-driven and streamed updates on top. Pass
 * `opts.initial` to hydrate from a cache (scroll restoration) and
 * `opts.onChange` to persist after every load/mutation.
 */
export interface EntityFeed {
  readonly posts: Post[];
  readonly loading: boolean;
  readonly hasMore: boolean;
  /** The cursor for the next page — exposed so callers can persist it. */
  readonly cursor: string | null;
  /** Fetch the first page (clears any existing posts). */
  reset: () => Promise<void>;
  /** Append the next page. No-op while loading or when exhausted. */
  loadMore: () => Promise<void>;
  /** Replace the whole array (e.g. merging pinned posts, banner merge). */
  set: (posts: Post[]) => void;
  /** Prepend an optimistic post (deduped). */
  prepend: (post: Post) => void;
  /** Swap an optimistic post id for the confirmed post (dedupe-safe). */
  replaceById: (oldId: string, post: Post) => void;
  /** Replace an already-present post in place (edits). */
  updateById: (post: Post) => void;
}

type Page = Post[] | { items: Post[]; nextCursor: string | null };

export interface EntityFeedOptions {
  /** Seed initial state (e.g. from a scroll-restoration cache). */
  initial?: { posts: Post[]; cursor: string | null; hasMore: boolean } | null;
  /** Start in the loading state (so a skeleton shows from first paint when
   *  the caller will `reset()` in onMount rather than fetching during SSR). */
  initialLoading?: boolean;
  /** Called after every load and every mutation (for persistence). */
  onChange?: () => void;
  /** Called when a load throws (e.g. to surface a toast). Existing posts
   *  are left intact either way. */
  onError?: (error: unknown) => void;
}

const MAX_EMPTY_PAGES = 3;

export function createEntityFeed(
  fetchPage: (cursor: string | null) => Promise<Page>,
  pageSize = 20,
  opts: EntityFeedOptions = {},
): EntityFeed {
  const initial = opts.initial ?? null;
  let posts = $state<Post[]>(initial?.posts ?? []);
  let loading = $state(opts.initialLoading ?? false);
  let hasMore = $state(initial?.hasMore ?? true);
  // Internal only — no reactivity needed, it's read/written inside load().
  let cursor: string | null = initial?.cursor ?? null;

  const changed = () => opts.onChange?.();

  async function load(reset: boolean) {
    // Guard paginated loads against overlap / exhaustion; a reset always
    // proceeds (it re-establishes state from scratch).
    if (!reset && (loading || !hasMore)) return;
    if (reset) {
      posts = [];
      cursor = null;
      hasMore = true;
    }
    loading = true;
    try {
      // A page of nothing but posts we already hold adds no height, so the
      // scroll sentinel never fires again and the feed would stall. Fetch on
      // from it, a bounded number of times.
      for (let attempt = 0; attempt < MAX_EMPTY_PAGES; attempt++) {
        const page = await fetchPage(cursor);
        const items = Array.isArray(page) ? page : page.items;
        let added = items.length;

        if (reset) {
          posts = items;
        } else {
          // The boundary post can repeat across pages — dedupe on append.
          const seen = new Set(posts.map((p) => p.id));
          const fresh = items.filter((p) => !seen.has(p.id));
          added = fresh.length;
          posts = [...posts, ...fresh];
        }

        if (Array.isArray(page)) {
          // Cursor must be a POST id — reach through a boost entry at the
          // tail so the next page's row-tuple WHERE anchors to a real row.
          const last: any = items.length > 0 ? items[items.length - 1] : null;
          cursor = last?.type === 'boost' ? (last.post?.id ?? null) : (last?.id ?? null);
          hasMore = items.length >= pageSize;
        } else {
          // Server-provided cursor — trust it verbatim for both fields.
          cursor = page.nextCursor;
          hasMore = page.nextCursor != null;
        }

        if (added > 0 || !hasMore) break;
      }
      changed();
    } catch (error) {
      // Leave the existing posts in place; let the caller surface it.
      opts.onError?.(error);
    } finally {
      loading = false;
    }
  }

  return {
    get posts() {
      return posts;
    },
    get loading() {
      return loading;
    },
    get hasMore() {
      return hasMore;
    },
    get cursor() {
      return cursor;
    },
    reset: () => load(true),
    loadMore: () => load(false),
    set: (v: Post[]) => {
      posts = v;
      changed();
    },
    prepend: (post: Post) => {
      if (!posts.some((p) => p.id === post.id)) {
        posts = [post, ...posts];
        changed();
      }
    },
    replaceById: (oldId: string, post: Post) => {
      const realPresent = posts.some((p) => p.id === post.id && p.id !== oldId);
      if (realPresent) posts = posts.filter((p) => p.id !== oldId);
      else posts = posts.map((p) => (p.id === oldId ? post : p));
      changed();
    },
    updateById: (post: Post) => {
      posts = posts.map((p) => (p.id === post.id ? post : p));
      changed();
    },
  };
}
