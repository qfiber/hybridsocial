<script lang="ts">
  import { acceptCookies } from '$lib/stores/consent.js';

  let { onaccept }: { onaccept?: () => void } = $props();

  function handleAccept() {
    acceptCookies();
    onaccept?.();
  }
</script>

<div class="cookie-overlay">
  <div class="cookie-banner">
    <div class="cookie-icon">
      <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M12 2a10 10 0 1 0 10 10 4 4 0 0 1-5-5 4 4 0 0 1-5-5" />
        <path d="M8.5 8.5v.01" /><path d="M16 15.5v.01" /><path d="M12 12v.01" />
        <path d="M11 17v.01" /><path d="M7 14v.01" />
      </svg>
    </div>

    <h2 class="cookie-title">This site uses cookies</h2>

    <p class="cookie-text">
      We use essential cookies to keep you signed in and provide core functionality.
      These cookies are required — the site cannot work without them.
      We do not use tracking or advertising cookies.
    </p>

    <div class="cookie-links">
      <a href="/legal/privacy" class="cookie-link" data-sveltekit-reload>Privacy Policy</a>
      <span class="cookie-dot">&middot;</span>
      <a href="/legal/terms" class="cookie-link" data-sveltekit-reload>Terms of Service</a>
    </div>

    <button class="cookie-accept" onclick={handleAccept}>
      Accept &amp; Continue
    </button>
  </div>
</div>

<style>
  .cookie-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.6);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: flex-end;
    justify-content: center;
    z-index: 9999;
    padding: var(--space-4);
    animation: fadeIn 0.3s ease;
  }

  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes slideUp {
    from { opacity: 0; transform: translateY(20px); }
    to { opacity: 1; transform: translateY(0); }
  }

  .cookie-banner {
    background: var(--color-surface-raised);
    border-radius: var(--radius-xl) var(--radius-xl) 0 0;
    padding: var(--space-8);
    max-width: 540px;
    width: 100%;
    text-align: center;
    box-shadow: 0 -8px 40px rgba(0, 0, 0, 0.15);
    animation: slideUp 0.35s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .cookie-icon {
    margin-block-end: var(--space-4);
  }

  .cookie-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-3);
  }

  .cookie-text {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.6;
    margin-block-end: var(--space-4);
  }

  .cookie-links {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    margin-block-end: var(--space-6);
  }

  .cookie-link {
    font-size: var(--text-xs);
    color: var(--color-primary);
    text-decoration: none;
  }

  .cookie-link:hover {
    text-decoration: underline;
  }

  .cookie-dot {
    color: var(--color-text-tertiary);
    font-size: var(--text-xs);
  }

  .cookie-accept {
    display: block;
    width: 100%;
    padding: var(--space-3) var(--space-6);
    background: var(--color-primary);
    color: var(--color-text-on-primary);
    border: none;
    border-radius: var(--radius-lg);
    font-size: var(--text-base);
    font-weight: 600;
    cursor: pointer;
    transition: background 0.2s ease, transform 0.15s ease;
  }

  .cookie-accept:hover {
    background: var(--color-primary-hover);
  }

  .cookie-accept:active {
    transform: scale(0.985);
  }

  @media (min-width: 640px) {
    .cookie-overlay {
      align-items: center;
    }

    .cookie-banner {
      border-radius: var(--radius-xl);
    }
  }
</style>
