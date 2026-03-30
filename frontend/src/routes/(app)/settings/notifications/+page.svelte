<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  const notifTypes = ['follow', 'mention', 'reaction', 'boost', 'poll', 'group_invite'] as const;

  let prefs = $state<Record<string, { email: boolean; push: boolean; in_app: boolean }>>({});
  let saving = $state(false);
  let saved = $state(false);
  let loading = $state(true);
  let error: string | null = $state(null);

  function isEnabled(type: string): boolean {
    return prefs[type]?.in_app ?? true;
  }

  function toggle(type: string, value: boolean) {
    if (!prefs[type]) {
      prefs[type] = { email: true, push: true, in_app: value };
    } else {
      prefs[type] = { ...prefs[type], in_app: value };
    }
  }

  onMount(async () => {
    try {
      prefs = await api.get<Record<string, any>>('/api/v1/notification_preferences');
    } catch {
      // Use defaults — all enabled
    } finally {
      loading = false;
    }
  });

  async function handleSave() {
    saving = true;
    error = null;
    saved = false;
    try {
      // Save each type individually
      for (const type of notifTypes) {
        const p = prefs[type] || { email: true, push: true, in_app: true };
        await api.patch('/api/v1/notification_preferences', {
          type,
          email: p.email,
          push: p.push,
          in_app: p.in_app,
        });
      }
      saved = true;
      setTimeout(() => { saved = false; }, 3000);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to save';
    } finally {
      saving = false;
    }
  }

</script>

<div class="stitch-settings">
  <!-- Page header -->
  <div class="stitch-settings-header">
    <h1 class="stitch-settings-title">Account Settings</h1>
    <p class="stitch-settings-subtitle">Manage your profile, preferences, and account details</p>
  </div>

  <!-- Notifications Section -->
  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/>
        </svg>
      </span>
      <h2 class="stitch-section-title">Notifications</h2>
    </div>

    <div class="stitch-section-content">
      {#if loading}
        <div class="stitch-loading">
          <Spinner />
        </div>
      {:else}
        <form class="stitch-form" onsubmit={(e) => { e.preventDefault(); handleSave(); }}>
          <p class="stitch-description">Choose which notifications you want to receive.</p>

          {#each [
            { type: 'follow', name: 'Follows', desc: 'Someone follows you or sends a follow request' },
            { type: 'mention', name: 'Mentions', desc: 'Someone mentions you in a post' },
            { type: 'reaction', name: 'Reactions', desc: 'Someone reacts to your post' },
            { type: 'boost', name: 'Boosts', desc: 'Someone boosts your post' },
            { type: 'poll', name: 'Polls', desc: 'A poll you voted in has ended' },
            { type: 'group_invite', name: 'Group invites', desc: 'Someone invites you to a group' },
          ] as item (item.type)}
            <div class="stitch-check-row">
              <label class="stitch-checkbox-label">
                <input
                  type="checkbox"
                  checked={isEnabled(item.type)}
                  onchange={(e) => toggle(item.type, (e.target as HTMLInputElement).checked)}
                  class="stitch-checkbox"
                />
                <div class="stitch-check-info">
                  <span class="stitch-check-name">{item.name}</span>
                  <span class="stitch-check-desc">{item.desc}</span>
                </div>
              </label>
            </div>
          {/each}

          {#if error}
            <div class="stitch-error">{error}</div>
          {/if}

          {#if saved}
            <div class="stitch-success">Notification preferences saved</div>
          {/if}

          <div class="stitch-actions">
            <button class="stitch-btn-primary" type="submit" disabled={saving}>
              {#if saving}
                <Spinner size={16} color="#fff" />
              {/if}
              Save Settings
            </button>
          </div>
        </form>
      {/if}
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

  .stitch-loading {
    display: flex;
    justify-content: center;
    padding: 48px;
  }

  .stitch-form {
    padding: 24px 32px 32px;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .stitch-description {
    font-size: 0.875rem;
    color: #6b7280;
    margin-block-end: 12px;
  }

  /* ---- Checkbox rows ---- */
  .stitch-check-row {
    padding: 12px 0;
    border-block-end: 1px solid rgba(0, 0, 0, 0.06);
  }

  .stitch-check-row:last-of-type {
    border-block-end: none;
  }

  .stitch-checkbox-label {
    display: flex;
    align-items: flex-start;
    gap: 12px;
    cursor: pointer;
  }

  .stitch-checkbox {
    width: 18px;
    height: 18px;
    accent-color: var(--color-primary);
    margin-block-start: 2px;
    flex-shrink: 0;
    cursor: pointer;
  }

  .stitch-check-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .stitch-check-name {
    font-size: 0.875rem;
    font-weight: 500;
    color: var(--color-text);
  }

  .stitch-check-desc {
    font-size: 0.75rem;
    color: #9ca3af;
  }

  .stitch-error {
    padding: 12px 16px;
    background: #fef2f2;
    color: #dc2626;
    border-radius: 10px;
    font-size: 0.875rem;
    margin-block-start: 12px;
  }

  .stitch-success {
    padding: 12px 16px;
    background: #f0fdf4;
    color: #16a34a;
    border-radius: 10px;
    font-size: 0.875rem;
    margin-block-start: 12px;
  }

  .stitch-actions {
    display: flex;
    justify-content: flex-end;
    gap: 12px;
    padding-block-start: 16px;
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
  }

  .stitch-btn-primary:hover:not(:disabled) {
    background: var(--color-primary-hover);
    box-shadow: 0 6px 20px rgba(var(--color-primary-rgb, 59, 130, 246), 0.3);
  }

  .stitch-btn-primary:active:not(:disabled) {
    transform: scale(0.98);
  }

  .stitch-btn-primary:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  @media (max-width: 640px) {
    .stitch-settings-title {
      font-size: 1.5rem;
    }

    .stitch-form {
      padding: 20px;
    }
  }
</style>
