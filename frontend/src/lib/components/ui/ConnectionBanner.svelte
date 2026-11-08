<script lang="ts">
  import { goto } from '$app/navigation';
  import { clearAuth, sessionExpired, serverReachable } from '$lib/stores/auth.js';

  let expired = $state(false);
  let reachable = $state(true);

  // Offline-view dismissal: user explicitly closed the "Connection
  // lost" dialog to keep reading what was already loaded. A tiny
  // corner pill stays visible so they don't forget, and the moment
  // the server comes back we reopen the full dialog (well, it
  // auto-hides since reachable flips to true and there's nothing
  // left to show) and reset the dismissed flag.
  let offlineDismissed = $state(false);

  serverReachable.subscribe((v) => {
    reachable = v;
    if (v) offlineDismissed = false;
  });
  sessionExpired.subscribe((v) => {
    expired = v;
    if (v) {
      setTimeout(() => {
        clearAuth();
        goto('/login?expired=1');
      }, 3000);
    }
  });

  function dismissOffline() {
    offlineDismissed = true;
  }

  function reopenOffline() {
    offlineDismissed = false;
  }
</script>

{#if !reachable && !offlineDismissed}
  <div class="overlay" role="alertdialog" aria-labelledby="conn-title" aria-describedby="conn-desc">
    <div class="card">
      <button
        type="button"
        class="close"
        onclick={dismissOffline}
        aria-label="Close — keep reading offline"
        title="Close — keep reading what's already loaded"
      >
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="6" y1="6" x2="18" y2="18"/><line x1="18" y1="6" x2="6" y2="18"/></svg>
      </button>

      <div class="icon" aria-hidden="true">
        <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
          <path d="M2 8.82a15 15 0 0 1 20 0" />
          <path d="M5 12.859a10 10 0 0 1 14 0" />
          <path d="M8.5 16.429a5 5 0 0 1 7 0" />
          <line x1="12" y1="20" x2="12" y2="20.01" />
          <line x1="3" y1="3" x2="21" y2="21" stroke="var(--color-danger, #dc2626)" stroke-width="2" />
        </svg>
      </div>

      <h2 id="conn-title" class="title">Connection lost</h2>
      <p id="conn-desc" class="text">Unable to reach the server.</p>
      <p class="status" aria-live="polite">
        <span>Reconnecting</span><span class="dots" aria-hidden="true"><span>.</span><span>.</span><span>.</span></span>
      </p>

      <button type="button" class="keep-reading" onclick={dismissOffline}>
        Keep reading offline
      </button>
    </div>
  </div>
{:else if !reachable && offlineDismissed}
  <!-- Persistent reminder pill so the user doesn't forget they're
       offline. Clicking it reopens the full dialog. -->
  <button type="button" class="offline-pill" onclick={reopenOffline} aria-label="You are offline — tap for details">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
      <path d="M2 8.82a15 15 0 0 1 20 0" />
      <line x1="3" y1="3" x2="21" y2="21" />
    </svg>
    Offline
  </button>
{:else if expired}
  <div class="overlay" role="alertdialog" aria-labelledby="expired-title">
    <div class="card">
      <div class="icon" aria-hidden="true">
        <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
          <rect x="3" y="11" width="18" height="11" rx="2" />
          <path d="M7 11V7a5 5 0 0 1 10 0v4" />
        </svg>
      </div>
      <h2 id="expired-title" class="title">Session expired</h2>
      <p class="text">Your session has timed out.</p>
      <p class="status" aria-live="polite">
        <span>Redirecting to login</span><span class="dots" aria-hidden="true"><span>.</span><span>.</span><span>.</span></span>
      </p>
    </div>
  </div>
{/if}

<style>
  .overlay {
    position: fixed;
    inset: 0;
    background: var(--scrim-medium);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 9999;
    padding: var(--space-4);
    animation: fadeIn 0.25s ease;
  }

  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes slideUp {
    from { opacity: 0; transform: translateY(12px) scale(0.98); }
    to { opacity: 1; transform: translateY(0) scale(1); }
  }

  .card {
    position: relative;
    background: var(--color-surface-raised);
    border-radius: var(--radius-xl);
    padding: var(--space-8);
    max-width: 420px;
    width: 100%;
    text-align: center;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.25);
    animation: slideUp 0.3s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .close {
    position: absolute;
    top: 12px;
    inset-inline-end: 12px;
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: transparent;
    border: none;
    border-radius: 9999px;
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: background 0.15s ease, color 0.15s ease;
  }

  .close:hover {
    background: var(--color-surface);
    color: var(--color-text);
  }

  .icon {
    margin-block-end: var(--space-4);
    display: flex;
    justify-content: center;
  }

  .title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .text {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-3);
  }

  .status {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    display: inline-flex;
    align-items: baseline;
    justify-content: center;
    gap: 1px;
    margin: 0;
  }

  .dots {
    display: inline-flex;
    width: 1.25em;
    letter-spacing: 1px;
  }

  .dots span {
    opacity: 0.2;
    animation: dot-pulse 1.2s infinite;
  }

  .dots span:nth-child(2) { animation-delay: 0.2s; }
  .dots span:nth-child(3) { animation-delay: 0.4s; }

  @keyframes dot-pulse {
    0%, 60%, 100% { opacity: 0.2; }
    30% { opacity: 1; }
  }

  .keep-reading {
    margin-block-start: var(--space-4);
    padding: 8px 14px;
    background: transparent;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
    font-weight: 500;
    cursor: pointer;
    transition: background 0.15s ease, color 0.15s ease, border-color 0.15s ease;
  }

  .keep-reading:hover {
    background: var(--color-surface);
    color: var(--color-text);
    border-color: var(--color-text-tertiary);
  }

  /* Persistent offline indicator — small pill anchored to the
     bottom so the user can tap it to reopen the dialog. */
  .offline-pill {
    position: fixed;
    inset-block-end: 16px;
    /* Physical `left`: centering is direction-neutral, and with
       `inset-inline-start` an RTL page anchors from the right while
       translateX(-50%) still shifts left — a full width off-center. */
    left: 50%;
    transform: translateX(-50%);
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 6px 14px;
    background: rgba(25, 28, 29, 0.92);
    color: #fff;
    border: none;
    border-radius: 9999px;
    font-size: 0.8rem;
    font-weight: 600;
    cursor: pointer;
    z-index: 9998;
    box-shadow: 0 6px 20px rgba(0, 0, 0, 0.25);
  }

  .offline-pill:hover {
    background: rgba(25, 28, 29, 1);
  }

  @media (prefers-reduced-motion: reduce) {
    .overlay { animation: none; }
    .card { animation: none; }
    .dots span { animation: none; opacity: 0.6; }
  }
</style>
