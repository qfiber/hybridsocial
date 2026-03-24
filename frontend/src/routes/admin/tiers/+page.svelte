<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getAdminSettings, updateAdminSettings } from '$lib/api/admin.js';
  import type { AdminSetting } from '$lib/api/types.js';

  let settings: AdminSetting[] = $state([]);
  let loading = $state(true);
  let saving = $state(false);

  // Track changes
  let changed: Record<string, string> = $state({});

  const tierNames = [
    { key: 'free', label: 'Free (L0)' },
    { key: 'verified_starter', label: 'Starter (L1)' },
    { key: 'verified_creator', label: 'Creator (L2)' },
    { key: 'verified_pro', label: 'Pro (L3)' }
  ];

  const limitRows = [
    { key: 'char_limit', label: 'Characters per post', type: 'integer' },
    { key: 'markdown', label: 'Markdown support', type: 'select', options: ['none', 'basic', 'full', 'full_embeds'] },
    { key: 'video_resolution', label: 'Video resolution (px)', type: 'integer' },
    { key: 'video_duration', label: 'Video duration (sec)', type: 'integer' },
    { key: 'image_size_mb', label: 'Image size (MB)', type: 'integer' },
    { key: 'video_size_mb', label: 'Video size (MB)', type: 'integer' },
    { key: 'media_per_post', label: 'Media per post', type: 'integer' },
    { key: 'poll_options', label: 'Poll options', type: 'integer' },
    { key: 'edit_window', label: 'Edit window (sec)', type: 'integer', hint: '0 = unlimited' },
    { key: 'pinned_posts', label: 'Pinned posts', type: 'integer' },
    { key: 'profile_fields', label: 'Profile fields', type: 'integer' },
    { key: 'scheduled_posts', label: 'Scheduled posts', type: 'boolean' },
    { key: 'custom_emoji', label: 'Custom emoji', type: 'boolean' },
    { key: 'follows_limit', label: 'Follows limit', type: 'integer', hint: '0 = unlimited' }
  ];

  function getSettingValue(key: string): string {
    const setting = settings.find(s => s.key === key);
    if (changed[key] !== undefined) return changed[key];
    return setting?.value ?? '';
  }

  function setSettingValue(key: string, value: string) {
    changed[key] = value;
  }

  let tiersEnabled = $derived(getSettingValue('tiers_enabled') === 'true');
  let paymentConfigured = $derived(getSettingValue('tiers_payment_configured') === 'true');

  onMount(async () => {
    try {
      const all = await getAdminSettings();
      settings = all.filter(s => s.category === 'tiers');
    } catch {
      addToast('Failed to load tier settings', 'error');
    } finally {
      loading = false;
    }
  });

  async function handleSave() {
    saving = true;
    try {
      const updates = Object.entries(changed).map(([key, value]) => ({ key, value }));
      if (updates.length > 0) {
        await updateAdminSettings(updates);
        // Refresh
        const all = await getAdminSettings();
        settings = all.filter(s => s.category === 'tiers');
        changed = {};
        addToast('Tier settings saved', 'success');
      }
    } catch {
      addToast('Failed to save settings', 'error');
    } finally {
      saving = false;
    }
  }

  function toggleEnabled() {
    const current = getSettingValue('tiers_enabled') === 'true';
    setSettingValue('tiers_enabled', current ? 'false' : 'true');
  }
</script>

<svelte:head>
  <title>Verification Tiers - Admin</title>
</svelte:head>

