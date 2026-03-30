<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface OAuthApp {
    id: string;
    name: string;
    client_id: string;
    scopes: string[];
    created_at: string;
  }

  interface CreatedApp {
    app: { id: string; name: string; client_id: string; client_secret: string; scopes: string[] };
    access_token: string | null;
  }

  // Existing apps
  let apps = $state<OAuthApp[]>([]);
  let appsLoading = $state(true);

  // Create form
  let appName = $state('');
  let selectedScopes = $state<string[]>(['read']);
  let creating = $state(false);
  let createdResult = $state<CreatedApp | null>(null);

  // API tester
  let method = $state('GET');
  let endpoint = $state('/api/v1/instance');
  let requestBody = $state('');
  let response = $state('');
  let responseStatus = $state(0);
  let testing = $state(false);

  const availableScopes = [
    { id: 'read', label: 'Read', desc: 'Read account data, timelines, notifications' },
    { id: 'write', label: 'Write', desc: 'Create posts, follow users, react' },
    { id: 'follow', label: 'Follow', desc: 'Follow and unfollow users' },
    { id: 'push', label: 'Push', desc: 'Receive push notifications' },
  ];

  const quickEndpoints = [
    { method: 'GET', path: '/api/v1/instance', label: 'Instance' },
    { method: 'GET', path: '/api/v1/timelines/public', label: 'Public' },
    { method: 'GET', path: '/api/v1/timelines/home', label: 'Home' },
    { method: 'GET', path: '/api/v1/accounts/verify_credentials', label: 'Me' },
    { method: 'GET', path: '/api/v1/notifications', label: 'Notifications' },
    { method: 'GET', path: '/api/v1/search?q=test', label: 'Search' },
  ];

  onMount(async () => {
    try {
      apps = await api.get<OAuthApp[]>('/api/v1/apps');
    } catch { /* */ }
    finally { appsLoading = false; }
  });

  function toggleScope(scope: string) {
    if (selectedScopes.includes(scope)) {
      selectedScopes = selectedScopes.filter(s => s !== scope);
    } else {
      selectedScopes = [...selectedScopes, scope];
    }
  }

  async function createApp() {
    if (!appName.trim() || creating) return;
    creating = true;
    createdResult = null;
    try {
      const result = await api.post<CreatedApp>('/api/v1/apps/with_token', {
        name: appName,
        scopes: selectedScopes,
        redirect_uris: ['urn:ietf:wg:oauth:2.0:oob'],
      });
      createdResult = result;
      appName = '';
      selectedScopes = ['read'];
      // Refresh apps list
      apps = await api.get<OAuthApp[]>('/api/v1/apps');
      addToast('App created', 'success');
    } catch {
      addToast('Failed to create app', 'error');
    } finally { creating = false; }
  }

  async function deleteApp(id: string) {
    try {
      await api.delete(`/api/v1/apps/${id}`);
      apps = apps.filter(a => a.id !== id);
      addToast('App deleted', 'success');
    } catch {
      addToast('Failed to delete app', 'error');
    }
  }

  function copyText(text: string) {
    navigator.clipboard.writeText(text);
    addToast('Copied', 'success');
  }

  async function sendRequest() {
    testing = true;
    response = '';
    responseStatus = 0;
    try {
      const apiBase = import.meta.env.VITE_API_URL || 'http://localhost:4000';
      const headers: Record<string, string> = { 'Accept': 'application/json' };
      const opts: RequestInit = { method, headers, credentials: 'include' };
      if ((method === 'POST' || method === 'PUT' || method === 'PATCH') && requestBody.trim()) {
        headers['Content-Type'] = 'application/json';
        opts.body = requestBody;
      }
      const res = await fetch(`${apiBase}${endpoint}`, opts);
      responseStatus = res.status;
      const text = await res.text();
      try { response = JSON.stringify(JSON.parse(text), null, 2); } catch { response = text; }
    } catch (e) {
      response = `Error: ${e instanceof Error ? e.message : 'Request failed'}`;
    } finally { testing = false; }
  }
</script>

<svelte:head><title>Developer Tools - Settings</title></svelte:head>

