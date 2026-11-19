<script lang="ts">
  import { t } from '$lib/stores/i18n.js';
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';
  import { authStore } from '$lib/stores/auth.js';
  import type { PremiumReactionsResponse } from '$lib/api/conversations.js';
  import { DEFAULT_EMOJI, loadReactionCatalog } from '$lib/utils/message-reactions.js';

  let {
    onpick,
    onclose,
  }: {
    onpick: (emoji: string) => void;
    onclose?: () => void;
  } = $props();

  let catalog = $state<PremiumReactionsResponse | null>(null);
  let loading = $state(true);

  // Premium tiers per backend TierLimits.
  const PREMIUM_TIERS = ['verified_creator', 'verified_pro'];
  let isPremium = $derived.by(() => {
    const tier = get(authStore).user?.verification_tier;
    return !!tier && PREMIUM_TIERS.includes(tier);
  });

  onMount(async () => {
    try {
      catalog = await loadReactionCatalog();
    } catch {
      catalog = { defaults: Object.keys(DEFAULT_EMOJI), premium: [], max_premium: 0 };
    } finally {
      loading = false;
    }
  });

  function pick(shortcode: string, locked: boolean) {
    if (locked) return;
    onpick(shortcode);
  }
</script>

<div class="picker" role="dialog" aria-label="React with emoji">
  {#if loading}
    <div class="picker-loading">{$t('dm.loading')}</div>
  {:else}
    <div class="picker-row">
      {#each catalog?.defaults ?? [] as code (code)}
        <button
          type="button"
          class="picker-btn"
          title={code}
          aria-label="React with {code}"
          onclick={() => pick(code, false)}
        >
          {DEFAULT_EMOJI[code] || code}
        </button>
      {/each}
    </div>

    {#if catalog && catalog.premium.length > 0}
      <div class="picker-divider">
        <span>Premium</span>
        {#if !isPremium}
          <a href="/settings/account" class="picker-upgrade">Upgrade</a>
        {/if}
      </div>
      <div class="picker-row">
        {#each catalog.premium as emoji (emoji.id)}
          <button
            type="button"
            class="picker-btn"
            class:locked={!isPremium}
            title={isPremium
              ? `:${emoji.shortcode}:`
              : `:${emoji.shortcode}: — premium only`}
            aria-label={isPremium
              ? `React with ${emoji.shortcode}`
              : `${emoji.shortcode} (premium only)`}
            onclick={() => pick(emoji.shortcode, !isPremium)}
            disabled={!isPremium}
          >
            {#if emoji.image_url}
              <img src={emoji.image_url} alt="" class="picker-img" />
            {:else}
              {emoji.character || ':' + emoji.shortcode + ':'}
            {/if}
            {#if !isPremium}
              <span class="picker-lock material-symbols-outlined">lock</span>
            {/if}
          </button>
        {/each}
      </div>
    {/if}
  {/if}

  {#if onclose}
    <button type="button" class="picker-close" onclick={onclose} aria-label="Close picker">
      <span class="material-symbols-outlined">close</span>
    </button>
  {/if}
</div>

<style>
  .picker {
    background: var(--color-surface-raised, var(--color-surface));
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg, 12px);
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.15);
    padding: var(--space-2, 8px);
    display: flex;
    flex-direction: column;
    gap: var(--space-2, 8px);
    min-width: 240px;
    position: relative;
  }

  .picker-loading {
    padding: var(--space-3);
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
  }

  .picker-row {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }

  .picker-btn {
    width: 36px;
    height: 36px;
    border: none;
    background: transparent;
    border-radius: 8px;
    font-size: 20px;
    line-height: 1;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    position: relative;
    transition:
      background-color var(--transition-fast),
      transform var(--transition-fast);
  }

  .picker-btn:hover:not(:disabled) {
    background: var(--color-surface);
    transform: scale(1.15);
  }

  .picker-btn:active:not(:disabled) {
    transform: scale(0.95);
  }

  .picker-btn.locked {
    opacity: 0.45;
    cursor: not-allowed;
    filter: grayscale(1);
  }

  .picker-btn:disabled {
    cursor: not-allowed;
  }

  .picker-img {
    width: 24px;
    height: 24px;
    object-fit: contain;
  }

  .picker-lock {
    position: absolute;
    inset-block-end: -2px;
    inset-inline-end: -2px;
    font-size: 12px !important;
    color: var(--color-text-tertiary);
    background: var(--color-surface-raised, var(--color-surface));
    border-radius: 50%;
    padding: 1px;
  }

  .picker-divider {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 0.6875rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-tertiary);
    padding: 0 4px;
  }

  .picker-upgrade {
    color: var(--color-primary, #3b82f6);
    text-decoration: none;
    font-weight: 700;
    text-transform: none;
    letter-spacing: 0;
    font-size: 0.75rem;
  }

  .picker-upgrade:hover {
    text-decoration: underline;
  }

  .picker-close {
    position: absolute;
    inset-block-start: 4px;
    inset-inline-end: 4px;
    background: none;
    border: none;
    color: var(--color-text-tertiary);
    cursor: pointer;
    padding: 2px;
    border-radius: 50%;
    display: none;
  }
</style>
