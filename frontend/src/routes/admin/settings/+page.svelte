<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getAdminSettings, updateAdminSettings } from '$lib/api/admin.js';
  import type { AdminSetting } from '$lib/api/types.js';

  let settings: AdminSetting[] = $state([]);
  let loading = $state(true);
  let savingCategory = $state('');

  // Editable values indexed by setting key
  let editValues: Record<string, string> = $state({});

  const categoryOrder = ['general', 'limits', 'registration', 'federation', 'media', 'security', 'search', 'apps', 'premium'];
  const hiddenCategories = new Set(['tiers']);

  const categoryLabels: Record<string, string> = {
    general: 'General',
    limits: 'Limits',
    registration: 'Registration',
    federation: 'Federation',
    media: 'Media',
    security: 'Security & Rate Limiting',
    search: 'Search',
    apps: 'Mobile Apps',
    premium: 'Premium'
  };

  let groupedSettings = $derived(() => {
    const groups: Record<string, AdminSetting[]> = {};
    for (const s of settings) {
      const cat = (s.category || 'general').toLowerCase();
      if (hiddenCategories.has(cat)) continue;
      if (!groups[cat]) groups[cat] = [];
      groups[cat].push(s);
    }
    const sorted: [string, AdminSetting[]][] = [];
    for (const cat of categoryOrder) {
      if (groups[cat]) sorted.push([cat, groups[cat]]);
    }
    for (const [cat, items] of Object.entries(groups)) {
      if (!categoryOrder.includes(cat)) sorted.push([cat, items]);
    }
    return sorted;
  });

  onMount(async () => {
    try {
      settings = await getAdminSettings();
      for (const s of settings) {
        editValues[s.key] = s.value;
      }
    } catch {
      addToast('Failed to load settings', 'error');
    } finally {
      loading = false;
    }
  });

  async function saveCategory(category: string) {
    const categorySettings = settings.filter((s) => (s.category || 'general').toLowerCase() === category);
    const changed = categorySettings.filter((s) => editValues[s.key] !== s.value);
    if (changed.length === 0) {
      addToast('No changes to save', 'info');
      return;
    }

    savingCategory = category;
    try {
      const updated = await updateAdminSettings(
        changed.map((s) => ({ key: s.key, value: editValues[s.key] }))
      );
      // Update local state
      for (const u of updated) {
        const idx = settings.findIndex((s) => s.key === u.key);
        if (idx >= 0) {
          settings[idx] = u;
        }
      }
      settings = [...settings];
      addToast(`${category} settings saved`, 'success');
    } catch {
      addToast(`Failed to save ${category} settings`, 'error');
    } finally {
      savingCategory = '';
    }
  }

  // Dropdown options for specific settings
  const dropdownOptions: Record<string, { value: string; label: string }[]> = {
    registration_mode: [
      { value: 'open', label: 'Open — anyone can register' },
      { value: 'approval', label: 'Approval — admin must approve' },
      { value: 'invite', label: 'Invite only — requires invite code' },
      { value: 'closed', label: 'Closed — registration disabled' },
    ],
    analytics_provider: [
      { value: '', label: 'None' },
      { value: 'plausible', label: 'Plausible' },
      { value: 'umami', label: 'Umami' },
      { value: 'matomo', label: 'Matomo' },
    ],
    storage_backend: [
      { value: 'local', label: 'Local filesystem' },
      { value: 's3', label: 'Amazon S3 / S3-compatible' },
      { value: 'r2', label: 'Cloudflare R2' },
    ],
    payment_gateway: [
      { value: '', label: 'None' },
      { value: 'stripe', label: 'Stripe' },
      { value: 'paddle', label: 'Paddle' },
    ],
    subscription_currency: [
      { value: 'usd', label: 'USD ($)' },
      { value: 'eur', label: 'EUR' },
      { value: 'gbp', label: 'GBP' },
    ],
    public_timeline_access: [
      { value: 'none', label: 'Disallow — login required' },
      { value: 'local', label: 'Local only — local + trending visible' },
      { value: 'all', label: 'Allow all — all timelines public' },
    ],
    search_backend: [
      { value: 'postgresql', label: 'PostgreSQL (built-in)' },
      { value: 'opensearch', label: 'OpenSearch' },
    ],
  };

  // Matrix limit keys that should show as width x height
  const matrixKeys = new Set(['video_matrix_limit', 'image_matrix_limit']);

  // S3-only settings
  const s3Keys = new Set(['s3_bucket', 's3_region', 's3_endpoint']);

  // Settings shown inline with another setting
  const inlineKeys = new Set(['opensearch_username', 'opensearch_password']);

  function isDropdown(key: string): boolean {
    return key in dropdownOptions;
  }

  function isHidden(setting: AdminSetting): boolean {
    if (s3Keys.has(setting.key) && editValues['storage_backend'] === 'local') return true;
    if (inlineKeys.has(setting.key)) return true;
    return false;
  }

  function matrixToWxH(val: string): { w: string; h: string } {
    const n = parseInt(val, 10);
    if (!n || n <= 0) return { w: '0', h: '0' };
    // Common aspect ratios
    if (n === 33177600) return { w: '7680', h: '4320' }; // 8K
    if (n === 8294400) return { w: '3840', h: '2160' };  // 4K
    if (n === 2073600) return { w: '1920', h: '1080' };  // 1080p
    // Approximate as 16:9
    const h = Math.round(Math.sqrt(n / (16 / 9)));
    const w = Math.round(n / h);
    return { w: String(w), h: String(h) };
  }

  function wxhToMatrix(w: string, h: string): string {
    return String(parseInt(w, 10) * parseInt(h, 10));
  }

  function renderInput(setting: AdminSetting): 'text' | 'number' | 'checkbox' | 'textarea' {
    switch (setting.type) {
      case 'boolean': return 'checkbox';
      case 'integer': return 'number';
      case 'text': return 'textarea';
      case 'json': return 'textarea';
      default: return 'text';
    }
  }
