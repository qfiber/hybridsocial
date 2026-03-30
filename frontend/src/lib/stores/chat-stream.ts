import { writable, derived } from 'svelte/store';
import { browser } from '$app/environment';

interface ChatEvent {
  type: string;
  data: Record<string, unknown>;
}

const events = writable<ChatEvent[]>([]);

let eventSource: EventSource | null = null;

export const chatEvents = derived(events, ($e) => $e);

/**
 * Connect to the user streaming endpoint and listen for chat events.
 * Events: chat.new_message, chat.read, chat.reaction_added, chat.reaction_removed
 */
export function connectChatStream(apiBase: string): void {
  if (!browser) return;
  disconnectChatStream();

  try {
    const url = `${apiBase}/api/v1/streaming/user`;
    eventSource = new EventSource(url, { withCredentials: true });

    // Chat events come as SSE events with "chat.*" event names
    const chatEventTypes = [
      'chat.new_message',
      'chat.read',
      'chat.reaction_added',
      'chat.reaction_removed',
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
        } catch {
          // Ignore malformed events
        }
      });
    }

    eventSource.onerror = () => {
      // Will auto-reconnect
    };
  } catch {
    // EventSource creation failed
  }
}

export function disconnectChatStream(): void {
  if (eventSource) {
    eventSource.close();
    eventSource = null;
  }
}
