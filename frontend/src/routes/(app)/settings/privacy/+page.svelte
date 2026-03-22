<script lang="ts">
  import { get } from 'svelte/store';
  import { onMount } from 'svelte';
  import { authStore, setUser } from '$lib/stores/auth.js';
  import { updateAccount } from '$lib/api/accounts.js';
  import { api } from '$lib/api/client.js';
  import Toggle from '$lib/components/ui/Toggle.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import type { UserPreferences } from '$lib/api/types.js';

  let isLocked: boolean = $state(false);
  let dmPreference: string = $state('everyone');
  let groupDmOptIn: boolean = $state(false);
  let loaded = $state(false);
  let defaultVisibility = $state<string>('public');
  let saving = $state(false);
  let saved = $state(false);
  let error: string | null = $state(null);

  onMount(async () => {
    const state = get(authStore);
    if (state.user) {
      isLocked = state.user.is_locked ?? false;
    }
    try {
      const prefs = await api.get<any>('/api/v1/dm_preferences');
      dmPreference = prefs.allow_dms_from || prefs.dm_preference || 'everyone';
      groupDmOptIn = prefs.allow_group_dms ?? prefs.group_dm_opt_in ?? false;
    } catch {
      // Use defaults
    }
    loaded = true;
  });

  async function handleSave() {
    saving = true;
    error = null;
    saved = false;
    try {
      const updated = await updateAccount({ is_locked: isLocked });
      setUser(updated);

      await api.patch('/api/v1/dm_preferences', {
        dm_preference: dmPreference,
        group_dm_opt_in: groupDmOptIn,
      });

      await updateAccount({ default_visibility: defaultVisibility });

      saved = true;
      setTimeout(() => { saved = false; }, 3000);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to save';
    } finally {
      saving = false;
    }
  }
</script>

<div class="settings-section">
  <h2 class="section-title">Privacy</h2>

  <form class="settings-form" onsubmit={(e) => { e.preventDefault(); handleSave(); }}>
    <div class="setting-row">
      <div class="setting-info">
        <span class="setting-label">Lock account</span>
        <span class="setting-description">Manually approve follow requests</span>
      </div>
      <Toggle bind:checked={isLocked} name="locked" />
    </div>

    <div class="setting-divider"></div>

    <div class="form-group">
      <label class="form-label" for="dm-pref">Who can send you direct messages</label>
      <select id="dm-pref" class="input" bind:value={dmPreference}>
        <option value="everyone">Everyone</option>
        <option value="followers">Followers only</option>
        <option value="mutual">Mutual followers only</option>
        <option value="nobody">Nobody</option>
      </select>
    </div>

    <div class="setting-row">
      <div class="setting-info">
        <span class="setting-label">Allow group DM invites</span>
        <span class="setting-description">Let others add you to group conversations</span>
      </div>
      <Toggle bind:checked={groupDmOptIn} name="group-dm" />
    </div>

    <div class="setting-divider"></div>

    <div class="form-group">
      <label class="form-label" for="default-vis">Default post visibility</label>
      <select id="default-vis" class="input" bind:value={defaultVisibility}>
        <option value="public">Public</option>
        <option value="followers">Followers only</option>
        <option value="direct">Direct (mentioned people only)</option>
      </select>
      <span class="form-hint">New posts will default to this visibility setting</span>
    </div>

    {#if error}
      <div class="form-error">{error}</div>
    {/if}

    {#if saved}
      <div class="form-success">Privacy settings saved</div>
    {/if}

    <div class="form-actions">
      <button class="btn btn-primary" type="submit" disabled={saving}>
        {#if saving}
          <Spinner size={16} color="var(--color-text-on-primary)" />
        {/if}
        Save changes
      </button>
    </div>
  </form>
</div>

<style>
  .settings-section {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow: hidden;
  }

  .section-title {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--color-text);
    padding: var(--space-4) var(--space-6);
    border-block-end: 1px solid var(--color-border);
  }

  .settings-form {
    padding: var(--space-6);
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .setting-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-4);
  }

  .setting-info {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .setting-label {
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
  }

  .setting-description {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .setting-divider {
    height: 1px;
    background: var(--color-border);
  }

  .form-group {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .form-label {
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
  }

  .form-hint {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .form-error {
    padding: var(--space-3);
    background: var(--color-danger-soft);
    color: var(--color-danger);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  .form-success {
    padding: var(--space-3);
    background: var(--color-success-soft);
    color: var(--color-success);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  .form-actions {
    display: flex;
    justify-content: flex-end;
  }
</style>
