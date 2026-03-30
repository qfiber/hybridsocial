<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface BlockedAccount {
    id: string;
    handle: string;
    display_name: string;
    avatar_url: string | null;
  }

  interface DomainBlock {
    domain: string;
  }

  let blockedAccounts: BlockedAccount[] = $state([]);
  let domainBlocks: string[] = $state([]);
  let accountsLoading = $state(true);
  let domainsLoading = $state(true);
  let unblockingId: string | null = $state(null);
  let removingDomain: string | null = $state(null);
  let newDomain = $state('');
  let addingDomain = $state(false);

  onMount(async () => {
    await Promise.all([loadBlockedAccounts(), loadDomainBlocks()]);
  });

  async function loadBlockedAccounts() {
    try {
      const res = await api.get<BlockedAccount[]>('/api/v1/accounts/blocks');
      blockedAccounts = Array.isArray(res) ? res : [];
    } catch {
      addToast('Failed to load blocked accounts', 'error');
    } finally {
      accountsLoading = false;
    }
  }

  async function loadDomainBlocks() {
    try {
      const res = await api.get<{ id: string; domain: string }[]>('/api/v1/accounts/domain_blocks');
      domainBlocks = Array.isArray(res) ? res.map(b => b.domain) : [];
    } catch {
      addToast('Failed to load domain blocks', 'error');
    } finally {
      domainsLoading = false;
    }
  }

  async function handleUnblock(account: BlockedAccount) {
    unblockingId = account.id;
    try {
      await api.post(`/api/v1/accounts/${account.id}/unblock`);
      blockedAccounts = blockedAccounts.filter(a => a.id !== account.id);
      addToast(`Unblocked @${account.handle}`, 'success');
    } catch {
      addToast('Failed to unblock account', 'error');
    } finally {
      unblockingId = null;
    }
  }

  async function handleAddDomain(e: Event) {
    e.preventDefault();
    const domain = newDomain.trim().toLowerCase();
    if (!domain) return;

    addingDomain = true;
    try {
      await api.post('/api/v1/accounts/domain_blocks', { domain });
      domainBlocks = [...domainBlocks, domain];
      newDomain = '';
      addToast(`Blocked domain ${domain}`, 'success');
    } catch {
      addToast('Failed to block domain', 'error');
    } finally {
      addingDomain = false;
    }
  }

  async function handleRemoveDomain(domain: string) {
    removingDomain = domain;
    try {
      await api.delete('/api/v1/accounts/domain_blocks', { domain });
      domainBlocks = domainBlocks.filter(d => d !== domain);
      addToast(`Unblocked domain ${domain}`, 'success');
    } catch {
      addToast('Failed to unblock domain', 'error');
    } finally {
      removingDomain = null;
    }
  }
</script>

<div class="stitch-settings">
  <div class="stitch-settings-header">
    <h1 class="stitch-settings-title">Blocks</h1>
    <p class="stitch-settings-subtitle">Manage blocked accounts and domains</p>
  </div>

  <!-- Blocked Accounts -->
  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
        </svg>
      </span>
      <h2 class="stitch-section-title">Blocked Accounts</h2>
    </div>

    <div class="stitch-section-content">
      <div class="stitch-form">
        <p class="stitch-description">
          Blocked accounts cannot see your posts, follow you, or send you messages.
        </p>

        {#if accountsLoading}
          <div class="stitch-loading"><Spinner size={20} /> Loading blocked accounts...</div>
        {:else if blockedAccounts.length === 0}
          <p class="stitch-description">You haven't blocked any accounts.</p>
        {:else}
          <div class="stitch-list">
            {#each blockedAccounts as account (account.id)}
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
                  <div class="stitch-list-handle">@{account.handle}</div>
                </div>
                <button
                  class="stitch-btn-outline stitch-btn-sm"
                  onclick={() => handleUnblock(account)}
                  disabled={unblockingId === account.id}
                >
                  {#if unblockingId === account.id}
                    <Spinner size={14} />
                  {/if}
                  Unblock
                </button>
              </div>
            {/each}
          </div>
        {/if}
      </div>
    </div>
  </section>

  <!-- Domain Blocks -->
  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>
        </svg>
      </span>
      <h2 class="stitch-section-title">Blocked Domains</h2>
    </div>

    <div class="stitch-section-content">
      <div class="stitch-form">
        <p class="stitch-description">
          Block an entire domain to hide all content from users on that instance.
        </p>

        <form class="stitch-inline-form" onsubmit={handleAddDomain}>
          <input
            type="text"
            class="stitch-input"
            bind:value={newDomain}
            placeholder="example.com"
            required
          />
          <button class="stitch-btn-primary stitch-btn-sm" type="submit" disabled={addingDomain}>
            {#if addingDomain}
              <Spinner size={14} color="#fff" />
            {/if}
            Block Domain
          </button>
        </form>

        {#if domainsLoading}
          <div class="stitch-loading"><Spinner size={20} /> Loading domain blocks...</div>
        {:else if domainBlocks.length === 0}
          <p class="stitch-description">No domain blocks.</p>
        {:else}
          <div class="stitch-list">
            {#each domainBlocks as domain (domain)}
              <div class="stitch-list-item">
                <div class="stitch-list-info">
                  <div class="stitch-list-name">{domain}</div>
                </div>
                <button
                  class="stitch-btn-danger stitch-btn-sm"
                  onclick={() => handleRemoveDomain(domain)}
                  disabled={removingDomain === domain}
                >
                  {#if removingDomain === domain}
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

  .stitch-inline-form {
    display: flex;
    gap: 12px;
    align-items: center;
  }

  .stitch-input {
    display: block;
    flex: 1;
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

  .stitch-list-handle {
    font-size: 0.75rem;
    color: #9ca3af;
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
    box-shadow: 0 6px 20px rgba(var(--color-primary-rgb, 59, 130, 246), 0.3);
  }

  .stitch-btn-primary:disabled {
    opacity: 0.6;
    cursor: not-allowed;
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
