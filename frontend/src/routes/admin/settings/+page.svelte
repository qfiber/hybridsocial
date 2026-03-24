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
            <div class="setting-row">
              <div class="setting-info">
                <label for="setting-{setting.key}" class="setting-label">{setting.key.replace(/_/g, ' ')}</label>
                {#if setting.description}
                  <p class="setting-description">{setting.description}</p>
                {/if}
              </div>
              <div class="setting-input">
                {#if renderInput(setting) === 'checkbox'}
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

  .setting-input {
    flex-shrink: 0;
    width: 280px;
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
