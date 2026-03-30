<script lang="ts">
  import { api } from '$lib/api/client.js';
  import { onMount } from 'svelte';

  let method = $state('GET');
  let endpoint = $state('/api/v1/instance');
  let requestBody = $state('');
  let response = $state('');
  let responseStatus = $state(0);
  let loading = $state(false);
  let instanceInfo = $state<Record<string, unknown> | null>(null);

  const commonEndpoints = [
    { method: 'GET', path: '/api/v1/instance', label: 'Instance info' },
    { method: 'GET', path: '/api/v1/timelines/public', label: 'Public timeline' },
    { method: 'GET', path: '/api/v1/timelines/home', label: 'Home timeline' },
    { method: 'GET', path: '/api/v1/accounts/verify_credentials', label: 'Current user' },
    { method: 'GET', path: '/api/v1/notifications', label: 'Notifications' },
    { method: 'GET', path: '/api/v1/search?q=test', label: 'Search' },
    { method: 'GET', path: '/api/v1/trends/tags', label: 'Trending tags' },
    { method: 'GET', path: '/api/v1/accounts/followed_tags', label: 'Followed tags' },
    { method: 'GET', path: '/api/v1/accounts/filters', label: 'Content filters' },
    { method: 'GET', path: '/api/v1/conversations', label: 'Conversations' },
    { method: 'GET', path: '/api/v1/accounts/blocks', label: 'Blocked accounts' },
    { method: 'GET', path: '/api/v1/accounts/mutes', label: 'Muted accounts' },
    { method: 'GET', path: '/api/v1/subscriptions/plans', label: 'Subscription plans' },
  ];

  onMount(async () => {
    try {
      instanceInfo = await api.get('/api/v1/instance');
    } catch { /* */ }
  });

  function selectEndpoint(ep: typeof commonEndpoints[0]) {
    method = ep.method;
    endpoint = ep.path;
    requestBody = '';
  }

  async function sendRequest() {
    loading = true;
    response = '';
    responseStatus = 0;

    try {
      const apiBase = import.meta.env.VITE_API_URL || 'http://localhost:4000';
      const token = api.getAccessToken();
      const headers: Record<string, string> = {
        'Accept': 'application/json',
      };
      if (token) headers['Authorization'] = `Bearer ${token}`;

      const opts: RequestInit = {
        method,
        headers,
        credentials: 'include',
      };

      if ((method === 'POST' || method === 'PUT' || method === 'PATCH') && requestBody.trim()) {
        headers['Content-Type'] = 'application/json';
        opts.body = requestBody;
      }

      const res = await fetch(`${apiBase}${endpoint}`, opts);
      responseStatus = res.status;

      const text = await res.text();
      try {
        response = JSON.stringify(JSON.parse(text), null, 2);
      } catch {
        response = text;
      }
    } catch (e) {
      response = `Error: ${e instanceof Error ? e.message : 'Request failed'}`;
      responseStatus = 0;
    } finally {
      loading = false;
    }
  }
</script>

<svelte:head>
  <title>Developer Tools - HybridSocial</title>
</svelte:head>