<div class="dev-page">
  <h1 class="dev-title">Developer Tools</h1>

  <!-- Create App -->
  <div class="stitch-card">
    <h2 class="stitch-section-title">Create API App</h2>
    <p class="stitch-desc">Create an app to get API credentials. You'll receive a client ID, client secret, and an access token — all in one step.</p>

    {#if createdResult}
      <div class="created-result">
        <div class="created-header">
          <span class="material-symbols-outlined" style="font-size: 24px; color: var(--color-success)">check_circle</span>
          <strong>App "{createdResult.app.name}" created!</strong>
        </div>
        <p class="created-warning">Save these credentials now — the client secret will not be shown again.</p>

        <div class="credential-row">
          <span class="credential-label">Client ID (public)</span>
          <div class="credential-value">
            <code>{createdResult.app.client_id}</code>
            <button type="button" class="copy-btn" onclick={() => copyText(createdResult!.app.client_id)}>
              <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
            </button>
          </div>
        </div>

        <div class="credential-row">
          <span class="credential-label">Client Secret (private — keep safe!)</span>
          <div class="credential-value secret">
            <code>{createdResult.app.client_secret}</code>
            <button type="button" class="copy-btn" onclick={() => copyText(createdResult!.app.client_secret)}>
              <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
            </button>
          </div>
        </div>

        {#if createdResult.access_token}
          <div class="credential-row">
            <span class="credential-label">Access Token (Bearer token for API requests)</span>
            <div class="credential-value secret">
              <code>{createdResult.access_token}</code>
              <button type="button" class="copy-btn" onclick={() => copyText(createdResult!.access_token!)}>
                <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
              </button>
            </div>
          </div>
        {/if}

        <div class="credential-row">
          <span class="credential-label">Usage example</span>
          <pre class="usage-example">curl -H "Authorization: Bearer {createdResult.access_token || 'YOUR_TOKEN'}" \
  {window.location.origin}/api/v1/accounts/verify_credentials</pre>
        </div>

        <button type="button" class="dismiss-btn" onclick={() => createdResult = null}>Done</button>
      </div>
    {:else}
      <div class="create-form">
        <div class="stitch-field">
          <label class="stitch-label" for="app-name">App Name</label>
          <input id="app-name" type="text" class="stitch-input" bind:value={appName} placeholder="My Bot, Dashboard, etc." />
        </div>

        <div class="stitch-field">
          <label class="stitch-label">Permissions</label>
          <div class="scope-chips">
            {#each availableScopes as scope (scope.id)}
              <button type="button" class="scope-chip" class:active={selectedScopes.includes(scope.id)} onclick={() => toggleScope(scope.id)}>
                <span class="scope-name">{scope.label}</span>
                <span class="scope-desc">{scope.desc}</span>
              </button>
            {/each}
          </div>
        </div>

        <button type="button" class="stitch-btn-primary" onclick={createApp} disabled={!appName.trim() || selectedScopes.length === 0 || creating}>
          {creating ? 'Creating...' : 'Create App & Generate Token'}
        </button>
      </div>
    {/if}
  </div>

  <!-- Existing Apps -->
  <div class="stitch-card">
    <h2 class="stitch-section-title">Your Apps</h2>
    {#if appsLoading}
      <div style="padding: 16px; text-align: center"><Spinner /></div>
    {:else if apps.length === 0}
      <p class="stitch-empty">No apps created yet.</p>
    {:else}
      <div class="apps-list">
        {#each apps as app (app.id)}
          <div class="app-item">
            <div class="app-info">
              <span class="app-name">{app.name}</span>
              <div class="app-key-row">
                <span class="app-key-label">Public Key:</span>
                <code class="app-client-id">{app.client_id}</code>
                <button type="button" class="copy-btn-sm" onclick={() => copyText(app.client_id)} aria-label="Copy public key">
                  <span class="material-symbols-outlined" style="font-size: 14px">content_copy</span>
                </button>
              </div>
              <span class="app-meta">{(app.scopes || []).join(', ')}</span>
            </div>
            <button type="button" class="app-delete" onclick={() => deleteApp(app.id)}>
              <span class="material-symbols-outlined" style="font-size: 18px">delete</span>
            </button>
          </div>
        {/each}
      </div>
    {/if}
  </div>

  <!-- API Tester -->
  <div class="stitch-card">
    <h2 class="stitch-section-title">API Tester</h2>
    <div class="quick-chips">
      {#each quickEndpoints as ep (ep.path)}
        <button type="button" class="quick-chip" class:active={endpoint === ep.path} onclick={() => { method = ep.method; endpoint = ep.path; }}>
          {ep.label}
        </button>
      {/each}
    </div>

    <div class="request-bar">
      <select class="method-select" bind:value={method}>
        <option>GET</option><option>POST</option><option>PUT</option><option>PATCH</option><option>DELETE</option>
      </select>
      <input type="text" class="endpoint-input" bind:value={endpoint} placeholder="/api/v1/..." />
      <button type="button" class="send-btn" onclick={sendRequest} disabled={testing}>{testing ? '...' : 'Send'}</button>
    </div>

    {#if method !== 'GET' && method !== 'DELETE'}
      <textarea class="body-input" bind:value={requestBody} rows={3} placeholder={'{"key": "value"}'}></textarea>
    {/if}

    {#if response}
      <div class="response-section">
        <div class="response-header">
          <span class="response-label">Response</span>
          {#if responseStatus > 0}
            <span class="status-badge" class:status-ok={responseStatus < 300} class:status-err={responseStatus >= 400}>{responseStatus}</span>
          {/if}
        </div>
        <pre class="response-body">{response}</pre>
      </div>
    {/if}
  </div>
</div>

<style>
  .dev-page { max-width: 700px; }
  .dev-title { font-size: var(--text-2xl); font-weight: 700; margin-block-end: var(--space-6); }

  .stitch-card { background: var(--color-surface-raised, white); border: 1px solid var(--color-border); border-radius: var(--radius-xl); padding: var(--space-5); margin-block-end: var(--space-4); }
  .stitch-section-title { font-size: var(--text-base); font-weight: 600; margin-block-end: var(--space-3); }
  .stitch-desc { font-size: var(--text-sm); color: var(--color-text-secondary); margin-block-end: var(--space-4); line-height: 1.4; }
  .stitch-empty { font-size: var(--text-sm); color: var(--color-text-tertiary); text-align: center; padding: var(--space-6); }
  .stitch-field { margin-block-end: var(--space-3); }
  .stitch-label { display: block; font-size: 0.75rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: var(--color-text-secondary); margin-block-end: 6px; }
  .stitch-input { width: 100%; padding: 10px 14px; border: 1px solid var(--color-border); border-radius: 10px; font-size: 0.875rem; color: var(--color-text); background: var(--color-surface); }
  .stitch-input:focus { outline: none; border-color: var(--color-primary); }
  .stitch-btn-primary { padding: 10px 24px; background: var(--color-primary); color: white; border: none; border-radius: 9999px; font-size: 0.875rem; font-weight: 600; cursor: pointer; }
  .stitch-btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }

  /* Scopes */
  .scope-chips { display: flex; flex-direction: column; gap: 6px; }
  .scope-chip {
    display: flex; flex-direction: column; gap: 2px; text-align: start;
    padding: 10px 14px; border: 2px solid var(--color-border); border-radius: 10px;
    background: transparent; cursor: pointer; transition: all 150ms ease;
  }
  .scope-chip.active { border-color: var(--color-primary); background: var(--color-primary-soft, rgba(0,128,128,0.05)); }
  .scope-name { font-size: 0.875rem; font-weight: 600; color: var(--color-text); }
  .scope-desc { font-size: 0.75rem; color: var(--color-text-secondary); }

  /* Created result */
  .created-result { padding: 16px; background: var(--color-surface); border-radius: 12px; }
  .created-header { display: flex; align-items: center; gap: 8px; font-size: 0.9375rem; margin-block-end: 8px; }
  .created-warning { font-size: 0.8125rem; color: var(--color-warning, #f59e0b); font-weight: 500; margin-block-end: 16px; }

  .credential-row { margin-block-end: 12px; }
  .credential-label { display: block; font-size: 0.7rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--color-text-tertiary); margin-block-end: 4px; }
  .credential-value { display: flex; align-items: center; gap: 8px; padding: 8px 12px; background: var(--color-surface-container-lowest); border: 1px solid var(--color-border); border-radius: 8px; }
  .credential-value code { flex: 1; font-size: 0.75rem; word-break: break-all; color: var(--color-text); }
  .credential-value.secret { border-color: var(--color-warning, #f59e0b); }
  .copy-btn { background: none; border: none; color: var(--color-text-tertiary); cursor: pointer; padding: 2px; border-radius: 4px; flex-shrink: 0; }
  .copy-btn:hover { color: var(--color-primary); background: var(--color-surface); }

  .usage-example { font-size: 0.75rem; padding: 10px 12px; background: #1e1e2e; color: #cdd6f4; border-radius: 8px; overflow-x: auto; white-space: pre-wrap; word-break: break-all; }

  .dismiss-btn { margin-top: 12px; padding: 8px 20px; background: var(--color-primary); color: white; border: none; border-radius: 9999px; font-size: 0.8125rem; font-weight: 600; cursor: pointer; }

  /* Apps list */
  .apps-list { display: flex; flex-direction: column; gap: 8px; }
  .app-item { display: flex; align-items: center; justify-content: space-between; padding: 10px 14px; background: var(--color-surface); border-radius: 10px; }
  .app-info { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .app-name { font-size: 0.875rem; font-weight: 600; }
  .app-meta { font-size: 0.7rem; color: var(--color-text-tertiary); }
  .app-client-id { font-size: 0.65rem; background: var(--color-surface-container-low, #f0f0f0); padding: 1px 5px; border-radius: 4px; }
  .app-key-row { display: flex; align-items: center; gap: 6px; margin: 2px 0; }
  .app-key-label { font-size: 0.65rem; font-weight: 600; color: var(--color-text-tertiary); }
  .copy-btn-sm { background: none; border: none; color: var(--color-text-tertiary); cursor: pointer; padding: 1px; border-radius: 3px; display: flex; }
  .copy-btn-sm:hover { color: var(--color-primary); }
  .app-delete { background: none; border: none; color: var(--color-text-tertiary); cursor: pointer; padding: 4px; border-radius: 50%; }
  .app-delete:hover { color: var(--color-danger); background: rgba(239,68,68,0.1); }

  /* API Tester */
  .quick-chips { display: flex; flex-wrap: wrap; gap: 4px; margin-block-end: 10px; }
  .quick-chip { padding: 3px 10px; border: 1px solid var(--color-border); border-radius: 6px; background: transparent; font-size: 0.7rem; font-weight: 600; color: var(--color-text-secondary); cursor: pointer; }
  .quick-chip:hover { border-color: var(--color-primary); }
  .quick-chip.active { background: var(--color-primary-soft, rgba(0,128,128,0.08)); border-color: var(--color-primary); color: var(--color-primary); }

  .request-bar { display: flex; gap: 6px; margin-block-end: 8px; }
  .method-select { padding: 8px 10px; border: 1px solid var(--color-border); border-radius: 8px; font-size: 0.8125rem; font-weight: 600; background: var(--color-surface); width: 90px; }
  .endpoint-input { flex: 1; padding: 8px 12px; border: 1px solid var(--color-border); border-radius: 8px; font-size: 0.8125rem; font-family: monospace; color: var(--color-text); background: var(--color-surface); }
  .endpoint-input:focus { outline: none; border-color: var(--color-primary); }
  .send-btn { padding: 8px 16px; background: var(--color-primary); color: white; border: none; border-radius: 8px; font-size: 0.8125rem; font-weight: 600; cursor: pointer; }
  .send-btn:disabled { opacity: 0.5; }

  .body-input { width: 100%; padding: 8px 12px; border: 1px solid var(--color-border); border-radius: 8px; font-size: 0.75rem; font-family: monospace; color: var(--color-text); background: var(--color-surface); resize: vertical; margin-block-end: 8px; }

  .response-section { background: var(--color-surface-container-lowest); border: 1px solid var(--color-border); border-radius: 10px; overflow: hidden; margin-top: 8px; }
  .response-header { display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; border-bottom: 1px solid var(--color-border); }
  .response-label { font-size: 0.65rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: var(--color-text-tertiary); }
  .status-badge { font-size: 0.7rem; font-weight: 700; padding: 1px 6px; border-radius: 4px; }
  .status-ok { background: #dcfce7; color: #15803d; }
  .status-err { background: #fecaca; color: #dc2626; }
  .response-body { padding: 12px; margin: 0; font-size: 0.75rem; font-family: monospace; color: var(--color-text); white-space: pre-wrap; word-break: break-word; max-height: 300px; overflow-y: auto; }

  .method-badge { font-size: 0.55rem; font-weight: 700; padding: 1px 4px; border-radius: 3px; text-transform: uppercase; }
  .method-get { background: #dbeafe; color: #1d4ed8; }
  .method-post { background: #dcfce7; color: #15803d; }
</style>
