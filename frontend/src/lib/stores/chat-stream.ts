import { writable, derived, get } from 'svelte/store';
import { browser } from '$app/environment';
import { currentUser } from './auth.js';

interface ChatEvent {
  type: string;
  data: Record<string, unknown>;
}

const events = writable<ChatEvent[]>([]);

let eventSource: EventSource | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let reconnectAttempts = 0;
let onlineListener: (() => void) | null = null;

export const chatEvents = derived(events, ($e) => $e);

/**
 * Connect to the user streaming endpoint and listen for chat events.
 * Events: chat.new_message, chat.read, chat.reaction_added, chat.reaction_removed
 */
export function connectChatStream(apiBase: string): void {
  if (!browser) return;
  stopReconnectTimer();
  closeEventSource();

  if (!onlineListener) {
    onlineListener = () => {
      reconnectAttempts = 0;
      stopReconnectTimer();
      connectChatStream(apiBase);
    };
    window.addEventListener('online', onlineListener);
  }

  try {
    const url = `${apiBase}/api/v1/streaming/user`;
    eventSource = new EventSource(url, { withCredentials: true });

    // User-scoped realtime events. Despite the store's name, this
    // connection carries every event broadcast on `user:<id>` —
    // DM traffic plus direct-post notifications for the profile's
    // Direct tab. Keeping them on one EventSource avoids doubling
    // up connections to the same endpoint.
    const chatEventTypes = [
      'chat.new_message',
      'chat.read',
      'chat.reaction_added',
      'chat.reaction_removed',
      'chat.typing',
      'direct.new_post',
    ];

    for (const eventType of chatEventTypes) {
      eventSource.addEventListener(eventType, (event) => {
        try {
          const data = JSON.parse(event.data);
          window.dispatchEvent(
            new CustomEvent('chat-event', {
              detail: { type: eventType, data },
            })
          );
          // A `chat.new_message` is the DM arrival ping — different
          // sound from the generic notification bell so the user can
          // distinguish at a glance. Direct-post broadcasts ride the
          // same channel but use the notification sound since they're
          // not really "chat".
          //
          // Skip echoes of our own sends: the server broadcasts the
          // new message to every participant, including the sender,
          // so without this check we'd chime on messages we ourselves
          // just typed.
          if (eventType === 'chat.new_message') {
            const viewer = get(currentUser);
            const senderId =
              (data?.sender as { id?: string } | undefined)?.id ??
              (data?.sender_id as string | undefined);
            if (viewer && senderId && viewer.id === senderId) {
              // Our own echo — no sound.
            } else {
              const messageId = (data?.id ?? (data?.message as { id?: string } | undefined)?.id) as
                | string
                | undefined;
              import('./sound.js').then((m) =>
                m.playMessageSound(messageId ? `message:${messageId}` : undefined),
              );
            }
          }
        } catch {
          // Ignore malformed events
        }
      });
    }

    eventSource.onopen = () => {
      reconnectAttempts = 0;
    };

    // EventSource's native auto-reconnect keeps the same server-side
    // subscription and never recovers from a backend restart, so we
    // tear down and re-dial ourselves with exponential backoff.
    eventSource.onerror = () => {
      closeEventSource();
      scheduleReconnect(apiBase);
    };
  } catch {
    // EventSource creation failed
  }
}

function scheduleReconnect(apiBase: string): void {
  stopReconnectTimer();
  const delay = Math.min(30_000, 1000 * 2 ** reconnectAttempts);
  reconnectAttempts += 1;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectChatStream(apiBase);
  }, delay);
}

function stopReconnectTimer(): void {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
}

function closeEventSource(): void {
  if (eventSource) {
    eventSource.close();
    eventSource = null;
  }
}

export function disconnectChatStream(): void {
  stopReconnectTimer();
  closeEventSource();
  if (onlineListener) {
    window.removeEventListener('online', onlineListener);
    onlineListener = null;
  }
  reconnectAttempts = 0;
}
