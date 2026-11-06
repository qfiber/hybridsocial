import type { PageServerLoad } from './$types';
import { env } from '$env/dynamic/private';

// SSR the post's share metadata so a shared /post/<id> link renders the
// post (author, text snippet, image) instead of the generic instance
// card. The backend endpoint is privacy-aware: only strictly-public
// posts return content; followers-only / direct / unlisted / deleted /
// remote posts return a neutral "private post" placeholder. Rendered by
// the root layout via page.data.og.
export const load: PageServerLoad = async ({ params, fetch, setHeaders }) => {
  const base = env.INTERNAL_API_URL || 'http://backend:4000';

  try {
    const res = await fetch(`${base}/api/v1/og/post/${encodeURIComponent(params.id)}`, {
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
        image_width: (m.image_width as number) ?? null,
        image_height: (m.image_height as number) ?? null,
        type: m.type || 'article',
        url: m.url,
        robots: m.indexable ? undefined : 'noindex'
      }
    };
  } catch {
    return { publicView: false };
  }
};
