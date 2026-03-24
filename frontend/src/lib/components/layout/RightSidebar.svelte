<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getPromotedUsers, getPromotionPricing, purchasePromotion, formatPrice } from '$lib/api/promotions.js';
  import type { PromotedUser, PromotionPricing } from '$lib/api/promotions.js';

  let {
    trending = [],
    suggestions = []
  }: {
    trending?: { tag: string; count: number }[];
    suggestions?: { handle: string; display_name: string; avatar_url: string | null }[];
  } = $props();

  let promotedUsers: PromotedUser[] = $state([]);
  let pricing: PromotionPricing | null = $state(null);
  let showPromoModal = $state(false);

  let allSuggestions = $derived([
    ...promotedUsers,
    ...suggestions.filter(s => !promotedUsers.some(p => p.handle === s.handle))
  ]);

  onMount(async () => {
    try {
      const [users, pricingData] = await Promise.all([
        getPromotedUsers().catch(() => [] as PromotedUser[]),
        getPromotionPricing().catch(() => null)
      ]);
      promotedUsers = users;
      pricing = pricingData;
    } catch {
      // Sidebar is non-critical
    }
  });

  async function handlePurchase() {
    try {
      await purchasePromotion();
      showPromoModal = false;
      addToast('Profile promotion activated!', 'success');
      promotedUsers = await getPromotedUsers().catch(() => []);
    } catch (err: unknown) {
      const error = err as { body?: { error?: string } };
      if (error?.body?.error === 'promotions.already_active') {
        addToast('You already have an active promotion', 'error');
      } else {
        addToast('Failed to purchase promotion', 'error');
      }
    }
  }
</script>

