import type { PageServerLoad } from './$types';
import { env } from '$env/dynamic/private';

// SSR a profile's share metadata, and what a logged-out visitor or search engine
// may get. All privacy-aware on the backend (Accounts.PublicProfile): only
// profiles that allow unfurling expose name/bio/avatar, and `seo` is only present
// for a profile that may be indexed. Rendered by the root layout via page.data.og.
export const load: PageServerLoad = async ({ params, fetch, setHeaders }) => {
  const base = env.INTERNAL_API_URL || 'http://backend:4000';
  const handle = params.handle.replace(/^@/, '');

  try {
    const res = await fetch(`${base}/api/v1/og/profile/${encodeURIComponent(handle)}`, {
      // The backend 301s plain http to the public https host unless told it came
      // in over TLS, which fails from inside the network. See +layout.server.ts.
      headers: { 'x-forwarded-proto': 'https' },
    });
    if (!res.ok) return { publicView: false };

    const m = (await res.json()) as Record<string, any>;
    if (!m.indexable) setHeaders({ 'x-robots-tag': 'noindex' });

    return {
      publicView: m.public === true,
      seo: m.seo ?? null,
      og: {
        title: m.title,
        description: m.description,
        image: m.image,
        type: m.type || 'profile',
        url: m.url,
        robots: m.indexable ? undefined : 'noindex'
      }
    };
  } catch {
    return { publicView: false };
  }
};
