<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { api } from '$lib/api/client.js';
  import { lookupAccount } from '$lib/api/accounts.js';
  import type { Identity } from '$lib/api/types.js';
  import { addToast } from '$lib/stores/toast.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';

  let handle = $derived(page.params.handle!);

  interface CryptoAddr {
    id: string;
    coin: string;
    coin_name: string;
    address: string;
    label: string | null;
  }

  let account = $state<Identity | null>(null);
  let addresses = $state<CryptoAddr[]>([]);
  let loading = $state(true);
  let selectedCoin = $state<string | null>(null);

  onMount(async () => {
    try {
      account = await lookupAccount(handle);
      addresses = await api.get<CryptoAddr[]>(`/api/v1/accounts/${account.id}/crypto_addresses`);
      if (addresses.length > 0) selectedCoin = addresses[0].coin;
    } catch { /* */ }
    finally { loading = false; }
  });

  let selectedAddress = $derived(addresses.find(a => a.coin === selectedCoin));

  async function copyAddress() {
    if (selectedAddress) {
      await navigator.clipboard.writeText(selectedAddress.address);
      addToast('Address copied', 'success');
    }
  }

  // Generate QR code URL (using a public QR API)
  function qrUrl(text: string): string {
    return `https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(text)}`;
  }
</script>

<svelte:head>
  <title>Donate to @{handle} - HybridSocial</title>
</svelte:head>

<div class="donate-page">
  {#if loading}
    <div class="donate-loading">Loading...</div>
  {:else if !account}
    <div class="donate-error">User not found</div>
  {:else if addresses.length === 0}
    <div class="donate-empty">
      <h2>@{handle} hasn't set up donations yet</h2>
      <p>This user hasn't added any wallet addresses.</p>
      <a href="/@{handle}" class="back-link">Back to profile</a>
    </div>
  {:else}
    <div class="donate-card">
      <div class="donate-header">
        <Avatar src={account.avatar_url} name={account.display_name || account.handle} size="lg" />
        <div>
          <h1 class="donate-title">Donate to {account.display_name || account.handle}</h1>
          <p class="donate-handle">@{account.acct || account.handle}</p>
        </div>
      </div>

      <!-- Coin selector -->
      <div class="coin-tabs">
        {#each addresses as addr (addr.coin)}
          <button
            type="button"
            class="coin-tab"
            class:active={selectedCoin === addr.coin}
            onclick={() => selectedCoin = addr.coin}
          >
            <span class="coin-tab-badge">{addr.coin.toUpperCase()}</span>
            {addr.coin_name}
          </button>
        {/each}
      </div>

      {#if selectedAddress}
        <div class="address-display">
          <!-- QR Code -->
          <div class="qr-section">
            <img src={qrUrl(selectedAddress.address)} alt="QR Code for {selectedAddress.coin_name}" class="qr-image" />
          </div>

          <!-- Address -->
          <div class="address-section">
            <label class="address-label">{selectedAddress.coin_name} Address</label>
            <div class="address-row">
              <code class="address-text">{selectedAddress.address}</code>
              <button type="button" class="copy-btn" onclick={copyAddress}>
                <span class="material-symbols-outlined" style="font-size: 18px">content_copy</span>
                Copy
              </button>
            </div>
            {#if selectedAddress.label}
              <p class="address-note">{selectedAddress.label}</p>
            {/if}
          </div>
        </div>
      {/if}

      <p class="donate-disclaimer">
        Donations are sent directly to the user's wallet. HybridSocial does not process or take a cut of any donations.
      </p>
    </div>

    <a href="/@{handle}" class="back-link">Back to profile</a>
  {/if}
</div>

<style>
  .donate-page {
    max-width: 500px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .donate-loading, .donate-error, .donate-empty {
    text-align: center;
    padding: var(--space-12);
    color: var(--color-text-secondary);
  }

  .donate-card {
    background: var(--color-surface-container-lowest);
    border: 1px solid var(--color-border);
    border-radius: 18px;
    padding: 28px;
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.06);
  }

  .donate-header {
    display: flex;
    align-items: center;
    gap: 16px;
    margin-bottom: 24px;
  }

  .donate-title { font-size: 1.25rem; font-weight: 700; }
  .donate-handle { font-size: 0.875rem; color: var(--color-text-secondary); }

  .coin-tabs {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-bottom: 20px;
  }

  .coin-tab {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 6px 14px;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    background: transparent;
    font-size: 0.8125rem;
    font-weight: 500;
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: all 150ms ease;
  }

  .coin-tab:hover { border-color: var(--color-primary); color: var(--color-text); }
  .coin-tab.active { background: var(--color-primary); color: white; border-color: var(--color-primary); }
  .coin-tab.active .coin-tab-badge { background: rgba(255,255,255,0.2); color: white; }

  .coin-tab-badge {
    font-size: 0.6rem;
    font-weight: 700;
    padding: 1px 5px;
    border-radius: 4px;
    background: var(--color-surface);
  }

  .address-display {
    text-align: center;
  }

  .qr-section {
    margin-bottom: 16px;
  }

  .qr-image {
    width: 180px;
    height: 180px;
    border-radius: 12px;
    border: 1px solid var(--color-border);
  }

  .address-section { text-align: start; }
  .address-label { font-size: 0.75rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: var(--color-text-tertiary); margin-bottom: 6px; display: block; }

  .address-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 14px;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: 10px;
  }

  .address-text {
    flex: 1;
    font-size: 0.75rem;
    word-break: break-all;
    color: var(--color-text);
  }

  .copy-btn {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 6px 12px;
    background: var(--color-primary);
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 0.75rem;
    font-weight: 600;
    cursor: pointer;
    flex-shrink: 0;
  }

  .copy-btn:hover { opacity: 0.9; }

  .address-note {
    font-size: 0.75rem;
    color: var(--color-text-tertiary);
    margin-top: 6px;
  }

  .donate-disclaimer {
    font-size: 0.7rem;
    color: var(--color-text-tertiary);
    text-align: center;
    margin-top: 20px;
    line-height: 1.4;
  }

  .back-link {
    display: block;
    text-align: center;
    font-size: 0.875rem;
    color: var(--color-primary);
    text-decoration: none;
    font-weight: 500;
  }

  .back-link:hover { text-decoration: underline; }
</style>