<div class="dev-page">
  <h1 class="dev-title">Developer Tools</h1>
  <p class="dev-desc">Test API endpoints and explore the HybridSocial API.</p>

  <div class="dev-layout">
    <!-- Sidebar: common endpoints -->
    <div class="dev-sidebar">
      <h3 class="sidebar-heading">Common Endpoints</h3>
      {#each commonEndpoints as ep (ep.path)}
        <button
          type="button"
          class="endpoint-btn"
          class:active={endpoint === ep.path}
          onclick={() => selectEndpoint(ep)}
        >
          <span class="method-badge method-{ep.method.toLowerCase()}">{ep.method}</span>
          {ep.label}
        </button>
      {/each}

      {#if instanceInfo}
        <h3 class="sidebar-heading" style="margin-top: 16px">Instance</h3>
        <div class="instance-info">
          <div class="info-row"><span class="info-label">Version</span><span>{(instanceInfo as any).version || '?'}</span></div>
          <div class="info-row"><span class="info-label">Title</span><span>{(instanceInfo as any).title || '?'}</span></div>
          <div class="info-row"><span class="info-label">Users</span><span>{(instanceInfo as any).stats?.user_count ?? '?'}</span></div>
          <div class="info-row"><span class="info-label">Posts</span><span>{(instanceInfo as any).stats?.status_count ?? '?'}</span></div>
        </div>
      {/if}
    </div>

    <!-- Main: request builder -->
    <div class="dev-main">
      <div class="request-bar">
        <select class="method-select" bind:value={method}>
          <option>GET</option>
          <option>POST</option>
          <option>PUT</option>
          <option>PATCH</option>
          <option>DELETE</option>
        </select>
        <input type="text" class="endpoint-input" bind:value={endpoint} placeholder="/api/v1/..." />
        <button type="button" class="send-btn" onclick={sendRequest} disabled={loading}>
          {loading ? 'Sending...' : 'Send'}
        </button>
      </div>

      {#if method !== 'GET' && method !== 'DELETE'}
        <div class="body-section">
          <label class="body-label">Request Body (JSON)</label>
          <textarea class="body-input" bind:value={requestBody} rows={4} placeholder={'{"key": "value"}'}></textarea>
        </div>
      {/if}

      <div class="response-section">
        <div class="response-header">
          <span class="response-label">Response</span>
          {#if responseStatus > 0}
            <span class="status-badge" class:status-ok={responseStatus < 300} class:status-err={responseStatus >= 400}>
              {responseStatus}
            </span>
          {/if}
        </div>
        <pre class="response-body">{response || 'Send a request to see the response'}</pre>
      </div>
    </div>
  </div>
</div>

<style>
  .dev-page { max-width: 1000px; margin: 0 auto; }
  .dev-title { font-size: var(--text-2xl); font-weight: 700; margin-block-end: var(--space-2); }
  .dev-desc { font-size: var(--text-sm); color: var(--color-text-secondary); margin-block-end: var(--space-6); }

  .dev-layout { display: grid; grid-template-columns: 240px 1fr; gap: var(--space-4); }

  /* Sidebar */
  .dev-sidebar {
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: 14px;
    padding: 16px;
    align-self: start;
    position: sticky;
    top: calc(var(--header-height) + 16px);
  }

  .sidebar-heading { font-size: 0.7rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: var(--color-text-tertiary); margin-block-end: 8px; }

  .endpoint-btn {
    display: flex; align-items: center; gap: 8px;
    width: 100%; padding: 6px 8px; background: transparent; border: none; border-radius: 8px;
    font-size: 0.8125rem; color: var(--color-text-secondary); cursor: pointer; text-align: start;
    transition: background 150ms ease;
  }
  .endpoint-btn:hover { background: var(--color-surface); }
  .endpoint-btn.active { background: var(--color-primary-soft, rgba(0,128,128,0.08)); color: var(--color-primary); }

  .method-badge {
    font-size: 0.6rem; font-weight: 700; padding: 1px 5px; border-radius: 4px;
    text-transform: uppercase; flex-shrink: 0;
  }
  .method-get { background: #dbeafe; color: #1d4ed8; }
  .method-post { background: #dcfce7; color: #15803d; }
  .method-put { background: #fef3c7; color: #92400e; }
  .method-patch { background: #fef3c7; color: #92400e; }
  .method-delete { background: #fecaca; color: #dc2626; }

  .instance-info { display: flex; flex-direction: column; gap: 4px; }
  .info-row { display: flex; justify-content: space-between; font-size: 0.75rem; color: var(--color-text-secondary); }
  .info-label { font-weight: 600; color: var(--color-text-tertiary); }

  /* Main */
  .dev-main { display: flex; flex-direction: column; gap: 12px; }

  .request-bar { display: flex; gap: 8px; }
  .method-select {
    padding: 10px 12px; border: 1px solid var(--color-border); border-radius: 10px;
    font-size: 0.875rem; font-weight: 600; background: var(--color-surface); color: var(--color-text);
    width: 100px;
  }
  .endpoint-input {
    flex: 1; padding: 10px 14px; border: 1px solid var(--color-border); border-radius: 10px;
    font-size: 0.875rem; font-family: monospace; color: var(--color-text); background: var(--color-surface);
  }
  .endpoint-input:focus { outline: none; border-color: var(--color-primary); }

  .send-btn {
    padding: 10px 24px; background: var(--color-primary); color: white; border: none; border-radius: 10px;
    font-size: 0.875rem; font-weight: 600; cursor: pointer;
  }
  .send-btn:disabled { opacity: 0.5; cursor: not-allowed; }
  .send-btn:hover:not(:disabled) { opacity: 0.9; }

  .body-section { display: flex; flex-direction: column; gap: 6px; }
  .body-label { font-size: 0.75rem; font-weight: 600; color: var(--color-text-secondary); }
  .body-input {
    padding: 10px 14px; border: 1px solid var(--color-border); border-radius: 10px;
    font-size: 0.8125rem; font-family: monospace; color: var(--color-text); background: var(--color-surface);
    resize: vertical;
  }

  .response-section {
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: 14px;
    overflow: hidden;
  }

  .response-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 10px 16px; border-bottom: 1px solid var(--color-border);
  }
  .response-label { font-size: 0.75rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: var(--color-text-tertiary); }

  .status-badge { font-size: 0.75rem; font-weight: 700; padding: 2px 8px; border-radius: 6px; }
  .status-ok { background: #dcfce7; color: #15803d; }
  .status-err { background: #fecaca; color: #dc2626; }

  .response-body {
    padding: 16px; margin: 0; font-size: 0.8125rem; font-family: monospace;
    color: var(--color-text); white-space: pre-wrap; word-break: break-word;
    max-height: 500px; overflow-y: auto; line-height: 1.5;
  }

  @media (max-width: 768px) {
    .dev-layout { grid-template-columns: 1fr; }
    .dev-sidebar { position: static; }
  }
</style>
