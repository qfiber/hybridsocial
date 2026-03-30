<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface CryptoAddr {
    id: string;
    coin: string;
    coin_name: string;
    address: string;
    label: string | null;
    is_public: boolean;
  }

  const coins = [
    { id: 'btc', name: 'Bitcoin', icon: 'B' },
    { id: 'eth', name: 'Ethereum', icon: 'E' },
    { id: 'xmr', name: 'Monero', icon: 'M' },
    { id: 'sol', name: 'Solana', icon: 'S' },
    { id: 'ltc', name: 'Litecoin', icon: 'L' },
    { id: 'doge', name: 'Dogecoin', icon: 'D' },
    { id: 'ada', name: 'Cardano', icon: 'A' },
    { id: 'dot', name: 'Polkadot', icon: 'P' },
    { id: 'bnb', name: 'BNB', icon: 'B' },
    { id: 'usdt', name: 'USDT', icon: 'T' },
    { id: 'usdc', name: 'USDC', icon: 'U' },
  ];

  let addresses = $state<CryptoAddr[]>([]);
  let loading = $state(true);
  let newCoin = $state('btc');
  let newAddress = $state('');
  let newLabel = $state('');
  let adding = $state(false);

  onMount(async () => {
    try {
      addresses = await api.get<CryptoAddr[]>('/api/v1/accounts/crypto_addresses');
    } catch { /* */ }
    finally { loading = false; }
  });

  async function addAddress() {
    if (!newAddress.trim() || adding) return;
    adding = true;
    try {
      const addr = await api.post<CryptoAddr>('/api/v1/accounts/crypto_addresses', {
        coin: newCoin,
        address: newAddress,
        label: newLabel || null,
      });
      addresses = [...addresses.filter(a => a.coin !== newCoin), addr];
      newAddress = '';
      newLabel = '';
      addToast('Wallet address saved', 'success');
    } catch {
      addToast('Failed to save address', 'error');
    } finally { adding = false; }
  }

  async function removeAddress(coin: string) {
    try {
      await api.delete(`/api/v1/accounts/crypto_addresses/${coin}`);
      addresses = addresses.filter(a => a.coin !== coin);
      addToast('Address removed', 'success');
    } catch {
      addToast('Failed to remove', 'error');
    }
  }
</script>

<svelte:head>
  <title>Donation Settings - HybridSocial</title>
</svelte:head>

<div class="donations-page">
  <h1 class="stitch-title">Crypto Donations</h1>
  <p class="stitch-desc">Add your wallet addresses so people can donate to you. These will appear on your profile.</p>

  <div class="stitch-card">
    <h2 class="stitch-section-title">Add Wallet Address</h2>
    <div class="add-form">
      <div class="stitch-field">
        <label class="stitch-label" for="coin-select">Cryptocurrency</label>
        <select id="coin-select" class="stitch-input" bind:value={newCoin}>
          {#each coins as coin (coin.id)}
            <option value={coin.id}>{coin.name} ({coin.id.toUpperCase()})</option>
          {/each}
        </select>
      </div>
      <div class="stitch-field">
        <label class="stitch-label" for="addr-input">Wallet Address</label>
        <input id="addr-input" type="text" class="stitch-input mono" bind:value={newAddress} placeholder="Your wallet address" />
      </div>
      <div class="stitch-field">
        <label class="stitch-label" for="label-input">Label (optional)</label>
        <input id="label-input" type="text" class="stitch-input" bind:value={newLabel} placeholder="e.g. Main wallet" />
      </div>
      <button type="button" class="stitch-btn-primary" onclick={addAddress} disabled={!newAddress.trim() || adding}>
        {adding ? 'Saving...' : 'Save address'}
      </button>
    </div>
  </div>

  <div class="stitch-card">
    <h2 class="stitch-section-title">Your Wallet Addresses</h2>
    {#if loading}
      <div style="padding: 24px; text-align: center"><Spinner /></div>
    {:else if addresses.length === 0}
      <p class="stitch-empty">No wallet addresses added yet.</p>
    {:else}
      <div class="addr-list">
        {#each addresses as addr (addr.id)}
          <div class="addr-item">
            <div class="addr-coin">
              <span class="coin-badge">{addr.coin.toUpperCase()}</span>
              <span class="coin-name">{addr.coin_name}</span>
            </div>
            <div class="addr-value">{addr.address}</div>
            {#if addr.label}
              <div class="addr-label">{addr.label}</div>
            {/if}
            <button type="button" class="addr-remove" onclick={() => removeAddress(addr.coin)} aria-label="Remove">
              <span class="material-symbols-outlined" style="font-size: 18px">close</span>
            </button>
          </div>
        {/each}
      </div>
    {/if}
  </div>
</div>

<style>
  .donations-page { max-width: 600px; }
  .stitch-title { font-size: var(--text-2xl); font-weight: 700; margin-block-end: var(--space-2); }
  .stitch-desc { font-size: var(--text-sm); color: var(--color-text-secondary); margin-block-end: var(--space-6); }
  .stitch-card { background: var(--color-surface-raised, white); border: 1px solid var(--color-border); border-radius: var(--radius-xl); padding: var(--space-5); margin-block-end: var(--space-4); }
  .stitch-section-title { font-size: var(--text-base); font-weight: 600; margin-block-end: var(--space-4); }
  .stitch-empty { font-size: var(--text-sm); color: var(--color-text-tertiary); text-align: center; padding: var(--space-6); }
  .stitch-field { margin-block-end: var(--space-3); }
  .stitch-label { display: block; font-size: 0.75rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: var(--color-text-secondary); margin-block-end: 6px; }
  .stitch-input { width: 100%; padding: 10px 14px; border: 1px solid var(--color-border); border-radius: 10px; font-size: 0.875rem; color: var(--color-text); background: var(--color-surface); }
  .stitch-input:focus { outline: none; border-color: var(--color-primary); }
  .mono { font-family: monospace; font-size: 0.8125rem; }
  .stitch-btn-primary { padding: 10px 24px; background: var(--color-primary); color: white; border: none; border-radius: 9999px; font-size: 0.875rem; font-weight: 600; cursor: pointer; }
  .stitch-btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }

  .addr-list { display: flex; flex-direction: column; gap: 8px; }
  .addr-item { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; padding: 12px; background: var(--color-surface); border-radius: 10px; position: relative; }
  .addr-coin { display: flex; align-items: center; gap: 6px; }
  .coin-badge { font-size: 0.65rem; font-weight: 700; padding: 2px 8px; border-radius: 6px; background: var(--color-primary-soft, rgba(0,128,128,0.1)); color: var(--color-primary); }
  .coin-name { font-size: 0.8125rem; font-weight: 600; }
  .addr-value { font-family: monospace; font-size: 0.75rem; color: var(--color-text-secondary); word-break: break-all; flex: 1; }
  .addr-label { font-size: 0.75rem; color: var(--color-text-tertiary); }
  .addr-remove { position: absolute; top: 8px; inset-inline-end: 8px; background: none; border: none; color: var(--color-text-tertiary); cursor: pointer; padding: 2px; border-radius: 50%; }
  .addr-remove:hover { color: var(--color-danger); background: var(--color-danger-soft, rgba(239,68,68,0.1)); }
</style>