<div class="tiers-page">
  <div class="tiers-header">
    <div>
      <h2 class="tiers-title">Verification Tiers</h2>
      <p class="tiers-subtitle">Configure feature limits for each verification level. Changes take effect immediately.</p>
    </div>
    <button class="btn btn-primary" onclick={handleSave} disabled={saving || Object.keys(changed).length === 0}>
      {saving ? 'Saving...' : 'Save Changes'}
    </button>
  </div>

  {#if loading}
    <div class="tiers-loading">Loading...</div>
  {:else}
    <!-- Kill switch -->
    <div class="tiers-switch">
      <label class="switch-row">
        <input type="checkbox" checked={tiersEnabled} onchange={toggleEnabled} class="switch-input" />
        <div class="switch-info">
          <span class="switch-label">Enable tiered limits</span>
          <span class="switch-hint">
            {#if tiersEnabled}
              Tiered limits are active. Users are restricted based on their verification level.
            {:else}
              Tiered limits are off. All users get maximum (L3 Pro) limits.
            {/if}
          </span>
        </div>
      </label>
      {#if tiersEnabled && !paymentConfigured}
        <div class="switch-warning">
          Payment method not configured. Users cannot upgrade tiers until payment is set up.
        </div>
      {/if}
    </div>

    <!-- Limits table -->
    <div class="tiers-table-wrap">
      <table class="tiers-table">
        <thead>
          <tr>
            <th class="col-limit">Limit</th>
            {#each tierNames as tier}
              <th class="col-tier">{tier.label}</th>
            {/each}
          </tr>
        </thead>
        <tbody>
          {#each limitRows as row}
            <tr>
              <td class="cell-label">
                {row.label}
                {#if row.hint}
                  <span class="cell-hint">{row.hint}</span>
                {/if}
              </td>
              {#each tierNames as tier}
                {@const settingKey = `tier_${tier.key}_${row.key}`}
                <td class="cell-input">
                  {#if row.type === 'boolean'}
                    <input
                      type="checkbox"
                      checked={getSettingValue(settingKey) === 'true'}
                      onchange={(e) => setSettingValue(settingKey, (e.target as HTMLInputElement).checked ? 'true' : 'false')}
                      class="tier-checkbox"
                    />
                  {:else if row.type === 'select'}
                    <select
                      value={getSettingValue(settingKey)}
                      onchange={(e) => setSettingValue(settingKey, (e.target as HTMLSelectElement).value)}
                      class="tier-select"
                    >
                      {#each row.options || [] as opt}
                        <option value={opt}>{opt}</option>
                      {/each}
                    </select>
                  {:else}
                    <input
                      type="number"
                      value={getSettingValue(settingKey)}
                      oninput={(e) => setSettingValue(settingKey, (e.target as HTMLInputElement).value)}
                      class="tier-input"
                    />
                  {/if}
                </td>
              {/each}
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</div>

<style>
  .tiers-page {
    padding: var(--space-6);
    max-width: 1100px;
  }

  .tiers-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    margin-block-end: var(--space-6);
  }

  .tiers-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-1);
  }

  .tiers-subtitle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .tiers-loading {
    text-align: center;
    padding: var(--space-8);
    color: var(--color-text-secondary);
  }

  /* Switch */
  .tiers-switch {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-5);
    margin-block-end: var(--space-6);
  }

  .switch-row {
    display: flex;
    align-items: flex-start;
    gap: var(--space-3);
    cursor: pointer;
  }

  .switch-input {
    width: 18px;
    height: 18px;
    accent-color: var(--color-primary);
    margin-top: 2px;
  }

  .switch-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .switch-hint {
    display: block;
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-start: 2px;
  }

  .switch-warning {
    margin-block-start: var(--space-3);
    padding: var(--space-3);
    background: var(--color-warning-soft);
    color: #92400e;
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  /* Table */
  .tiers-table-wrap {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow-x: auto;
  }

  .tiers-table {
    width: 100%;
    border-collapse: collapse;
    font-size: var(--text-sm);
  }

  .tiers-table th {
    padding: var(--space-3) var(--space-4);
    text-align: left;
    font-weight: 600;
    color: var(--color-text);
    border-block-end: 1px solid var(--color-border);
    background: var(--color-surface);
    white-space: nowrap;
  }

  .col-limit {
    width: 200px;
  }

  .col-tier {
    text-align: center !important;
    min-width: 140px;
  }

  .tiers-table td {
    padding: var(--space-2) var(--space-4);
    border-block-end: 1px solid var(--color-border);
    vertical-align: middle;
  }

  .tiers-table tr:last-child td {
    border-block-end: none;
  }

  .cell-label {
    font-weight: 500;
    color: var(--color-text);
  }

  .cell-hint {
    display: block;
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    font-weight: 400;
  }

  .cell-input {
    text-align: center;
  }

  .tier-input {
    width: 80px;
    padding: var(--space-1) var(--space-2);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    text-align: center;
    color: var(--color-text);
    background: var(--color-bg);
  }

  .tier-input:focus {
    outline: none;
    border-color: var(--color-primary);
  }

  .tier-select {
    padding: var(--space-1) var(--space-2);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    color: var(--color-text);
    background: var(--color-bg);
  }

  .tier-checkbox {
    width: 18px;
    height: 18px;
    accent-color: var(--color-primary);
  }

  @media (max-width: 768px) {
    .tiers-header {
      flex-direction: column;
      gap: var(--space-3);
    }
  }
</style>