<aside class="right-sidebar">
  <section class="sidebar-section">
    <h3 class="section-title">Trending</h3>
    {#if trending.length > 0}
      <ul class="trending-list">
        {#each trending as item (item.tag)}
          <li>
            <a href="/explore?q=%23{encodeURIComponent(item.tag)}" class="trending-item">
              <span class="trending-tag">#{item.tag}</span>
              <span class="trending-count">{item.count} posts</span>
            </a>
          </li>
        {/each}
      </ul>
    {:else}
      <p class="empty-text">No trending topics yet.</p>
    {/if}
  </section>

  <section class="sidebar-section">
    <h3 class="section-title">Who to follow</h3>
    {#if allSuggestions.length > 0}
      <ul class="suggestions-list">
        {#each allSuggestions as person (person.handle)}
          <li>
            <a href="/@{person.handle}" class="suggestion-item">
              <div class="suggestion-avatar">
                {#if person.avatar_url}
                  <img src={person.avatar_url} alt={person.display_name} class="suggestion-img" />
                {:else}
                  <span class="suggestion-initial">{person.display_name.charAt(0).toUpperCase()}</span>
                {/if}
              </div>
              <div class="suggestion-info">
                <span class="suggestion-name">
                  {person.display_name}
                  {#if 'promoted' in person && person.promoted}
                    <span class="promoted-badge">Promoted</span>
                  {/if}
                </span>
                <span class="suggestion-handle">@{person.handle}</span>
              </div>
            </a>
          </li>
        {/each}
      </ul>
    {:else}
      <p class="empty-text">No suggestions right now.</p>
    {/if}
  </section>

  {#if pricing?.enabled}
    <section class="sidebar-section promo-cta">
      <div class="promo-cta-icon">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>
        </svg>
      </div>
      <h4 class="promo-cta-title">Promote your profile</h4>
      <p class="promo-cta-text">
        Get featured in "Who to follow" for {pricing.duration_days} days.
      </p>
      <button class="promo-cta-btn" onclick={() => showPromoModal = true}>
        Promote for {formatPrice(pricing.price_cents, pricing.currency)}
      </button>
    </section>
  {/if}

  <section class="sidebar-footer">
    <nav class="footer-links" aria-label="Footer">
      <a href="/legal/about" class="footer-link">About</a>
      <span class="footer-dot" aria-hidden="true">&middot;</span>
      <a href="/legal/privacy" class="footer-link">Privacy</a>
      <span class="footer-dot" aria-hidden="true">&middot;</span>
      <a href="/legal/terms" class="footer-link">Terms</a>
    </nav>
    <p class="footer-text">HybridSocial &middot; Decentralized Social</p>
  </section>
</aside>

{#if showPromoModal && pricing}
  <div class="modal-overlay" onclick={() => showPromoModal = false} role="presentation">
    <div class="modal-card" onclick={(e) => e.stopPropagation()} role="dialog" aria-labelledby="promo-modal-title">
      <button class="modal-close" onclick={() => showPromoModal = false} aria-label="Close">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
        </svg>
      </button>

      <div class="modal-icon">
        <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>
        </svg>
      </div>

      <h3 id="promo-modal-title" class="modal-title">Promote Your Profile</h3>
      <p class="modal-desc">
        Your profile will appear in the "Who to follow" section for all users
        on this server for <strong>{pricing.duration_days} days</strong>.
      </p>

      <div class="modal-pricing">
        <div class="modal-price">{formatPrice(pricing.price_cents, pricing.currency)}</div>
        <div class="modal-period">for {pricing.duration_days} days</div>
      </div>

      <ul class="modal-features">
        <li>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
          Featured in "Who to follow" sidebar
        </li>
        <li>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
          "Promoted" badge on your listing
        </li>
        <li>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
          Reach new followers organically
        </li>
        <li>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
          Active immediately after payment
        </li>
      </ul>

      <button class="modal-buy-btn" onclick={handlePurchase}>
        Purchase Promotion
      </button>

      <p class="modal-note">
        Payment processing coming soon. Promotion activates instantly for testing.
      </p>
    </div>
  </div>
{/if}

<style>
  .right-sidebar {
    position: sticky;
    top: calc(var(--header-height) + var(--space-8));
    height: calc(100vh - var(--header-height) - var(--space-8));
    padding: var(--space-2) 0;
    overflow-y: auto;
  }

  .sidebar-section {
    margin-block-end: var(--space-4);
    background: var(--color-surface-container-lowest);
    border-radius: var(--radius-xl);
    padding: var(--space-5);
    border: 1px solid rgba(188, 201, 200, 0.15);
    box-shadow: 0 1px 3px rgba(25, 28, 29, 0.04);
  }

  .section-title {
    font-family: var(--font-headline);
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-on-surface);
    margin-block-end: var(--space-3);
  }

  .trending-list,
  .suggestions-list {
    display: flex;
    flex-direction: column;
  }

  .trending-item {
    display: flex;
    flex-direction: column;
    padding: var(--space-2) var(--space-3);
    margin-inline: calc(-1 * var(--space-3));
    text-decoration: none;
    color: var(--color-on-surface);
    border-radius: var(--radius-lg);
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .trending-item:hover {
    text-decoration: none;
    background: var(--color-surface-container-low);
    color: var(--color-primary);
  }

  .trending-tag {
    font-weight: 600;
    font-size: var(--text-sm);
  }

  .trending-count {
    font-size: var(--text-xs);
    color: var(--color-on-surface-variant);
  }

  .suggestion-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-2) var(--space-3);
    margin-inline: calc(-1 * var(--space-3));
    text-decoration: none;
    color: var(--color-on-surface);
    border-radius: var(--radius-lg);
    transition: background var(--transition-fast);
  }

  .suggestion-item:hover {
    text-decoration: none;
    background: var(--color-surface-container-low);
  }

  .suggestion-avatar {
    width: 36px;
    height: 36px;
    border-radius: var(--radius-full);
    background: var(--color-secondary-container);
    overflow: hidden;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .suggestion-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .suggestion-initial {
    font-family: var(--font-headline);
    font-weight: 600;
    color: var(--color-primary);
    font-size: var(--text-sm);
  }

  .suggestion-info {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .suggestion-name {
    font-size: var(--text-sm);
    font-weight: 500;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .promoted-badge {
    font-size: 0.6rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-primary);
    background: var(--color-secondary-container);
    padding: 1px 5px;
    border-radius: var(--radius-full);
    flex-shrink: 0;
  }

  .suggestion-handle {
    font-size: var(--text-xs);
    color: var(--color-on-surface-variant);
  }

  .empty-text {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  /* ---- Promote CTA ---- */
  .promo-cta {
    background: linear-gradient(180deg, var(--color-secondary-container) 0%, var(--color-surface-container-lowest) 100%);
    text-align: center;
  }

  .promo-cta-icon {
    color: var(--color-primary);
    margin-block-end: var(--space-2);
  }

  .promo-cta-title {
    font-family: var(--font-headline);
    font-size: var(--text-sm);
    font-weight: 700;
    color: var(--color-on-surface);
    margin-block-end: var(--space-1);
  }

  .promo-cta-text {
    font-size: var(--text-xs);
    color: var(--color-on-surface-variant);
    line-height: 1.4;
    margin-block-end: var(--space-3);
  }

  .promo-cta-btn {
    display: block;
    width: 100%;
    padding: var(--space-2) var(--space-3);
    background: var(--gradient-primary);
    color: var(--color-on-primary);
    border: none;
    border-radius: var(--radius-full);
    font-size: var(--text-sm);
    font-weight: 600;
    cursor: pointer;
    transition: box-shadow var(--transition-fast), transform 0.15s ease;
  }

  .promo-cta-btn:hover {
    box-shadow: var(--shadow-md);
  }

  .promo-cta-btn:active {
    transform: scale(0.98);
  }

  /* ---- Modal ---- */
  .modal-overlay {
    position: fixed;
    inset: 0;
    background: var(--color-overlay);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    padding: var(--space-4);
    animation: fadeIn 0.2s ease;
  }

  .modal-card {
    background: var(--color-surface-container-lowest);
    border-radius: var(--radius-xl);
    padding: var(--space-8);
    max-width: 420px;
    width: 100%;
    position: relative;
    box-shadow: var(--shadow-xl);
    animation: scaleIn 0.25s cubic-bezier(0.22, 1, 0.36, 1);
  }

  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes scaleIn {
    from { opacity: 0; transform: scale(0.95) translateY(8px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .modal-close {
    position: absolute;
    top: var(--space-4);
    right: var(--space-4);
    background: none;
    border: none;
    color: var(--color-text-tertiary);
    cursor: pointer;
    padding: var(--space-1);
    border-radius: var(--radius-full);
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .modal-close:hover {
    color: var(--color-on-surface);
    background: var(--color-surface-container-low);
  }

  .modal-icon {
    display: flex;
    justify-content: center;
    margin-block-end: var(--space-4);
  }

  .modal-title {
    font-family: var(--font-headline);
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-on-surface);
    text-align: center;
    margin-block-end: var(--space-2);
  }

  .modal-desc {
    font-size: var(--text-sm);
    color: var(--color-on-surface-variant);
    text-align: center;
    line-height: 1.5;
    margin-block-end: var(--space-5);
  }

  .modal-pricing {
    text-align: center;
    padding: var(--space-4);
    background: var(--color-surface-container-low);
    border-radius: var(--radius-xl);
    margin-block-end: var(--space-5);
  }

  .modal-price {
    font-family: var(--font-headline);
    font-size: var(--text-3xl);
    font-weight: 800;
    color: var(--color-on-surface);
  }

  .modal-period {
    font-size: var(--text-sm);
    color: var(--color-on-surface-variant);
  }

  .modal-features {
    list-style: none;
    padding: 0;
    margin: 0 0 var(--space-6) 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .modal-features li {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    color: var(--color-on-surface);
  }

  .modal-features li svg {
    flex-shrink: 0;
  }

  .modal-buy-btn {
    display: block;
    width: 100%;
    padding: var(--space-3);
    background: var(--gradient-primary);
    color: var(--color-on-primary);
    border: none;
    border-radius: var(--radius-full);
    font-size: var(--text-base);
    font-weight: 600;
    cursor: pointer;
    transition: box-shadow var(--transition-fast), transform 0.15s ease;
  }

  .modal-buy-btn:hover {
    box-shadow: var(--shadow-md);
  }

  .modal-buy-btn:active {
    transform: scale(0.98);
  }

  .modal-note {
    text-align: center;
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-start: var(--space-3);
  }

  /* ---- Footer ---- */
  .sidebar-footer {
    padding: var(--space-4) var(--space-2) 0;
  }

  .footer-links {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    margin-block-end: var(--space-2);
  }

  .footer-link {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    text-decoration: none;
  }

  .footer-link:hover {
    color: var(--color-primary);
    text-decoration: underline;
  }

  .footer-dot {
    color: var(--color-text-tertiary);
    font-size: var(--text-xs);
  }

  .footer-text {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  @media (max-width: 1280px) {
    .right-sidebar {
      display: none;
    }
  }
</style>
