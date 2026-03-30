<script lang="ts">
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import { authStore } from '$lib/stores/auth.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let aliases: string[] = $state([]);
  let aliasesLoading = $state(true);
  let newAlias = $state('');
  let addingAlias = $state(false);
  let removingAlias: string | null = $state(null);

  let targetAccount = $state('');
  let migratePassword = $state('');
  let migrating = $state(false);
  let migrateError: string | null = $state(null);
  let confirmMigrate = $state(false);

  onMount(async () => {
    try {
      const state = get(authStore);
      const user = state.user as any;
      aliases = user?.also_known_as ?? [];
    } catch {
      // Fall back to API
    }

    try {
      const res = await api.get<{ data: { also_known_as: string[] } }>('/api/v1/accounts/aliases');
      aliases = res.data.also_known_as ?? [];
    } catch {
      // Non-critical, we may already have aliases from auth state
    } finally {
      aliasesLoading = false;
    }
  });

  async function handleAddAlias(e: Event) {
    e.preventDefault();
    const alias = newAlias.trim();
    if (!alias) return;

    addingAlias = true;
    try {
      await api.post('/api/v1/accounts/aliases', { alias });
      aliases = [...aliases, alias];
      newAlias = '';
      addToast('Alias added', 'success');
    } catch {
      addToast('Failed to add alias', 'error');
    } finally {
      addingAlias = false;
    }
  }

  async function handleRemoveAlias(alias: string) {
    removingAlias = alias;
    try {
      await api.delete('/api/v1/accounts/aliases', { alias });
      aliases = aliases.filter(a => a !== alias);
      addToast('Alias removed', 'success');
    } catch {
      addToast('Failed to remove alias', 'error');
    } finally {
      removingAlias = null;
    }
  }

  async function handleMigrate(e: Event) {
    e.preventDefault();
    migrateError = null;

    if (!targetAccount.trim()) {
      migrateError = 'Target account is required';
      return;
    }

    if (!migratePassword) {
      migrateError = 'Password is required to confirm migration';
      return;
    }

    migrating = true;
    try {
      await api.post('/api/v1/accounts/migrate', {
        target_account: targetAccount.trim(),
        password: migratePassword,
      });
      addToast('Migration initiated successfully', 'success');
      confirmMigrate = false;
      targetAccount = '';
      migratePassword = '';
    } catch (err) {
      migrateError = err instanceof Error ? err.message : 'Migration failed';
    } finally {
      migrating = false;
    }
  }
</script>

