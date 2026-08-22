import { api } from './client.js';
import type { Conversation, Message, MessageReaction, PaginatedResponse } from './types.js';

export function getConversations(cursor?: string): Promise<PaginatedResponse<Conversation>> {
  const params: Record<string, string> = {};
  if (cursor) params.cursor = cursor;
  return api.get('/api/v1/conversations', params);
}

export function getConversation(id: string): Promise<Conversation> {
  return api.get(`/api/v1/conversations/${id}`);
}

export function createConversation(recipientIds: string[]): Promise<Conversation> {
  // API contract: the sender is implicit (current_identity). `recipient_ids`
  // is the OTHER party (or parties for a group DM). One ID → direct DM,
  // two or more → group DM.
  return api.post('/api/v1/conversations', { recipient_ids: recipientIds });
}

// The messages endpoint is offset-paginated and returns a bare array
// (newest-first). We translate the caller's opaque `cursor` to/from an
// offset and synthesize `next_cursor` from page fullness, so the view's
// cursor-based load-older logic works. PAGE must equal the server's
// max_limit (40) — a smaller value would make a full page look partial.
const MESSAGES_PAGE = 40;

export async function getMessages(
  conversationId: string,
  cursor?: string,
): Promise<PaginatedResponse<Message>> {
  const offset = cursor ? parseInt(cursor, 10) || 0 : 0;
  const params: Record<string, string> = {
    limit: String(MESSAGES_PAGE),
    offset: String(offset),
  };
  const raw = await api.get<Message[] | PaginatedResponse<Message>>(
    `/api/v1/conversations/${conversationId}/messages`,
    params,
  );
  const data = Array.isArray(raw) ? raw : raw.data;
  // A full page means more history likely exists; a short page is the end.
  const next_cursor = data.length === MESSAGES_PAGE ? String(offset + data.length) : null;
  return { data, next_cursor, prev_cursor: null };
}

export function sendMessage(conversationId: string, data: {
  content: string;
  media_ids?: string[];
  reply_to_id?: string;
}): Promise<Message> {
  return api.post(`/api/v1/conversations/${conversationId}/messages`, data);
}

export function markConversationRead(id: string): Promise<void> {
  return api.post(`/api/v1/conversations/${id}/read`);
}

/** Fire-and-forget "I'm typing" ping to the other participants. */
export function sendTyping(id: string): Promise<void> {
  return api.post(`/api/v1/conversations/${id}/typing`);
}

export function deleteConversation(id: string): Promise<void> {
  return api.delete(`/api/v1/conversations/${id}`);
}

export function acceptConversation(id: string): Promise<Conversation> {
  return api.post(`/api/v1/conversations/${id}/accept`);
}

export function declineConversation(id: string): Promise<void> {
  return api.delete(`/api/v1/conversations/${id}/decline`);
}

export interface ReactionUpdate {
  action: 'added' | 'removed' | 'swapped';
  emoji: string | null;
  previous_emoji: string | null;
  message_id: string;
  reactions: MessageReaction[];
}

export function addMessageReaction(
  conversationId: string,
  messageId: string,
  emoji: string,
): Promise<ReactionUpdate> {
  return api.post(`/api/v1/conversations/${conversationId}/messages/${messageId}/reactions`, { emoji });
}

export function removeMessageReaction(conversationId: string, messageId: string, emoji: string): Promise<void> {
  return api.delete(`/api/v1/conversations/${conversationId}/messages/${messageId}/reactions/${encodeURIComponent(emoji)}`);
}

export function deleteMessage(conversationId: string, messageId: string): Promise<void> {
  return api.delete(`/api/v1/conversations/${conversationId}/messages/${messageId}`);
}

export interface TranslatedMessage {
  content: string;
  provider: string;
}

/** Translate a DM's text into `targetLang` for any conversation participant. */
export function translateMessage(
  conversationId: string,
  messageId: string,
  targetLang: string,
): Promise<TranslatedMessage> {
  return api.post(`/api/v1/conversations/${conversationId}/messages/${messageId}/translate`, {
    target_lang: targetLang,
  });
}

export function editMessage(
  conversationId: string,
  messageId: string,
  content: string,
): Promise<Message> {
  return api.put(`/api/v1/conversations/${conversationId}/messages/${messageId}`, {
    content,
  });
}

export interface PremiumReactionsResponse {
  defaults: string[];
  premium: Array<{
    id: string;
    shortcode: string;
    character: string | null;
    image_url: string | null;
    position: number;
  }>;
  max_premium: number;
}

export function getPremiumReactions(): Promise<PremiumReactionsResponse> {
  return api.get('/api/v1/premium_reactions');
}