</script>

<svelte:head>
  <title>Settings - Admin</title>
</svelte:head>

<div class="settings-page">
  <h1 class="page-title">Instance Settings</h1>

  {#if loading}
    <div class="loading-state">
      {#each Array(3) as _}
        <div class="card" style="margin-bottom: var(--space-4)">
          <div class="skeleton" style="height: 24px; width: 120px; margin-bottom: 16px"></div>
          {#each Array(3) as _s}
            <div class="skeleton" style="height: 40px; margin-bottom: 12px"></div>
          {/each}
        </div>
      {/each}
    </div>
  {:else}
    {#each groupedSettings() as [category, categorySettings] (category)}
      <section class="settings-category card">
        <h2 class="category-title">{categoryLabels[category] || category}</h2>

        <div class="settings-list">
          {#each categorySettings as setting (setting.key)}
            {#if !isHidden(setting)}
              <div class="setting-row">
                <div class="setting-info">
                  <label for="setting-{setting.key}" class="setting-label">{setting.key.replace(/_/g, ' ')}</label>
                  {#if setting.description}
                    <p class="setting-description">{setting.description}</p>
                  {/if}
                </div>
                <div class="setting-input">
                  {#if isDropdown(setting.key)}
                    <select
                      id="setting-{setting.key}"
                      class="input"
                      bind:value={editValues[setting.key]}
                    >
                      {#each dropdownOptions[setting.key] as opt}
                        <option value={opt.value}>{opt.label}</option>
                      {/each}
                    </select>
                    {#if setting.key === 'public_timeline_access' && editValues[setting.key] === 'all'}
                      <p class="setting-warning">
                        <span class="material-symbols-outlined" style="font-size: 16px; vertical-align: middle">warning</span>
                        May increase server load from unauthenticated traffic.
                      </p>
                    {/if}
                  {:else if matrixKeys.has(setting.key)}
                    {@const dims = matrixToWxH(editValues[setting.key] || '0')}
                    <div class="matrix-input">
                      <input
                        type="number"
                        class="input matrix-field"
                        value={dims.w}
                        placeholder="Width"
                        onchange={(e) => {
                          editValues[setting.key] = wxhToMatrix((e.currentTarget as HTMLInputElement).value, dims.h);
                        }}
                      />
                      <span class="matrix-x">&times;</span>
                      <input
                        type="number"
                        class="input matrix-field"
                        value={dims.h}
                        placeholder="Height"
                        onchange={(e) => {
                          editValues[setting.key] = wxhToMatrix(dims.w, (e.currentTarget as HTMLInputElement).value);
                        }}
                      />
                      <span class="matrix-label">px</span>
                    </div>
                  {:else if setting.key === 'opensearch_url'}
                    <input
                      type="text"
                      id="setting-{setting.key}"
                      class="input"
                      bind:value={editValues[setting.key]}
                      placeholder="http://localhost:9200"
                    />
                    <label class="opensearch-option">
                      <input
                        type="checkbox"
                        checked={editValues[setting.key]?.startsWith('https')}
                        onchange={(e) => {
                          const url = editValues[setting.key] || 'http://localhost:9200';
                          if ((e.currentTarget as HTMLInputElement).checked) {
                            editValues[setting.key] = url.replace('http://', 'https://');
                          } else {
                            editValues[setting.key] = url.replace('https://', 'http://');
                          }
                        }}
                      />
                      <span>Use HTTPS (secure connection)</span>
                    </label>
                    <label class="opensearch-option">
                      <input
                        type="checkbox"
                        checked={!!editValues['opensearch_username']}
                        onchange={(e) => {
                          if (!(e.currentTarget as HTMLInputElement).checked) {
                            editValues['opensearch_username'] = '';
                            editValues['opensearch_password'] = '';
                          }
                        }}
                      />
                      <span>Use authentication</span>
                    </label>
                    {#if editValues['opensearch_username'] !== undefined}
                      <div class="opensearch-auth">
                        <input
                          type="text"
                          class="input"
                          bind:value={editValues['opensearch_username']}
                          placeholder="Username"
                        />
                        <input
                          type="password"
                          class="input"
                          bind:value={editValues['opensearch_password']}
                          placeholder="Password"
                        />
                      </div>
                    {/if}
                  {:else if renderInput(setting) === 'checkbox'}
                    <label class="toggle-wrapper">
                      <input
                        type="checkbox"
                        id="setting-{setting.key}"
                        checked={editValues[setting.key] === 'true'}
                        onchange={(e) => {
                          editValues[setting.key] = (e.currentTarget as HTMLInputElement).checked ? 'true' : 'false';
                        }}
                        class="toggle-checkbox"
                      />
                      <span class="toggle-track-inline">
                        <span class="toggle-thumb-inline"></span>
                      </span>
                    </label>
                  {:else if renderInput(setting) === 'textarea'}
                    <textarea
                      id="setting-{setting.key}"
                      class="textarea"
                      rows="3"
                      bind:value={editValues[setting.key]}
                    ></textarea>
                  {:else}
                    <input
                      type={renderInput(setting)}
                      id="setting-{setting.key}"
                      class="input"
                      bind:value={editValues[setting.key]}
                    />
                  {/if}
                </div>
              </div>
            {/if}
          {/each}
        </div>

        <div class="category-actions">
          <button
            class="btn btn-primary"
            type="button"
            disabled={savingCategory === category}
            onclick={() => saveCategory(category)}
          >
            {savingCategory === category ? 'Saving...' : `Save ${category}`}
          </button>
        </div>
      </section>
    {/each}
  {/if}
</div>

<style>
  .settings-page {
    max-width: 800px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-6);
  }

  .settings-category {
    margin-block-end: var(--space-4);
  }

  .category-title {
    font-size: var(--text-lg);
    font-weight: 600;
    margin-block-end: var(--space-4);
    padding-block-end: var(--space-3);
    border-block-end: 1px solid var(--color-border);
  }

  .settings-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .setting-row {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-4);
  }

  .setting-info {
    flex: 1;
    min-width: 0;
  }

  .setting-label {
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
    text-transform: capitalize;
    display: block;
    margin-block-end: var(--space-1);
  }

  .setting-description {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    line-height: 1.4;
  }

  .setting-warning {
    font-size: var(--text-xs);
    color: var(--color-warning, #f59e0b);
    margin-block-start: 6px;
    line-height: 1.4;
    font-weight: 500;
  }

  .setting-input {
    flex-shrink: 0;
    width: 280px;
  }

  .matrix-input {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .matrix-field {
    width: 90px !important;
    text-align: center;
  }

  .matrix-x {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    font-weight: 600;
  }

  .matrix-label {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .opensearch-option {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    margin-block-start: 6px;
    cursor: pointer;
  }

  .opensearch-option input {
    accent-color: var(--color-primary);
  }

  .opensearch-auth {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-block-start: 8px;
  }

  .category-actions {
    margin-block-start: var(--space-4);
    padding-block-start: var(--space-3);
    border-block-start: 1px solid var(--color-border);
    display: flex;
    justify-content: flex-end;
  }

  .toggle-wrapper {
    display: inline-flex;
    align-items: center;
    cursor: pointer;
  }

  .toggle-checkbox {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
  }

  .toggle-track-inline {
    position: relative;
    width: 44px;
    height: 24px;
    background: var(--color-border);
    border-radius: var(--radius-full);
    transition: background var(--transition-fast);
  }

  .toggle-checkbox:checked + .toggle-track-inline {
    background: var(--color-primary);
  }

  .toggle-thumb-inline {
    position: absolute;
    top: 2px;
    inset-inline-start: 2px;
    width: 20px;
    height: 20px;
    background: white;
    border-radius: var(--radius-full);
    box-shadow: var(--shadow-sm);
    transition: transform var(--transition-fast);
  }

  .toggle-checkbox:checked + .toggle-track-inline .toggle-thumb-inline {
    transform: translateX(20px);
  }

  .loading-state {
    max-width: 800px;
  }

  @media (max-width: 768px) {
    .setting-row {
      flex-direction: column;
    }

    .setting-input {
      width: 100%;
    }
  }
</style>
