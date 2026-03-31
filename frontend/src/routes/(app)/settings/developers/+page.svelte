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

  interface PersonalApp {
    id: string;
    name: string;
    client_id: string;
    scopes: string[];
  }

  interface CreatedCredentials {
    type: 'personal' | 'bot';
    bot?: { id: string; name: string; handle: string };
    app?: PersonalApp;
    client_id: string;
    client_secret: string;
    access_token: string;
  }

  interface RegeneratedKeys {
    client_id: string;
    client_secret: string;
    access_token: string;
  }

  // State
  let bots = $state<BotEntry[]>([]);
  let personalApps = $state<PersonalApp[]>([]);
  let loading = $state(true);

  // Wizard
  let wizardStep = $state<'choice' | 'personal' | 'bot' | null>(null);
  let appName = $state('');
  let botName = $state('');
  let creating = $state(false);
  let createdResult = $state<CreatedCredentials | null>(null);

  // Regenerated keys
  let regeneratedKeys = $state<{ id: string; type: 'bot' | 'personal'; keys: RegeneratedKeys } | null>(null);

  // Confirmation states
  let confirmDeleteId = $state<string | null>(null);
  let confirmDeleteType = $state<'bot' | 'personal' | null>(null);
  let confirmRegenerateId = $state<string | null>(null);
  let confirmRegenerateType = $state<'bot' | 'personal' | null>(null);
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

  let hasExistingItems = $derived(bots.length > 0 || personalApps.length > 0);

  onMount(async () => {
    try {
      const [botsResult, appsResult] = await Promise.all([
        api.get<BotEntry[]>('/api/v1/bots'),
        api.get<PersonalApp[]>('/api/v1/apps'),
      ]);
      bots = botsResult;
      personalApps = appsResult;
    } catch { /* */ }
    finally { loading = false; }
  });

  function startWizard() {
    wizardStep = 'choice';
    appName = '';
    botName = '';
    createdResult = null;
  }

  function cancelWizard() {
    wizardStep = null;
    appName = '';
    botName = '';
  }

  async function createPersonalApp() {
    if (!appName.trim() || creating) return;
    creating = true;
    try {
      const result = await api.post<{ app: PersonalApp; access_token: string; client_secret?: string }>('/api/v1/apps/with_token', {
        name: appName,
        scopes: ['read', 'write', 'follow', 'push'],
      });
      createdResult = {
        type: 'personal',
        app: result.app,
        client_id: result.app.client_id,
        client_secret: result.app.client_secret || result.client_secret || '',
        access_token: result.access_token,
      };
      personalApps = await api.get<PersonalApp[]>('/api/v1/apps');
      wizardStep = null;
      addToast('API app created', 'success');
    } catch {
      addToast('Failed to create app', 'error');
    } finally { creating = false; }
  }

  async function createBot() {
    if (!botName.trim() || creating) return;
    creating = true;
    try {
      const result = await api.post<{ bot: { id: string; name: string; handle: string }; client_id: string; client_secret: string; access_token: string }>('/api/v1/bots', { name: botName });
      createdResult = {
        type: 'bot',
        bot: result.bot,
        client_id: result.client_id,
        client_secret: result.client_secret,
        access_token: result.access_token,
      };
      bots = await api.get<BotEntry[]>('/api/v1/bots');
      wizardStep = null;
      addToast('Bot created', 'success');
    } catch {
      addToast('Failed to create bot', 'error');
    } finally { creating = false; }
  }

  async function deleteItem(id: string, type: 'bot' | 'personal') {
    deleting = true;
    try {
      if (type === 'bot') {
        await api.delete(`/api/v1/bots/${id}`);
        bots = bots.filter(b => b.id !== id);
      } else {
        await api.delete(`/api/v1/apps/${id}`);
        personalApps = personalApps.filter(a => a.id !== id);
      }
      confirmDeleteId = null;
      confirmDeleteType = null;
      addToast(`${type === 'bot' ? 'Bot' : 'App'} deleted`, 'success');
    } catch {
      addToast('Failed to delete', 'error');
    } finally { deleting = false; }
  }

  async function regenerateKeys(id: string, type: 'bot' | 'personal') {
    regenerating = true;
    try {
      if (type === 'bot') {
        const result = await api.post<RegeneratedKeys>(`/api/v1/bots/${id}/regenerate`, {});
        regeneratedKeys = { id, type, keys: result };
        bots = await api.get<BotEntry[]>('/api/v1/bots');
      } else {
        // For personal apps, delete and recreate
        const app = personalApps.find(a => a.id === id);
        if (app) {
          await api.delete(`/api/v1/apps/${id}`);
          const result = await api.post<{ app: PersonalApp; access_token: string; client_secret?: string }>('/api/v1/apps/with_token', {
            name: app.name,
            scopes: app.scopes,
          });
          regeneratedKeys = {
            id: result.app.id,
            type: 'personal',
            keys: {
              client_id: result.app.client_id,
              client_secret: result.app.client_secret || result.client_secret || '',
              access_token: result.access_token,
            }
          };
          personalApps = await api.get<PersonalApp[]>('/api/v1/apps');
        }
      }
      confirmRegenerateId = null;
      confirmRegenerateType = null;
      addToast('Keys regenerated', 'success');
    } catch {
      addToast('Failed to regenerate keys', 'error');
    } finally { regenerating = false; }
  }

  function copyText(text: string) {
    navigator.clipboard.writeText(text);
    addToast('Copied to clipboard', 'success');
  }

  function dismissCreated() {
    createdResult = null;
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
  <p class="dev-subtitle">Build integrations with the API using your own profile or a bot.</p>

  {#if loading}
    <div class="stitch-card" style="text-align: center; padding: 32px;">
      <Spinner />
    </div>
  {:else}

    <!-- Credential Display (after create or regenerate) -->
    {#if createdResult}
      <div class="stitch-card">
        <div class="created-result">
          <div class="created-header">
            <span class="material-symbols-outlined" style="font-size: 24px; color: var(--color-success)">check_circle</span>
            <strong>
              {#if createdResult.type === 'bot'}
                Bot "@{createdResult.bot?.handle}" created!
              {:else}
                API app "{createdResult.app?.name}" created!
              {/if}
            </strong>
          </div>
          <p class="created-warning">Save these credentials now -- they will not be shown again.</p>

          {#if createdResult.type === 'bot' && createdResult.bot}
            <div class="credential-row">
              <span class="credential-label">Bot Handle</span>
              <div class="credential-value"><code>@{createdResult.bot.handle}</code></div>
            </div>
          {/if}

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
            <span class="credential-label">Client Secret (shown once)</span>
            <div class="credential-value secret">
              <code>{createdResult.client_secret}</code>
              <button type="button" class="copy-btn" onclick={() => copyText(createdResult!.client_secret)}>
                <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
              </button>
            </div>
          </div>

          <div class="credential-row">
            <span class="credential-label">Access Token (Bearer token)</span>
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

    {#if regeneratedKeys}
      <div class="stitch-card">
        <div class="created-result">
          <div class="created-header">
            <span class="material-symbols-outlined" style="font-size: 24px; color: var(--color-success)">key</span>
            <strong>New API keys generated</strong>
          </div>
          <p class="created-warning">Save these credentials now -- they will not be shown again.</p>

          {#each [['Client ID', regeneratedKeys.keys.client_id, false], ['Client Secret (shown once)', regeneratedKeys.keys.client_secret, true], ['Access Token', regeneratedKeys.keys.access_token, true]] as [label, value, isSecret]}
            <div class="credential-row">
              <span class="credential-label">{label}</span>
              <div class="credential-value" class:secret={isSecret}>
                <code>{value}</code>
                <button type="button" class="copy-btn" onclick={() => copyText(String(value))}>
                  <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
                </button>
              </div>
            </div>
          {/each}

          <button type="button" class="dismiss-btn" onclick={dismissRegenerated}>I've saved my credentials</button>
        </div>
      </div>
    {/if}

    <!-- Wizard -->
    {#if wizardStep === 'choice'}
      <div class="stitch-card wizard-card">
        <h2 class="stitch-section-title">What would you like to do?</h2>
        <p class="stitch-desc">Choose how you want to use the API.</p>

        <div class="wizard-options">
          <button type="button" class="wizard-option" onclick={() => wizardStep = 'personal'}>
            <span class="material-symbols-outlined wizard-option-icon">person</span>
            <div class="wizard-option-text">
              <strong>Use my own profile</strong>
              <span>Post, read, and interact as yourself via the API.</span>
            </div>
            <span class="material-symbols-outlined wizard-arrow">chevron_right</span>
          </button>

          <button type="button" class="wizard-option" onclick={() => wizardStep = 'bot'}>
            <span class="material-symbols-outlined wizard-option-icon">smart_toy</span>
            <div class="wizard-option-text">
              <strong>Create a bot</strong>
              <span>Create a separate bot profile that posts on its own.</span>
            </div>
            <span class="material-symbols-outlined wizard-arrow">chevron_right</span>
          </button>
        </div>

        <button type="button" class="cancel-link" onclick={cancelWizard}>Cancel</button>
      </div>

    {:else if wizardStep === 'personal'}
      <div class="stitch-card">
        <h2 class="stitch-section-title">Create API App</h2>
        <p class="stitch-desc">This app will act as you -- posts will appear on your profile.</p>

        <div class="create-form">
          <div class="stitch-field">
            <label class="stitch-label" for="app-name">App Name</label>
            <input id="app-name" type="text" class="stitch-input" bind:value={appName} placeholder="My Integration" onkeydown={(e) => e.key === 'Enter' && createPersonalApp()} />
          </div>

          <div class="form-actions">
            <button type="button" class="stitch-btn-primary" onclick={createPersonalApp} disabled={!appName.trim() || creating}>
              {creating ? 'Creating...' : 'Create App'}
            </button>
            <button type="button" class="stitch-btn-secondary" onclick={cancelWizard}>Back</button>
          </div>
        </div>
      </div>

    {:else if wizardStep === 'bot'}
      <div class="stitch-card">
        <h2 class="stitch-section-title">Create a Bot</h2>
        <p class="stitch-desc">The bot gets its own profile and handle. Posts will appear on the bot's profile, not yours.</p>

        <div class="create-form">
          <div class="stitch-field">
            <label class="stitch-label" for="bot-name">Bot Name</label>
            <input id="bot-name" type="text" class="stitch-input" bind:value={botName} placeholder="My Awesome Bot" onkeydown={(e) => e.key === 'Enter' && createBot()} />
          </div>

          <div class="form-actions">
            <button type="button" class="stitch-btn-primary" onclick={createBot} disabled={!botName.trim() || creating}>
              {creating ? 'Creating...' : 'Create Bot'}
            </button>
            <button type="button" class="stitch-btn-secondary" onclick={cancelWizard}>Back</button>
          </div>
        </div>
      </div>
    {/if}

    <!-- Empty state -->
    {#if !hasExistingItems && !wizardStep && !createdResult}
      <div class="stitch-card empty-state">
        <span class="material-symbols-outlined empty-icon">code</span>
        <h2 class="stitch-section-title">Get started with the API</h2>
        <p class="stitch-desc">Create an API app to post as yourself, or spin up a bot with its own profile.</p>
        <button type="button" class="stitch-btn-primary" onclick={startWizard}>Get Started</button>
      </div>
    {/if}

    <!-- Existing Personal Apps -->
    {#if personalApps.length > 0}
      <h2 class="section-heading">Your API Apps</h2>
      <div class="items-list">
        {#each personalApps as app (app.id)}
          <div class="stitch-card item-card">
            <div class="item-header">
              <div class="item-identity">
                <span class="material-symbols-outlined item-avatar">person</span>
                <div>
                  <div class="item-name">{app.name}</div>
                  <div class="item-meta">Posts as your profile</div>
                </div>
              </div>
              <div class="item-actions">
                {#if confirmRegenerateId === app.id && confirmRegenerateType === 'personal'}
                  <div class="confirm-bar">
                    <span class="confirm-text">Regenerate keys?</span>
                    <button type="button" class="confirm-yes" onclick={() => regenerateKeys(app.id, 'personal')} disabled={regenerating}>{regenerating ? '...' : 'Yes'}</button>
                    <button type="button" class="confirm-no" onclick={() => { confirmRegenerateId = null; confirmRegenerateType = null; }}>No</button>
                  </div>
                {:else if confirmDeleteId === app.id && confirmDeleteType === 'personal'}
                  <div class="confirm-bar">
                    <span class="confirm-text">Delete this app?</span>
                    <button type="button" class="confirm-yes danger" onclick={() => deleteItem(app.id, 'personal')} disabled={deleting}>{deleting ? '...' : 'Delete'}</button>
                    <button type="button" class="confirm-no" onclick={() => { confirmDeleteId = null; confirmDeleteType = null; }}>Cancel</button>
                  </div>
                {:else}
                  <button type="button" class="action-btn" onclick={() => { confirmRegenerateId = app.id; confirmRegenerateType = 'personal'; }} title="Regenerate keys">
                    <span class="material-symbols-outlined" style="font-size: 18px">key</span>
                  </button>
                  <button type="button" class="action-btn danger" onclick={() => { confirmDeleteId = app.id; confirmDeleteType = 'personal'; }} title="Delete app">
                    <span class="material-symbols-outlined" style="font-size: 18px">delete</span>
                  </button>
                {/if}
              </div>
            </div>
            <div class="item-credentials">
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
          </div>
        {/each}
      </div>
    {/if}

    <!-- Existing Bots -->
    {#if bots.length > 0}
      <h2 class="section-heading">Your Bots</h2>
      <div class="items-list">
        {#each bots as bot (bot.id)}
          <div class="stitch-card item-card">
            <div class="item-header">
              <div class="item-identity">
                <span class="material-symbols-outlined item-avatar bot">smart_toy</span>
                <div>
                  <div class="item-name">{bot.name}</div>
                  <div class="item-meta">@{bot.handle}</div>
                </div>
              </div>
              <div class="item-actions">
                {#if confirmRegenerateId === bot.id && confirmRegenerateType === 'bot'}
                  <div class="confirm-bar">
                    <span class="confirm-text">Regenerate keys?</span>
                    <button type="button" class="confirm-yes" onclick={() => regenerateKeys(bot.id, 'bot')} disabled={regenerating}>{regenerating ? '...' : 'Yes'}</button>
                    <button type="button" class="confirm-no" onclick={() => { confirmRegenerateId = null; confirmRegenerateType = null; }}>No</button>
                  </div>
                {:else if confirmDeleteId === bot.id && confirmDeleteType === 'bot'}
                  <div class="confirm-bar">
                    <span class="confirm-text">Delete this bot?</span>
                    <button type="button" class="confirm-yes danger" onclick={() => deleteItem(bot.id, 'bot')} disabled={deleting}>{deleting ? '...' : 'Delete'}</button>
                    <button type="button" class="confirm-no" onclick={() => { confirmDeleteId = null; confirmDeleteType = null; }}>Cancel</button>
                  </div>
                {:else}
                  <button type="button" class="action-btn" onclick={() => { confirmRegenerateId = bot.id; confirmRegenerateType = 'bot'; }} title="Regenerate keys">
                    <span class="material-symbols-outlined" style="font-size: 18px">key</span>
                  </button>
                  <button type="button" class="action-btn danger" onclick={() => { confirmDeleteId = bot.id; confirmDeleteType = 'bot'; }} title="Delete bot">
                    <span class="material-symbols-outlined" style="font-size: 18px">delete</span>
                  </button>
                {/if}
              </div>
            </div>
            {#if bot.apps.length > 0}
              <div class="item-credentials">
                <div class="credential-row">
                  <span class="credential-label">Client ID</span>
                  <div class="credential-value">
                    <code>{bot.apps[0].client_id}</code>
                    <button type="button" class="copy-btn" onclick={() => copyText(bot.apps[0].client_id)}>
                      <span class="material-symbols-outlined" style="font-size: 16px">content_copy</span>
                    </button>
                  </div>
                </div>
              </div>
            {:else}
              <p class="no-keys">No API keys. Click the key icon to generate new ones.</p>
            {/if}
          </div>
        {/each}
      </div>
    {/if}

    <!-- Create new button -->
    {#if hasExistingItems && !wizardStep && !createdResult}
      <button type="button" class="create-another-btn" onclick={startWizard}>
        <span class="material-symbols-outlined" style="font-size: 18px">add</span>
        Create Another App or Bot
      </button>
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
  .stitch-field { margin-block-end: var(--space-3); }
  .stitch-label { display: block; font-size: 0.75rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: var(--color-text-secondary); margin-block-end: 6px; }
  .stitch-input { width: 100%; padding: 10px 14px; border: 1px solid var(--color-border); border-radius: 10px; font-size: 0.875rem; color: var(--color-text); background: var(--color-surface); }
  .stitch-input:focus { outline: none; border-color: var(--color-primary); }
  .stitch-btn-primary { padding: 10px 24px; background: var(--color-primary); color: white; border: none; border-radius: 9999px; font-size: 0.875rem; font-weight: 600; cursor: pointer; }
  .stitch-btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }
  .stitch-btn-secondary { padding: 10px 24px; background: transparent; color: var(--color-text-secondary); border: 1px solid var(--color-border); border-radius: 9999px; font-size: 0.875rem; font-weight: 600; cursor: pointer; }
  .stitch-btn-secondary:hover { border-color: var(--color-text-tertiary); }

  /* Wizard */
  .wizard-card { text-align: center; }
  .wizard-card .stitch-section-title { margin-block-end: var(--space-1); }
  .wizard-options { display: flex; flex-direction: column; gap: var(--space-3); margin-block-end: var(--space-4); text-align: start; }

  .wizard-option {
    display: flex; align-items: center; gap: var(--space-3); padding: var(--space-4);
    background: var(--color-surface); border: 2px solid var(--color-border);
    border-radius: var(--radius-xl); cursor: pointer; transition: all 150ms ease; width: 100%;
  }
  .wizard-option:hover { border-color: var(--color-primary); background: var(--color-primary-soft, rgba(0,128,128,0.04)); }
  .wizard-option-icon { font-size: 28px; color: var(--color-primary); background: var(--color-primary-soft, rgba(0,128,128,0.08)); border-radius: 10px; padding: 8px; flex-shrink: 0; }
  .wizard-option-text { flex: 1; }
  .wizard-option-text strong { display: block; font-size: 0.9375rem; color: var(--color-text); margin-block-end: 2px; }
  .wizard-option-text span { font-size: 0.8125rem; color: var(--color-text-secondary); }
  .wizard-arrow { color: var(--color-text-tertiary); flex-shrink: 0; }

  .cancel-link { background: none; border: none; color: var(--color-text-tertiary); font-size: 0.8125rem; cursor: pointer; padding: 4px 8px; }
  .cancel-link:hover { color: var(--color-text-secondary); }

  /* Empty state */
  .empty-state { text-align: center; padding: var(--space-8) var(--space-5); }
  .empty-state .stitch-section-title { margin-block-end: var(--space-2); }
  .empty-icon { font-size: 48px; color: var(--color-text-tertiary); margin-block-end: var(--space-3); display: block; }

  /* Sections */
  .section-heading { font-size: var(--text-sm); font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: var(--color-text-tertiary); margin-block-end: var(--space-3); margin-block-start: var(--space-4); }
  .items-list { display: flex; flex-direction: column; gap: var(--space-3); }

  /* Item cards */
  .item-card { padding: var(--space-4); }
  .item-header { display: flex; align-items: center; justify-content: space-between; margin-block-end: var(--space-3); }
  .item-identity { display: flex; align-items: center; gap: var(--space-3); }
  .item-avatar { font-size: 28px; color: var(--color-primary); background: var(--color-primary-soft, rgba(0,128,128,0.08)); border-radius: 10px; padding: 6px; }
  .item-avatar.bot { color: var(--color-primary); }
  .item-name { font-size: 0.9375rem; font-weight: 600; color: var(--color-text); }
  .item-meta { font-size: 0.8125rem; color: var(--color-text-tertiary); }
  .item-credentials { margin-top: var(--space-2); }
  .no-keys { font-size: 0.8rem; color: var(--color-text-tertiary); }

  .item-actions { display: flex; align-items: center; gap: 4px; }
  .action-btn { background: none; border: none; color: var(--color-text-tertiary); cursor: pointer; padding: 6px; border-radius: 8px; display: flex; align-items: center; }
  .action-btn:hover { background: var(--color-surface); color: var(--color-text-secondary); }
  .action-btn.danger:hover { color: var(--color-danger, #ef4444); background: rgba(239,68,68,0.08); }

  .confirm-bar { display: flex; align-items: center; gap: 6px; font-size: 0.8125rem; }
  .confirm-text { color: var(--color-text-secondary); font-weight: 500; }
  .confirm-yes { padding: 4px 12px; background: var(--color-primary); color: white; border: none; border-radius: 6px; font-size: 0.75rem; font-weight: 600; cursor: pointer; }
  .confirm-yes.danger { background: var(--color-danger, #ef4444); }
  .confirm-yes:disabled { opacity: 0.5; }
  .confirm-no { padding: 4px 12px; background: transparent; color: var(--color-text-secondary); border: 1px solid var(--color-border); border-radius: 6px; font-size: 0.75rem; font-weight: 600; cursor: pointer; }

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
  .create-form { max-width: 400px; }

  .create-another-btn {
    display: flex; align-items: center; gap: 6px; justify-content: center;
    width: 100%; padding: 12px; margin-top: var(--space-4); background: transparent; border: 2px dashed var(--color-border);
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
