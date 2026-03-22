import { api } from './client.js';
import type { Conversation, Message, PaginatedResponse } from './types.js';

export function getConversations(cursor?: string): Promise<PaginatedResponse<Conversation>> {
  const params: Record<string, string> = {};
  if (cursor) params.cursor = cursor;
  return api.get('/api/v1/conversations', params);
}

export function getConversation(id: string): Promise<Conversation> {
  return api.get(`/api/v1/conversations/${id}`);
}

export function createConversation(participantIds: string[]): Promise<Conversation> {
  return api.post('/api/v1/conversations', { participant_ids: participantIds });
}

export function getMessages(conversationId: string, cursor?: string): Promise<PaginatedResponse<Message>> {
  const params: Record<string, string> = {};
  if (cursor) params.cursor = cursor;
  return api.get(`/api/v1/conversations/${conversationId}/messages`, params);
}

export function sendMessage(conversationId: string, data: {
  content: string;
  media_ids?: string[];
}): Promise<Message> {
  return api.post(`/api/v1/conversations/${conversationId}/messages`, data);
}

export function markConversationRead(id: string): Promise<void> {
  return api.post(`/api/v1/conversations/${id}/read`);
}

export function deleteConversation(id: string): Promise<void> {
  return api.delete(`/api/v1/conversations/${id}`);
}
