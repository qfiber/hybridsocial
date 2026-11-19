/**
 * Tracks unread DM counts per-conversation and exposes a derived
 * total for the header/sidebar badge. Separate from the notification
 * bell (which covers mentions/replies/reactions/follows) because DMs
 * are a distinct inbox column — Mastodon, Twitter, Slack all keep
 * them apart.
 *
 * Sources of truth (merged):
 *   - Initial load: `getConversations()` returns each conversation's
 *     `unread_count`.
 *   - Realtime: `chat.new_message` increments the sender's
 *     conversation by 1, unless the viewer is already looking at that
 *     thread.
 *   - `chat.read`: zeros the conversation's unread.
 *   - Manual clear: when the user opens `/messages/<id>`, the
 *     conversation view fires `markConversationRead` and we mirror
 *     that locally.
 */

import { writable, derived, get } from 'svelte/store';
import { browser } from '$app/environment';
import { getConversations } from '$lib/api/conversations.js';
import { currentUser } from '$lib/stores/auth.js';

type UnreadMap = Record<string, number>;

const map = writable<UnreadMap>({});

export const dmUnreadMap = derived(map, ($m) => $m);
export const dmUnreadTotal = derived(map, ($m) =>
  Object.values($m).reduce((a, b) => a + b, 0),
);

let initialized = false;

export async function initDmUnread(): Promise<void> {
  if (!browser || initialized) return;
  initialized = true;

  try {
    const result = await getConversations();
    const convs = Array.isArray(result)
      ? result
      : ((result as unknown) as { data?: Array<{ id: string; unread_count?: number }> })
          .data ?? [];

    const next: UnreadMap = {};
    for (const c of convs) {
      if ((c.unread_count ?? 0) > 0) next[c.id] = c.unread_count ?? 0;
    }
    map.set(next);
  } catch {
    // Not fatal — the SSE stream will top us up once events arrive.
  }

  // Hook the chat-event pipe so new messages + read events update
  // the badge without page code having to remember.
  window.addEventListener('chat-event', handleChatEvent as EventListener);
}

export function resetDmUnread(): void {
  if (!browser) return;
  map.set({});
}

export function markConversationReadLocal(conversationId: string): void {
  if (!browser) return;
  map.update((m) => {
    if (!m[conversationId]) return m;
    const { [conversationId]: _dropped, ...rest } = m;
    return rest;
  });
}

/** The viewer marked the thread unread (#299): it counts as one again. */
export function markConversationUnreadLocal(conversationId: string): void {
  if (!browser) return;
  map.update((m) => ({ ...m, [conversationId]: Math.max(m[conversationId] ?? 0, 1) }));
}

function handleChatEvent(ev: Event): void {
  const detail = (ev as CustomEvent<{ type: string; data: Record<string, unknown> }>).detail;
  if (!detail) return;

  switch (detail.type) {
    case 'chat.new_message':
      handleNewMessage(detail.data);
      break;
    case 'chat.read':
      handleRead(detail.data);
      break;
  }
}

function handleNewMessage(data: Record<string, unknown>): void {
  const convId = data.conversation_id as string | undefined;
  if (!convId) return;

  // Skip outgoing echoes — a new_message event for a message we
  // just sent shouldn't bump our own badge.
  const viewer = get(currentUser);
  const senderId = (data.sender as { id?: string } | undefined)?.id;
  if (viewer && senderId && viewer.id === senderId) return;

  // Skip if the user is currently inside that conversation — the
  // view auto-marks it read on entry.
  if (typeof window !== 'undefined') {
    const inSamePath = window.location.pathname === `/messages/${convId}`;
    if (inSamePath) return;
  }

  map.update((m) => ({
    ...m,
    [convId]: (m[convId] ?? 0) + 1,
  }));
}

function handleRead(data: Record<string, unknown>): void {
  const convId = data.conversation_id as string | undefined;
  const identityId = data.identity_id as string | undefined;
  if (!convId) return;

  const viewer = get(currentUser);
  // Only clear when WE marked it read — the other party reading
  // their side doesn't change our unread state.
  if (identityId && viewer && identityId !== viewer.id) return;

  markConversationReadLocal(convId);
}
