<script lang="ts">
  // OAuth consent screen.
  //
  // The backend's GET /oauth/authorize redirects a third-party client here
  // rather than rendering its own login page, so the whole real auth flow
  // (2FA, passkeys, the email-confirmation gate) is reused instead of
  // reimplemented. Once the user approves, we ask the backend for an
  // authorization code and hand it back to the client.
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { api, ApiError } from '$lib/api/client.js';
  import { currentUser, initAuth } from '$lib/stores/auth.js';
  import { instanceName } from '$lib/stores/instance.js';
  import BrandMark from '$lib/components/ui/BrandMark.svelte';
  import Avatar from '$lib/components/ui/Avatar.svelte';

  const OOB = 'urn:ietf:wg:oauth:2.0:oob';

  interface AppInfo {
    name: string;
    website: string | null;
    scopes: string[];
    redirect_uris: string[];
  }

  type Phase = 'loading' | 'consent' | 'oob' | 'error';

  let phase = $state<Phase>('loading');
  let app = $state<AppInfo | null>(null);
  let errorMessage = $state('');
  let submitting = $state(false);
  let oobCode = $state('');
  let copied = $state(false);

  let params = $state<URLSearchParams>(new URLSearchParams());
  let clientId = $derived(params.get('client_id') || '');
  let redirectUri = $derived(params.get('redirect_uri') || '');
  let requestedScope = $derived(params.get('scope') || params.get('scopes') || '');

  // The client can only ever receive what it registered for, so show the
  // intersection rather than whatever the query string asked for.
  let grantedScopes = $derived.by(() => {
    if (!app) return [];
    const asked = requestedScope.split(/\s+/).filter(Boolean);
    if (asked.length === 0) return app.scopes;
    return asked.filter((s) => app!.scopes.includes(s));
  });

  const SCOPE_TEXT: Record<string, string> = {
    read: 'Read your account, posts, timelines, notifications and lists',
    write: 'Post, edit and delete on your behalf, and change your profile',
    follow: 'Follow, unfollow, block and mute accounts for you',
    push: 'Send you push notifications',
    'admin:read': 'Read moderation data across the whole server',
    'admin:write': 'Take moderation actions across the whole server'
  };

  function describeScope(scope: string): string {
    if (SCOPE_TEXT[scope]) return SCOPE_TEXT[scope];
    // Granular forms like read:accounts.
    const [family, subject] = scope.split(':');
    if (family && subject) {
      const verb = family === 'read' ? 'Read' : 'Modify';
      return `${verb} your ${subject.replace(/_/g, ' ')}`;
    }
    return scope;
  }

  onMount(async () => {
    params = new URL(window.location.href).searchParams;

    if (!clientId) {
      errorMessage = 'This link is missing a client_id, so there is no app to authorize.';
      phase = 'error';
      return;
    }

    try {
      app = await api.get<AppInfo>('/api/v1/apps/info', { client_id: clientId });
    } catch (err) {
      errorMessage =
        err instanceof ApiError && err.status === 404
          ? 'That application is not registered on this server.'
          : 'Could not load the application details. Try again.';
      phase = 'error';
      return;
    }

    if (!app.redirect_uris.includes(redirectUri)) {
      errorMessage =
        'The callback address does not match one registered by this application, so the request was rejected.';
      phase = 'error';
      return;
    }

    // A child's onMount runs before the root layout's, so the session may not
    // be bootstrapped yet. initAuth() is idempotent — awaiting it here avoids
    // bouncing an already-signed-in user to the login page.
    await initAuth();

    // Not signed in: send the user through the real login flow and come back.
    if (!$currentUser) {
      const here = window.location.pathname + window.location.search;
      await goto(`/login?next=${encodeURIComponent(here)}`);
      return;
    }

    phase = 'consent';
  });

  function appendQuery(uri: string, query: Record<string, string>): string {
    const pairs = Object.entries(query).filter(([, v]) => v);
    const encoded = pairs
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
      .join('&');
    return uri + (uri.includes('?') ? '&' : '?') + encoded;
  }

  // Custom schemes (husky://, tusky://) can't be handed to SvelteKit's
  // router — this has to be a real browser navigation.
  function leaveTo(uri: string) {
    window.location.href = uri;
  }

  async function approve() {
    if (submitting || !app) return;
    submitting = true;
    errorMessage = '';

    try {
      const result = await api.post<{ code: string; state: string | null }>('/oauth/authorize', {
        response_type: params.get('response_type') || 'code',
        client_id: clientId,
        redirect_uri: redirectUri,
        scope: grantedScopes.join(' '),
        state: params.get('state') || '',
        code_challenge: params.get('code_challenge') || ''
      });

      const state = params.get('state') || '';

      if (redirectUri === OOB) {
        oobCode = result.code;
        phase = 'oob';
        return;
      }

      leaveTo(appendQuery(redirectUri, { code: result.code, state }));
    } catch (err) {
      errorMessage =
        err instanceof ApiError
          ? err.message || 'The server refused this authorization request.'
          : 'Something went wrong. Try again.';
      submitting = false;
    }
  }

  function deny() {
    const state = params.get('state') || '';

    if (redirectUri === OOB) {
      errorMessage = 'Access denied. You can close this page.';
      phase = 'error';
      return;
    }

    leaveTo(appendQuery(redirectUri, { error: 'access_denied', state }));
  }

  async function copyCode() {
    try {
      await navigator.clipboard.writeText(oobCode);
      copied = true;
      setTimeout(() => (copied = false), 2000);
    } catch {
      /* clipboard unavailable — the code is selectable on screen */
    }
  }
</script>

