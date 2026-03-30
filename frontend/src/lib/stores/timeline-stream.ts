import { writable, derived } from 'svelte/store';
import type { Post } from '$lib/api/types.js';
import { browser } from '$app/environment';

const MAX_QUEUE_SIZE = 30;
const TRUNCATE_TO = 60;
const TRUNCATE_THRESHOLD = 120;

interface TimelineStreamState {
  queued: Post[];
  connected: boolean;
}

const state = writable<TimelineStreamState>({
  queued: [],
  connected: false,
});

export const queuedPosts = derived(state, ($s) => $s.queued);
export const queuedCount = derived(state, ($s) => $s.queued.length);
export const isStreamConnected = derived(state, ($s) => $s.connected);

let eventSource: EventSource | null = null;
let isAtTop = true;

export function setAtTop(atTop: boolean) {
  isAtTop = atTop;
}

/**
 * Flush queued posts into the timeline.
 * Returns the queued posts and clears the queue.
 */
export function flushQueue(): Post[] {
  let flushed: Post[] = [];
  state.update((s) => {
    flushed = s.queued;
    return { ...s, queued: [] };
  });
  return flushed;
}

/**
 * Connect to the streaming endpoint for home timeline updates.
 */
export function connectTimelineStream(apiBase: string, token: string): void {
  if (!browser) return;
  disconnectTimelineStream();

  try {
    const url = `${apiBase}/api/v1/streaming/user?access_token=${encodeURIComponent(token)}&stream=home`;
    eventSource = new EventSource(url);

    state.update((s) => ({ ...s, connected: true }));

    eventSource.addEventListener('update', (event) => {
      try {
        const post: Post = JSON.parse(event.data);

        if (isAtTop) {
          // Dispatch directly to the feed
          window.dispatchEvent(new CustomEvent('timeline-update', { detail: post }));
        } else {
          // Queue it
          state.update((s) => {
            const queued = [post, ...s.queued].slice(0, MAX_QUEUE_SIZE);
            return { ...s, queued };
          });
        }
      } catch {
        // Ignore malformed events
      }
    });

    eventSource.addEventListener('status.update', (event) => {
      try {
        const post: Post = JSON.parse(event.data);
        window.dispatchEvent(new CustomEvent('timeline-status-update', { detail: post }));
      } catch {
        // Ignore
      }
    });

    eventSource.addEventListener('delete', (event) => {
      try {
        const id = event.data;
        window.dispatchEvent(new CustomEvent('post-deleted', { detail: { id } }));
      } catch {
        // Ignore
      }
    });

    eventSource.onerror = () => {
      state.update((s) => ({ ...s, connected: false }));
      // Will auto-reconnect via EventSource
    };

    eventSource.onopen = () => {
      state.update((s) => ({ ...s, connected: true }));
    };
  } catch {
    // EventSource creation failed
  }
}

export function disconnectTimelineStream(): void {
  if (eventSource) {
    eventSource.close();
    eventSource = null;
  }
  state.update((s) => ({ ...s, connected: false }));
}

/**
 * Truncate a posts array if it exceeds the threshold.
 * Call this after merging queued posts to prevent memory bloat.
 */
export function maybeTruncate(posts: Post[]): Post[] {
  if (posts.length > TRUNCATE_THRESHOLD) {
    return posts.slice(0, TRUNCATE_TO);
  }
  return posts;
}
