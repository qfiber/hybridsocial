<script lang="ts">
  import { onMount } from 'svelte';
  import { getFunding, type FundingMethod } from '$lib/api/funding.js';

  let methods = $state<FundingMethod[]>([]);
  let loading = $state(true);
  let copiedId = $state<string | null>(null);

  onMount(async () => {
    try {
      methods = await getFunding();
    } catch {
      methods = [];
    } finally {
      loading = false;
    }
  });

  let enabledMethods = $derived(methods.filter((m) => m.enabled));

  function getPlatformIcon(platform: string): string {
    switch (platform.toLowerCase()) {
      case 'stripe': return '💳';
      case 'paypal': return '🅿️';
      case 'bitcoin': return '₿';
      case 'ethereum': return 'Ξ';
      default: return '💰';
    }
  }

  function isCrypto(platform: string): boolean {
    return ['bitcoin', 'ethereum'].includes(platform.toLowerCase());
  }

  async function copyAddress(id: string, address: string) {
    try {
      await navigator.clipboard.writeText(address);
      copiedId = id;
      setTimeout(() => { copiedId = null; }, 2000);
    } catch {
      // Fallback
    }
  }
</script>

<svelte:head>
  <title>Support this instance - HybridSocial</title>
</svelte:head>

<div class="donate-page">
  <div class="donate-header">
    <h1 class="donate-title">Support This Instance</h1>
    <p class="donate-subtitle">Help keep this community running by supporting the server costs.</p>
  </div>

  {#if loading}
    <div class="donate-loading">
      <div class="spinner"></div>
      <span>Loading funding options...</span>
    </div>
  {:else if enabledMethods.length === 0}
    <div class="donate-empty">
      <div class="empty-icon">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--color-text-tertiary)" stroke-width="1.5" aria-hidden="true">
          <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/>
        </svg>
      </div>
      <p class="empty-text">This instance doesn't accept donations yet.</p>
      <p class="empty-subtext">Check back later or reach out to the administrator.</p>
    </div>
  {:else}
    <div class="donate-methods">
      {#each enabledMethods as method (method.id)}
        <div class="donate-card">
          <div class="donate-card-header">
            <span class="platform-icon">{getPlatformIcon(method.platform)}</span>
            <h2 class="platform-name">{method.platform}</h2>
          </div>

          {#if method.display_text}
            <p class="donate-description">{method.display_text}</p>
          {/if}

          {#if method.goal_amount && method.goal_amount > 0}
            <div class="goal-section">
              <div class="goal-bar-track">
                <div
                  class="goal-bar-fill"
                  style="width: {Math.min(((method.current_amount ?? 0) / method.goal_amount) * 100, 100)}%"
                ></div>
              </div>
              <div class="goal-text">
                <span>{method.current_amount ?? 0}</span>
                <span class="goal-separator">/</span>
                <span>{method.goal_amount} goal</span>
              </div>
            </div>
          {/if}

          {#if isCrypto(method.platform) && method.wallet_address}
            <div class="crypto-address">
              <code class="address-text">{method.wallet_address}</code>
              <button
                type="button"
                class="copy-btn"
                onclick={() => copyAddress(method.id, method.wallet_address!)}
              >
                {#if copiedId === method.id}
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-success)" stroke-width="2" aria-hidden="true">
                    <polyline points="20 6 9 17 4 12"/>
                  </svg>
                  Copied
                {:else}
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                    <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
                  </svg>
                  Copy
                {/if}
              </button>
            </div>
          {:else if method.url}
            <a href={method.url} target="_blank" rel="noopener noreferrer" class="donate-link-btn">
              Donate via {method.platform}
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/>
              </svg>
            </a>
          {:else}
            <button type="button" class="donate-link-btn" disabled>
              Coming soon
            </button>
          {/if}
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .donate-page {
    max-width: 640px;
    margin: 0 auto;
    padding: var(--space-6);
  }

  .donate-header {
    margin-block-end: var(--space-6);
  }

  .donate-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .donate-subtitle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.6;
  }

  .donate-loading {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-3);
    padding: var(--space-12);
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
  }

  .spinner {
    width: 20px;
    height: 20px;
    border: 2px solid var(--color-border);
    border-top-color: var(--color-primary);
    border-radius: 50%;
    animation: spin 0.6s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .donate-empty {
    text-align: center;
    padding: var(--space-12) var(--space-6);
  }

  .empty-icon {
    margin-block-end: var(--space-4);
  }

  .empty-text {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .empty-subtext {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  .donate-methods {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .donate-card {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-5);
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .donate-card-header {
    display: flex;
    align-items: center;
    gap: var(--space-3);
  }

  .platform-icon {
    font-size: 1.5rem;
    line-height: 1;
  }

  .platform-name {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--color-text);
    text-transform: capitalize;
  }

  .donate-description {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.5;
  }

  .goal-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .goal-bar-track {
    height: 8px;
    background: var(--color-bg-tertiary);
    border-radius: var(--radius-full);
    overflow: hidden;
  }

  .goal-bar-fill {
    height: 100%;
    background: linear-gradient(90deg, var(--color-primary), #0d9488);
    border-radius: var(--radius-full);
    transition: width 0.5s ease;
  }

  .goal-text {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    display: flex;
    gap: var(--space-1);
  }

  .goal-separator {
    color: var(--color-text-tertiary);
  }

  .crypto-address {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-3);
    background: var(--color-bg-tertiary);
    border-radius: var(--radius-md);
  }

  .address-text {
    flex: 1;
    font-size: var(--text-xs);
    word-break: break-all;
    color: var(--color-text);
    font-family: monospace;
  }

  .copy-btn {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    padding: var(--space-1) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface);
    color: var(--color-text-secondary);
    font-size: var(--text-xs);
    cursor: pointer;
    white-space: nowrap;
    transition: background-color 0.15s ease;
  }

  .copy-btn:hover {
    background: var(--color-bg);
  }

  .donate-link-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    padding: var(--space-3) var(--space-5);
    background: var(--color-primary);
    color: var(--color-text-inverse);
    border: none;
    border-radius: var(--radius-full);
    font-size: var(--text-sm);
    font-weight: 600;
    cursor: pointer;
    text-decoration: none;
    transition: background-color 0.15s ease;
  }

  .donate-link-btn:hover {
    background: var(--color-primary-hover);
    text-decoration: none;
  }

  .donate-link-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>
