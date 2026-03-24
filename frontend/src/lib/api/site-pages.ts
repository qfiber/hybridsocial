import { api } from './client.js';

export interface PublicSitePage {
  slug: string;
  title: string;
  body_html: string;
  published: boolean;
  updated_at: string | null;
}

export function getPublicSitePage(slug: string): Promise<PublicSitePage> {
  return api.get(`/api/v1/pages/site/${slug}`).then((r: { data: PublicSitePage }) => r.data);
}