<svelte:head>
  <title>Authorize application · {$instanceName}</title>
  <meta name="robots" content="noindex" />
</svelte:head>

<div class="authorize-page">
  <div class="authorize-card">
    <div class="authorize-brand">
      <BrandMark size={28} />
      <span class="authorize-brand-name">{$instanceName}</span>
    </div>

    {#if phase === 'loading'}
      <p class="authorize-muted">Loading application details…</p>
    {:else if phase === 'error'}
      <h1 class="authorize-title">Authorization request rejected</h1>
      <p class="authorize-muted">{errorMessage}</p>
      <a class="authorize-secondary" href="/home">Back to {$instanceName}</a>
    {:else if phase === 'oob'}
      <h1 class="authorize-title">Copy this code into {app?.name}</h1>
      <p class="authorize-muted">
        Paste it back into the app to finish signing in. It expires in a few minutes.
      </p>
      <output class="authorize-code">{oobCode}</output>
      <button type="button" class="authorize-primary" onclick={copyCode}>
        {copied ? 'Copied' : 'Copy code'}
      </button>
    {:else}
      <h1 class="authorize-title">
        <strong>{app?.name}</strong> wants access to your account
      </h1>

      {#if app?.website}
        <a class="authorize-site" href={app.website} rel="noopener noreferrer nofollow" target="_blank">
          {app.website}
        </a>
      {/if}

      {#if $currentUser}
        <div class="authorize-account">
          <Avatar
            src={$currentUser.avatar_url}
            name={$currentUser.display_name || $currentUser.handle}
            size="sm"
          />
          <div class="authorize-account-text">
            <span class="authorize-muted">Signing in as</span>
            <span class="authorize-handle">@{$currentUser.handle}</span>
          </div>
        </div>
      {/if}

      <p class="authorize-section-label">This will let it:</p>
      <ul class="authorize-scopes">
        {#each grantedScopes as scope (scope)}
          <li>
            <span class="authorize-scope-name">{scope}</span>
            <span class="authorize-scope-desc">{describeScope(scope)}</span>
          </li>
        {:else}
          <li><span class="authorize-scope-desc">No permissions requested.</span></li>
        {/each}
      </ul>

      <p class="authorize-fineprint">
        You can revoke this access at any time from Settings → Developers.
      </p>

      {#if errorMessage}
        <div class="authorize-error" role="alert">{errorMessage}</div>
      {/if}

      <div class="authorize-actions">
        <button type="button" class="authorize-secondary" onclick={deny} disabled={submitting}>
          Deny
        </button>
        <button type="button" class="authorize-primary" onclick={approve} disabled={submitting}>
          {submitting ? 'Authorizing…' : 'Authorize'}
        </button>
      </div>
    {/if}
  </div>
</div>

<style>
  .authorize-page {
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-6);
    background: var(--color-surface-container-low);
  }

  .authorize-card {
    width: 100%;
    max-width: 460px;
    background: var(--color-surface);
    border: 1px solid var(--scrim-soft);
    border-radius: 16px;
    padding: var(--space-8);
  }

  .authorize-brand {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    margin-block-end: var(--space-6);
  }

  .authorize-brand-name {
    font-family: var(--font-sans);
    font-weight: 700;
    color: var(--color-primary);
  }

  .authorize-title {
    font-size: var(--text-xl);
    font-weight: 600;
    line-height: 1.35;
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .authorize-site {
    display: inline-block;
    font-size: var(--text-sm);
    color: var(--color-primary);
    margin-block-end: var(--space-4);
    word-break: break-all;
  }

  .authorize-muted {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .authorize-account {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3);
    border: 1px solid var(--scrim-soft);
    border-radius: 12px;
    margin-block: var(--space-4);
  }

  .authorize-account-text {
    display: flex;
    flex-direction: column;
  }

  .authorize-handle {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .authorize-section-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .authorize-scopes {
    list-style: none;
    padding: 0;
    margin: 0 0 var(--space-4);
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .authorize-scopes li {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding-inline-start: var(--space-3);
    border-inline-start: 2px solid var(--color-primary);
  }

  .authorize-scope-name {
    font-size: var(--text-xs);
    font-weight: 700;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--color-primary);
  }

  .authorize-scope-desc {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.45;
  }

  .authorize-fineprint {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-end: var(--space-5);
  }

  .authorize-error {
    font-size: var(--text-sm);
    color: var(--color-error, #b3261e);
    margin-block-end: var(--space-4);
  }

  .authorize-code {
    display: block;
    font-family: var(--font-mono, monospace);
    font-size: var(--text-sm);
    word-break: break-all;
    padding: var(--space-4);
    border: 1px solid var(--scrim-soft);
    border-radius: 12px;
    background: var(--color-surface-container-low);
    margin-block: var(--space-4);
    color: var(--color-text);
  }

  .authorize-actions {
    display: flex;
    gap: var(--space-3);
  }

  .authorize-primary,
  .authorize-secondary {
    flex: 1;
    padding: var(--space-3) var(--space-4);
    border-radius: 9999px;
    font-size: var(--text-sm);
    font-weight: 600;
    cursor: pointer;
    text-align: center;
    text-decoration: none;
  }

  .authorize-primary {
    background: var(--color-primary);
    color: var(--color-on-primary, #fff);
    border: 1px solid var(--color-primary);
  }

  .authorize-secondary {
    background: transparent;
    color: var(--color-text);
    border: 1px solid var(--scrim-soft);
  }

  .authorize-primary:disabled,
  .authorize-secondary:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  @media (max-width: 480px) {
    .authorize-card {
      padding: var(--space-6);
      border: none;
    }
  }
</style>
