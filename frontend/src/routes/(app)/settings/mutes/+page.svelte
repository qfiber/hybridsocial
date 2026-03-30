<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface MutedAccount {
    id: string;
    handle: string;
    display_name: string;
    avatar_url: string | null;
    muted_until: string | null;
  }

  let mutedAccounts: MutedAccount[] = $state([]);
  let loading = $state(true);
  let unmutingId: string | null = $state(null);

  onMount(async () => {
    try {
      const res = await api.get<MutedAccount[]>('/api/v1/accounts/mutes');
      mutedAccounts = Array.isArray(res) ? res : [];
    } catch {
      addToast('Failed to load muted accounts', 'error');
    } finally {
      loading = false;
    }
  });

  async function handleUnmute(account: MutedAccount) {
    unmutingId = account.id;
    try {
      await api.post(`/api/v1/accounts/${account.id}/unmute`);
      mutedAccounts = mutedAccounts.filter(a => a.id !== account.id);
      addToast(`Unmuted @${account.handle}`, 'success');
    } catch {
      addToast('Failed to unmute account', 'error');
    } finally {
      unmutingId = null;
    }
  }

  function formatMuteExpiry(iso: string | null): string {
    if (!iso) return 'Indefinite';
    const date = new Date(iso);
    if (date.getTime() <= Date.now()) return 'Expired';
    return `Until ${date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })}`;
  }
</script>

<div class="stitch-settings">
  <div class="stitch-settings-header">
    <h1 class="stitch-settings-title">Mutes</h1>
    <p class="stitch-settings-subtitle">Manage muted accounts</p>
  </div>

  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6"/><path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2c0 .76-.12 1.5-.35 2.18"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/>
        </svg>
      </span>
      <h2 class="stitch-section-title">Muted Accounts</h2>
    </div>

    <div class="stitch-section-content">
      <div class="stitch-form">
        <p class="stitch-description">
          Muted accounts won't appear in your home feed or notifications. They can still follow you and see your posts.
        </p>

        {#if loading}
          <div class="stitch-loading"><Spinner size={20} /> Loading muted accounts...</div>
        {:else if mutedAccounts.length === 0}
          <p class="stitch-description">You haven't muted any accounts.</p>
        {:else}
          <div class="stitch-list">
            {#each mutedAccounts as account (account.id)}
              <div class="stitch-list-item">
                <div class="stitch-list-avatar">
                  {#if account.avatar_url}
                    <img src={account.avatar_url} alt="" class="stitch-avatar-img" />
                  {:else}
                    <div class="stitch-avatar-placeholder">
                      {(account.display_name || account.handle).charAt(0).toUpperCase()}
                    </div>
                  {/if}
                </div>
                <div class="stitch-list-info">
                  <div class="stitch-list-name">{account.display_name || account.handle}</div>
                  <div class="stitch-list-meta">
                    <span class="stitch-list-handle">@{account.handle}</span>
                    <span class="stitch-list-dot">&middot;</span>
                    <span class="stitch-list-expiry">{formatMuteExpiry(account.muted_until)}</span>
                  </div>
                </div>
                <button
                  class="stitch-btn-outline stitch-btn-sm"
                  onclick={() => handleUnmute(account)}
                  disabled={unmutingId === account.id}
                >
                  {#if unmutingId === account.id}
                    <Spinner size={14} />
                  {/if}
                  Unmute
                </button>
              </div>
            {/each}
          </div>
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

  .stitch-list-avatar {
    flex-shrink: 0;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    overflow: hidden;
  }

  .stitch-avatar-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .stitch-avatar-placeholder {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--color-primary);
    color: white;
    font-weight: 700;
    font-size: 1rem;
  }

  .stitch-list-info {
    flex: 1;
    min-width: 0;
  }

  .stitch-list-name {
    font-size: 0.875rem;
    font-weight: 500;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .stitch-list-meta {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: 0.75rem;
    color: #9ca3af;
  }

  .stitch-list-handle {
    font-size: 0.75rem;
    color: #9ca3af;
  }

  .stitch-list-dot {
    font-size: 0.75rem;
  }

  .stitch-list-expiry {
    font-size: 0.75rem;
    color: #9ca3af;
  }

  .stitch-btn-outline {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 10px 24px;
    background: transparent;
    border: 1.5px solid var(--color-primary);
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-primary);
    cursor: pointer;
    transition: background-color 0.15s ease;
    white-space: nowrap;
  }

  .stitch-btn-outline:hover:not(:disabled) {
    background: rgba(var(--color-primary-rgb, 59, 130, 246), 0.06);
  }

  .stitch-btn-outline:disabled {
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
  }
</style>
