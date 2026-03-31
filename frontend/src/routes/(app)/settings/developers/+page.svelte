<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface BotApp {
    id: string;
    name: string;
    client_id: string;
    scopes: string[];
    created_at: string;
  }

  interface BotEntry {
    id: string;
    name: string;
    handle: string;
    created_at: string;
    apps: BotApp[];
  }

  interface CreatedBot {
    bot: { id: string; name: string; handle: string };
    client_id: string;
    client_secret: string;
    access_token: string;
    note: string;
  }

  interface RegeneratedKeys {
    client_id: string;
    client_secret: string;
    access_token: string;
    note: string;
  }

  // State
  let bots = $state<BotEntry[]>([]);
  let loading = $state(true);

  // Create form
  let botName = $state('');
  let creating = $state(false);
  let createdResult = $state<CreatedBot | null>(null);
  let showCreateForm = $state(false);

  // Regenerated keys (shown once)
  let regeneratedKeys = $state<{ botId: string; keys: RegeneratedKeys } | null>(null);

  // Token visibility per bot
  let visibleTokens = $state<Set<string>>(new Set());

  // Confirmation states
  let confirmDeleteId = $state<string | null>(null);
  let confirmRegenerateId = $state<string | null>(null);
  let deleting = $state(false);
  let regenerating = $state(false);

  // API tester
  let method = $state('GET');
  let endpoint = $state('/api/v1/instance');
  let requestBody = $state('');
  let response = $state('');
  let responseStatus = $state(0);
  let testing = $state(false);

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
      bots = await api.get<BotEntry[]>('/api/v1/bots');
    } catch { /* */ }
    finally { loading = false; }
  });

  async function createBot() {
    if (!botName.trim() || creating) return;
    creating = true;
    createdResult = null;
    try {
      const result = await api.post<CreatedBot>('/api/v1/bots', { name: botName });
      createdResult = result;
      botName = '';
      // Refresh bots list
      bots = await api.get<BotEntry[]>('/api/v1/bots');
      addToast('Bot created', 'success');
    } catch {
      addToast('Failed to create bot', 'error');
    } finally { creating = false; }
  }

  async function deleteBot(id: string) {
    deleting = true;
    try {
      await api.delete(`/api/v1/bots/${id}`);
      bots = bots.filter(b => b.id !== id);
      confirmDeleteId = null;
      addToast('Bot deleted', 'success');
    } catch {
      addToast('Failed to delete bot', 'error');
    } finally { deleting = false; }
  }

  async function regenerateKeys(id: string) {
    regenerating = true;
    try {
      const result = await api.post<RegeneratedKeys>(`/api/v1/bots/${id}/regenerate`, {});
      regeneratedKeys = { botId: id, keys: result };
      confirmRegenerateId = null;
      // Refresh bots list
      bots = await api.get<BotEntry[]>('/api/v1/bots');
      addToast('Keys regenerated', 'success');
    } catch {
      addToast('Failed to regenerate keys', 'error');
    } finally { regenerating = false; }
  }

  function toggleTokenVisibility(botId: string) {
    const next = new Set(visibleTokens);
    if (next.has(botId)) {
      next.delete(botId);
    } else {
      next.add(botId);
    }
    visibleTokens = next;
  }

  function copyText(text: string) {
    navigator.clipboard.writeText(text);
    addToast('Copied to clipboard', 'success');
  }

  function dismissCreated() {
    createdResult = null;
    showCreateForm = false;
  }

  function dismissRegenerated() {
    regeneratedKeys = null;
  }

  async function sendRequest() {
    testing = true;
    response = '';
    responseStatus = 0;
    try {
      const apiBase = import.meta.env.VITE_API_URL || '';
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
  <p class="dev-subtitle">Create a bot to get API credentials for building integrations.</p>

  {#if loading}
    <div class="stitch-card" style="text-align: center; padding: 32px;">
      <Spinner />
    </div>
  {:else}

    <!-- Created Bot Success Screen -->
    {#if createdResult}
      <div class="stitch-card">
        <div class="created-result">
          <div class="created-header">
            <span class="material-symbols-outlined" style="font-size: 24px; color: var(--color-success)">check_circle</span>
            <strong>Bot "{createdResult.bot.name}" created!</strong>
          </div>
          <p class="created-warning">Save these credentials now -- they will not be shown again.</p>

          <div class="credential-row">
            <span class="credential-label">Bot Handle</span>
            <div class="credential-value">
              <code>@{createdResult.bot.handle}</code>
            </div>
          </div>

          <div class="credential-row">
            <span class="credential-label">Client ID</span>
            <div class="credential-value">
              <code>{createdResult.client_id}</code>
              <button type="button" class="copy-btn" onclick={() => copyText(createdResult!.client_id)}>
                <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
              </button>
            </div>
          </div>

          <div class="credential-row">
            <span class="credential-label">Client Secret (shown once -- save it now!)</span>
            <div class="credential-value secret">
              <code>{createdResult.client_secret}</code>
              <button type="button" class="copy-btn" onclick={() => copyText(createdResult!.client_secret)}>
                <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
              </button>
            </div>
          </div>

          <div class="credential-row">
            <span class="credential-label">Access Token (Bearer token for API requests)</span>
            <div class="credential-value secret">
              <code>{createdResult.access_token}</code>
              <button type="button" class="copy-btn" onclick={() => copyText(createdResult!.access_token)}>
                <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
              </button>
            </div>
          </div>

          <div class="credential-row">
            <span class="credential-label">Usage example</span>
            <pre class="usage-example">curl -H "Authorization: Bearer {createdResult.access_token}" \
  {typeof window !== 'undefined' ? window.location.origin : ''}/api/v1/accounts/verify_credentials</pre>
          </div>

          <button type="button" class="dismiss-btn" onclick={dismissCreated}>I've saved my credentials</button>
        </div>
      </div>
    {/if}

    <!-- Regenerated Keys Success Screen -->
    {#if regeneratedKeys}
      <div class="stitch-card">
        <div class="created-result">
          <div class="created-header">
            <span class="material-symbols-outlined" style="font-size: 24px; color: var(--color-success)">key</span>
            <strong>New API keys generated</strong>
          </div>
          <p class="created-warning">Save these credentials now -- they will not be shown again.</p>

          <div class="credential-row">
            <span class="credential-label">Client ID</span>
            <div class="credential-value">
              <code>{regeneratedKeys.keys.client_id}</code>
              <button type="button" class="copy-btn" onclick={() => copyText(regeneratedKeys!.keys.client_id)}>
                <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
              </button>
            </div>
          </div>

          <div class="credential-row">
            <span class="credential-label">Client Secret (shown once)</span>
            <div class="credential-value secret">
              <code>{regeneratedKeys.keys.client_secret}</code>
              <button type="button" class="copy-btn" onclick={() => copyText(regeneratedKeys!.keys.client_secret)}>
                <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
              </button>
            </div>
          </div>

          <div class="credential-row">
            <span class="credential-label">Access Token</span>
            <div class="credential-value secret">
              <code>{regeneratedKeys.keys.access_token}</code>
              <button type="button" class="copy-btn" onclick={() => copyText(regeneratedKeys!.keys.access_token)}>
                <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
              </button>
            </div>
          </div>

          <button type="button" class="dismiss-btn" onclick={dismissRegenerated}>I've saved my credentials</button>
        </div>
      </div>
    {/if}

    <!-- No Bots: Create First Bot -->
    {#if bots.length === 0 && !createdResult}
      <div class="stitch-card empty-state">
        <span class="material-symbols-outlined empty-icon">smart_toy</span>
        <h2 class="stitch-section-title">Create Your First Bot</h2>
        <p class="stitch-desc">Bots let you interact with the API programmatically. Create one to get started with API credentials.</p>

        <div class="create-form">
          <div class="stitch-field">
            <label class="stitch-label" for="bot-name">Bot Name</label>
            <input id="bot-name" type="text" class="stitch-input" bind:value={botName} placeholder="My Awesome Bot" onkeydown={(e) => e.key === 'Enter' && createBot()} />
          </div>

          <button type="button" class="stitch-btn-primary" onclick={createBot} disabled={!botName.trim() || creating}>
            {creating ? 'Creating...' : 'Create Bot'}
          </button>
        </div>
      </div>
    {/if}

    <!-- Existing Bots -->
    {#if bots.length > 0}
      <div class="bots-list">
        {#each bots as bot (bot.id)}
          <div class="stitch-card bot-card">
            <div class="bot-header">
              <div class="bot-identity">
                <span class="material-symbols-outlined bot-avatar">smart_toy</span>
                <div>
                  <div class="bot-name">{bot.name}</div>
                  <div class="bot-handle">@{bot.handle}</div>
                </div>
              </div>
              <div class="bot-actions">
                {#if confirmRegenerateId === bot.id}
                  <div class="confirm-bar">
                    <span class="confirm-text">Regenerate keys?</span>
                    <button type="button" class="confirm-yes" onclick={() => regenerateKeys(bot.id)} disabled={regenerating}>
                      {regenerating ? '...' : 'Yes'}
                    </button>
                    <button type="button" class="confirm-no" onclick={() => confirmRegenerateId = null}>No</button>
                  </div>
                {:else if confirmDeleteId === bot.id}
                  <div class="confirm-bar">
                    <span class="confirm-text">Delete this bot?</span>
                    <button type="button" class="confirm-yes danger" onclick={() => deleteBot(bot.id)} disabled={deleting}>
                      {deleting ? '...' : 'Yes, delete'}
                    </button>
                    <button type="button" class="confirm-no" onclick={() => confirmDeleteId = null}>Cancel</button>
                  </div>
                {:else}
                  <button type="button" class="action-btn" onclick={() => confirmRegenerateId = bot.id} title="Regenerate API keys">
                    <span class="material-symbols-outlined" style="font-size: 18px">key</span>
                  </button>
                  <button type="button" class="action-btn danger" onclick={() => confirmDeleteId = bot.id} title="Delete bot">
                    <span class="material-symbols-outlined" style="font-size: 18px">delete</span>
                  </button>
                {/if}
              </div>
            </div>

            {#if bot.apps.length > 0}
              {@const app = bot.apps[0]}
              <div class="bot-credentials">
                <div class="credential-row">
                  <span class="credential-label">Client ID</span>
                  <div class="credential-value">
                    <code>{app.client_id}</code>
                    <button type="button" class="copy-btn" onclick={() => copyText(app.client_id)}>
                      <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
                    </button>
                  </div>
                </div>
              </div>
            {:else}
              <p class="stitch-empty" style="font-size: 0.8rem;">No API keys. Click the key icon to generate new ones.</p>
            {/if}
          </div>
        {/each}
      </div>

      <!-- Create Another Bot -->
      {#if !createdResult}
        {#if showCreateForm}
          <div class="stitch-card">
            <h2 class="stitch-section-title">Create Another Bot</h2>
            <div class="create-form">
              <div class="stitch-field">
                <label class="stitch-label" for="bot-name-new">Bot Name</label>
                <input id="bot-name-new" type="text" class="stitch-input" bind:value={botName} placeholder="Another Bot" onkeydown={(e) => e.key === 'Enter' && createBot()} />
              </div>
              <div class="form-actions">
                <button type="button" class="stitch-btn-primary" onclick={createBot} disabled={!botName.trim() || creating}>
                  {creating ? 'Creating...' : 'Create Bot'}
                </button>
                <button type="button" class="stitch-btn-secondary" onclick={() => { showCreateForm = false; botName = ''; }}>
                  Cancel
                </button>
              </div>
            </div>
          </div>
        {:else}
          <button type="button" class="create-another-btn" onclick={() => showCreateForm = true}>
            <span class="material-symbols-outlined" style="font-size: 18px">add</span>
            Create Another Bot
          </button>
        {/if}
      {/if}
    {/if}
  {/if}

  <!-- API Tester -->
  <div class="stitch-card" style="margin-top: var(--space-6);">
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
  .dev-title { font-size: var(--text-2xl); font-weight: 700; margin-block-end: var(--space-1); }
  .dev-subtitle { font-size: var(--text-sm); color: var(--color-text-secondary); margin-block-end: var(--space-6); }

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
  .stitch-btn-secondary { padding: 10px 24px; background: transparent; color: var(--color-text-secondary); border: 1px solid var(--color-border); border-radius: 9999px; font-size: 0.875rem; font-weight: 600; cursor: pointer; }
  .stitch-btn-secondary:hover { border-color: var(--color-text-tertiary); }

  /* Empty state */
  .empty-state { text-align: center; padding: var(--space-8) var(--space-5); }
  .empty-state .stitch-section-title { margin-block-end: var(--space-2); }
  .empty-state .create-form { max-width: 400px; margin: 0 auto; text-align: start; }
  .empty-icon { font-size: 48px; color: var(--color-text-tertiary); margin-block-end: var(--space-3); display: block; }

  /* Bot cards */
  .bots-list { display: flex; flex-direction: column; gap: var(--space-3); }
  .bot-card { padding: var(--space-4); }
  .bot-header { display: flex; align-items: center; justify-content: space-between; margin-block-end: var(--space-3); }
  .bot-identity { display: flex; align-items: center; gap: var(--space-3); }
  .bot-avatar { font-size: 32px; color: var(--color-primary); background: var(--color-primary-soft, rgba(0,128,128,0.08)); border-radius: 10px; padding: 6px; }
  .bot-name { font-size: 0.9375rem; font-weight: 600; color: var(--color-text); }
  .bot-handle { font-size: 0.8125rem; color: var(--color-text-tertiary); }

  .bot-actions { display: flex; align-items: center; gap: 4px; }
  .action-btn { background: none; border: none; color: var(--color-text-tertiary); cursor: pointer; padding: 6px; border-radius: 8px; display: flex; align-items: center; }
  .action-btn:hover { background: var(--color-surface); color: var(--color-text-secondary); }
  .action-btn.danger:hover { color: var(--color-danger, #ef4444); background: rgba(239,68,68,0.08); }

  .confirm-bar { display: flex; align-items: center; gap: 6px; font-size: 0.8125rem; }
  .confirm-text { color: var(--color-text-secondary); font-weight: 500; }
  .confirm-yes { padding: 4px 12px; background: var(--color-primary); color: white; border: none; border-radius: 6px; font-size: 0.75rem; font-weight: 600; cursor: pointer; }
  .confirm-yes.danger { background: var(--color-danger, #ef4444); }
  .confirm-yes:disabled { opacity: 0.5; }
  .confirm-no { padding: 4px 12px; background: transparent; color: var(--color-text-secondary); border: 1px solid var(--color-border); border-radius: 6px; font-size: 0.75rem; font-weight: 600; cursor: pointer; }

  .bot-credentials { margin-top: var(--space-2); }

  /* Credentials */
  .created-result { padding: 16px; background: var(--color-surface); border-radius: 12px; }
  .created-header { display: flex; align-items: center; gap: 8px; font-size: 0.9375rem; margin-block-end: 8px; }
  .created-warning { font-size: 0.8125rem; color: var(--color-warning, #f59e0b); font-weight: 500; margin-block-end: 16px; }

  .credential-row { margin-block-end: 12px; }
  .credential-label { display: block; font-size: 0.7rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--color-text-tertiary); margin-block-end: 4px; }
  .credential-value { display: flex; align-items: center; gap: 8px; padding: 8px 12px; background: var(--color-surface-container-lowest); border: 1px solid var(--color-border); border-radius: 8px; }
  .credential-value code { flex: 1; font-size: 0.75rem; word-break: break-all; color: var(--color-text); }
  .credential-value.secret { border-color: var(--color-warning, #f59e0b); }
  .copy-btn { background: none; border: none; color: var(--color-text-tertiary); cursor: pointer; padding: 2px; border-radius: 4px; flex-shrink: 0; display: flex; }
  .copy-btn:hover { color: var(--color-primary); background: var(--color-surface); }

  .usage-example { font-size: 0.75rem; padding: 10px 12px; background: #1e1e2e; color: #cdd6f4; border-radius: 8px; overflow-x: auto; white-space: pre-wrap; word-break: break-all; }

  .dismiss-btn { margin-top: 12px; padding: 8px 20px; background: var(--color-primary); color: white; border: none; border-radius: 9999px; font-size: 0.8125rem; font-weight: 600; cursor: pointer; }

  .form-actions { display: flex; gap: 8px; }

  .create-another-btn {
    display: flex; align-items: center; gap: 6px; justify-content: center;
    width: 100%; padding: 12px; background: transparent; border: 2px dashed var(--color-border);
    border-radius: var(--radius-xl); font-size: 0.875rem; font-weight: 600;
    color: var(--color-text-secondary); cursor: pointer; transition: all 150ms ease;
  }
  .create-another-btn:hover { border-color: var(--color-primary); color: var(--color-primary); }

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
</style>
