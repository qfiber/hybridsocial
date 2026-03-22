import { api } from './client.js';
import type { MediaAttachment } from './types.js';

export function uploadMedia(file: File, description?: string): Promise<MediaAttachment> {
  const fields: Record<string, string> = {};
  if (description) fields.description = description;
  return api.upload('/api/v1/media', file, fields);
}

export function updateMedia(id: string, data: { description?: string }): Promise<MediaAttachment> {
  return api.put(`/api/v1/media/${id}`, data);
}
