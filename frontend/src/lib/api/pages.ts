import { api } from './client.js';

export function getPages(): Promise<any[]> {
  return api.get('/api/v1/pages');
}

export function createPage(data: any): Promise<any> {
  return api.post('/api/v1/pages', data);
}

export function getPage(id: string): Promise<any> {
  return api.get(`/api/v1/pages/${id}`);
}

export function updatePage(id: string, data: any): Promise<any> {
  return api.patch(`/api/v1/pages/${id}`, data);
}

export function deletePage(id: string): Promise<void> {
  return api.delete(`/api/v1/pages/${id}`);
}
