// In-memory snapshots of the Explore feeds (Local / Global / Trending) for the
// current session, one per tab. Mirrors home-feed-cache.ts.
//
// The Explore page re-mounts whenever the user navigates away and back (e.g.
// opens a post). Without this, the feed re-fetches and the scroll position is
// lost, and Trending may even have re-ranked underneath them. Hydrating from
// the snapshot keeps the same posts at the same DOM heights, so scroll restores
// cleanly (#53). Session-scoped only: dropped on a full reload.

import type { TimelineCache, TimelineSnapshot } from '$lib/components/feed/TimelineFeed.svelte';

// Past this a feed is worth reloading: a back-nav restores the place, but someone
// returning to a tab much later should see what's current.
const MAX_AGE_MS = 10 * 60 * 1000;

const snapshots = new Map<string, { snap: TimelineSnapshot; savedAt: number }>();

export function exploreFeedCache(tabId: string): TimelineCache {
  return {
    read: () => {
      const entry = snapshots.get(tabId);
      return entry && Date.now() - entry.savedAt < MAX_AGE_MS ? entry.snap : null;
    },
    write: (snap) => {
      snapshots.set(tabId, { snap, savedAt: Date.now() });
    },
  };
}