<div class="stitch-settings">
  <div class="stitch-settings-header">
    <h1 class="stitch-settings-title">Account Migration</h1>
    <p class="stitch-settings-subtitle">Move your account to or from another instance</p>
  </div>

  <!-- Aliases -->
  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="8.5" cy="7" r="4"/><line x1="20" y1="8" x2="20" y2="14"/><line x1="23" y1="11" x2="17" y2="11"/>
        </svg>
      </span>
      <h2 class="stitch-section-title">Account Aliases</h2>
    </div>

    <div class="stitch-section-content">
      <div class="stitch-form">
        <p class="stitch-description">
          Aliases tell other instances that this account is also known as the listed accounts. This is required before migrating from another account to this one.
        </p>

        <form class="stitch-inline-form" onsubmit={handleAddAlias}>
          <input
            type="text"
            class="stitch-input"
            bind:value={newAlias}
            placeholder="user@other-instance.social"
            required
          />
          <button class="stitch-btn-primary stitch-btn-sm" type="submit" disabled={addingAlias}>
            {#if addingAlias}
              <Spinner size={14} color="#fff" />
            {/if}
            Add Alias
          </button>
        </form>

        {#if aliasesLoading}
          <div class="stitch-loading"><Spinner size={20} /> Loading aliases...</div>
        {:else if aliases.length === 0}
          <p class="stitch-description">No aliases configured.</p>
        {:else}
          <div class="stitch-list">
            {#each aliases as alias (alias)}
              <div class="stitch-list-item">
                <div class="stitch-list-info">
                  <div class="stitch-list-name">{alias}</div>
                </div>
                <button
                  class="stitch-btn-danger stitch-btn-sm"
                  onclick={() => handleRemoveAlias(alias)}
                  disabled={removingAlias === alias}
                >
                  {#if removingAlias === alias}
                    <Spinner size={14} color="#fff" />
                  {/if}
                  Remove
                </button>
              </div>
            {/each}
          </div>
        {/if}
      </div>
    </div>
  </section>

  <!-- Migrate -->
  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <polyline points="15 3 21 3 21 9"/><polyline points="9 21 3 21 3 15"/><line x1="21" y1="3" x2="14" y2="10"/><line x1="3" y1="21" x2="10" y2="14"/>
        </svg>
      </span>
      <h2 class="stitch-section-title">Migrate Account</h2>
    </div>

    <div class="stitch-section-content">
      <div class="stitch-form">
        <div class="stitch-warning">
          <strong>Warning:</strong> Account migration is a destructive operation. Your followers will be moved to the target account, and your current account will be redirected. This cannot be easily undone. Make sure the target account has an alias pointing back to this account before proceeding.
        </div>

        {#if !confirmMigrate}
          <div class="stitch-actions">
            <button class="stitch-btn-danger" type="button" onclick={() => { confirmMigrate = true; }}>
              Begin Migration
            </button>
          </div>
        {:else}
          <form onsubmit={handleMigrate}>
            <div class="stitch-migrate-fields">
              <div class="stitch-field">
                <label class="stitch-label" for="target-account">TARGET ACCOUNT</label>
                <input
                  id="target-account"
                  type="text"
                  class="stitch-input"
                  bind:value={targetAccount}
                  placeholder="user@new-instance.social"
                  required
                />
              </div>

              <div class="stitch-field">
                <label class="stitch-label" for="migrate-password">CONFIRM PASSWORD</label>
                <input
                  id="migrate-password"
                  type="password"
                  class="stitch-input"
                  bind:value={migratePassword}
                  autocomplete="current-password"
                  required
                />
              </div>

              {#if migrateError}
                <div class="stitch-error">{migrateError}</div>
              {/if}

              <div class="stitch-actions">
                <button class="stitch-btn-ghost" type="button" onclick={() => { confirmMigrate = false; migrateError = null; }}>
                  Cancel
                </button>
                <button class="stitch-btn-danger" type="submit" disabled={migrating}>
                  {#if migrating}
                    <Spinner size={16} color="#fff" />
                  {/if}
                  Confirm Migration
                </button>
              </div>
            </div>
          </form>
        {/if}
      </div>
    </div>
  </section>
</div>

<style>
  .stitch-settings {
    max-width: 720px;
  }

  .stitch-settings-header {
    margin-block-end: 32px;
  }

  .stitch-settings-title {
    font-family: 'Manrope', var(--font-sans);
    font-size: 1.875rem;
    font-weight: 800;
    letter-spacing: -0.025em;
    color: var(--color-text);
    margin: 0;
  }

  .stitch-settings-subtitle {
    font-size: 0.875rem;
    color: #6b7280;
    margin-block-start: 4px;
  }

  .stitch-section {
    margin-block-end: 24px;
  }

  .stitch-section-heading {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-block-end: 16px;
  }

  .stitch-section-icon {
    color: var(--color-primary);
    display: flex;
    align-items: center;
  }

  .stitch-section-title {
    font-size: 1.125rem;
    font-weight: 700;
    color: var(--color-text);
    margin: 0;
  }

  .stitch-section-content {
    background: #f2f4f5;
    border-radius: 16px;
    overflow: hidden;
  }

  .stitch-form {
    padding: 24px 32px 32px;
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .stitch-description {
    font-size: 0.875rem;
    color: #6b7280;
    line-height: 1.5;
  }

  .stitch-loading {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 0.875rem;
    color: #6b7280;
  }

  .stitch-warning {
    padding: 16px 20px;
    background: #fef3c7;
    color: #92400e;
    border-radius: 10px;
    font-size: 0.875rem;
    line-height: 1.5;
  }

  .stitch-warning strong {
    font-weight: 700;
  }

  .stitch-inline-form {
    display: flex;
    gap: 12px;
    align-items: center;
  }

  .stitch-migrate-fields {
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .stitch-field {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .stitch-label {
    font-size: 0.6875rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #6b7280;
    margin-inline-start: 4px;
  }

  .stitch-input {
    display: block;
    flex: 1;
    width: 100%;
    padding: 12px 16px;
    background: #e6e8e9;
    border: none;
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    transition: background-color 0.2s ease, box-shadow 0.2s ease;
  }

  .stitch-input::placeholder {
    color: #9ca3af;
  }

  .stitch-input:focus {
    outline: none;
    background: white;
    box-shadow: 0 0 0 2px rgba(var(--color-primary-rgb, 59, 130, 246), 0.2);
  }

  .stitch-error {
    padding: 12px 16px;
    background: #fef2f2;
    color: #dc2626;
    border-radius: 10px;
    font-size: 0.875rem;
  }

  .stitch-list {
    display: flex;
    flex-direction: column;
    gap: 1px;
    background: rgba(0, 0, 0, 0.06);
    border-radius: 12px;
    overflow: hidden;
  }

  .stitch-list-item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 16px;
    background: #e6e8e9;
  }

  .stitch-list-info {
    flex: 1;
    min-width: 0;
  }

  .stitch-list-name {
    font-size: 0.875rem;
    font-weight: 500;
    color: var(--color-text);
  }

  .stitch-actions {
    display: flex;
    justify-content: flex-end;
    gap: 12px;
    padding-block-start: 8px;
  }

  .stitch-btn-primary {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 10px 28px;
    background: var(--color-primary);
    color: white;
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    box-shadow: 0 4px 14px rgba(var(--color-primary-rgb, 59, 130, 246), 0.2);
    transition: background-color 0.15s ease, box-shadow 0.15s ease, transform 0.1s ease;
    white-space: nowrap;
  }

  .stitch-btn-primary:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .stitch-btn-primary:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .stitch-btn-ghost {
    padding: 10px 24px;
    background: transparent;
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    color: #6b7280;
    cursor: pointer;
    transition: color 0.15s ease, background-color 0.15s ease;
  }

  .stitch-btn-ghost:hover {
    color: var(--color-text);
    background: rgba(0, 0, 0, 0.04);
  }

  .stitch-btn-danger {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 10px 24px;
    background: #dc2626;
    color: white;
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    transition: background-color 0.15s ease, transform 0.1s ease;
    white-space: nowrap;
  }

  .stitch-btn-danger:hover:not(:disabled) {
    background: #b91c1c;
  }

  .stitch-btn-danger:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .stitch-btn-sm {
    padding: 6px 16px;
    font-size: 0.75rem;
  }

  @media (max-width: 640px) {
    .stitch-settings-title {
      font-size: 1.5rem;
    }

    .stitch-form {
      padding: 20px;
    }

    .stitch-inline-form {
      flex-direction: column;
      align-items: stretch;
    }
  }
</style>
