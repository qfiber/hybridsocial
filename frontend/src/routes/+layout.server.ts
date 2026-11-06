import type { LayoutServerLoad } from './$types';
import { env } from '$env/dynamic/private';

// Fetch the public instance info at SSR time so the root layout can render
// real <meta name="description"> / og: tags into the initial HTML. Social
// crawlers (Twitter/Slack/Discord/Facebook) don't run JS, so these must be
// server-rendered, not applied client-side.
//
// Uses the internal backend URL (Docker network) rather than a relative
// path, which would hairpin out through the public edge during SSR. Falls
// back gracefully to no instance data if the backend is unreachable.
export const load: LayoutServerLoad = async ({ fetch }) => {
  const base = env.INTERNAL_API_URL || 'http://backend:4000';

  try {
    // The backend forces SSL (rewrite_on: [:x_forwarded_proto]) and only
    // excludes localhost, so a plain http://backend:4000 call gets 301'd to
    // the public https host — which hairpins/fails during SSR, leaving the
    // <title> and og: tags on their "HybridSocial" fallbacks. We're an
    // internal client behind the same TLS edge, so declare the forwarded
    // proto and the backend serves us directly instead of redirecting.
    const res = await fetch(`${base}/api/v1/instance`, {
      headers: { 'x-forwarded-proto': 'https' },
    });
    if (!res.ok) return { instance: null };

    const info = (await res.json()) as Record<string, unknown>;
    const theme = (info.theme as Record<string, unknown> | null) ?? null;

    return {
      instance: {
        configuration: {
          feeds: (info.configuration as { feeds?: unknown } | undefined)?.feeds ?? null,
        },
        title: (info.title as string) || 'HybridSocial',
        description:
          (info.short_description as string) || (info.description as string) || '',
        favicon_url:
          (info.favicon_url as string) || (theme?.favicon_url as string) || null,
        og_image_url:
          (info.og_image_url as string) || (theme?.og_image_url as string) || null,
        og_image_width: (info.og_image_width as number) ?? null,
        og_image_height: (info.og_image_height as number) ?? null
      }
    };
  } catch {
    return { instance: null };
  }
};
