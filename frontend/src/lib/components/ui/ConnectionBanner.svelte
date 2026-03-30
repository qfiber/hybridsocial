<script lang="ts">
  import { goto } from '$app/navigation';
  import { clearAuth, sessionExpired, serverReachable } from '$lib/stores/auth.js';

  let expired = $state(false);
  let reachable = $state(true);

  serverReachable.subscribe((v) => (reachable = v));
  sessionExpired.subscribe((v) => {
    expired = v;
    if (v) {
      setTimeout(() => {
        clearAuth();
        goto('/login?expired=1');
      }, 3000);
    }
  });
</script>

{#if !reachable}
  <div class="connection-banner connection-offline" role="alert">
    <span class="material-symbols-outlined banner-icon">cloud_off</span>
    <div class="banner-text">
      <strong>Connection lost</strong>
      <span>Unable to reach the server. Reconnecting...</span>
    </div>
  </div>
{:else if expired}
  <div class="connection-banner connection-expired" role="alert">
    <span class="material-symbols-outlined banner-icon">lock_clock</span>
    <div class="banner-text">
      <strong>Session expired</strong>
      <span>Redirecting to login...</span>
    </div>
  </div>
{/if}

<style>
  .connection-banner {
    position: fixed;
    top: var(--header-height, 56px);
    inset-inline: 0;
    z-index: 9000;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    padding: 10px 20px;
    font-size: 0.875rem;
    animation: banner-slide-down 0.3s ease;
  }

  @keyframes banner-slide-down {
    from { transform: translateY(-100%); opacity: 0; }
    to { transform: translateY(0); opacity: 1; }
  }

  .connection-offline {
    background: #dc2626;
    color: white;
  }

  .connection-expired {
    background: #f59e0b;
    color: #1a1a1a;
  }

  .banner-icon {
    font-size: 20px;
    flex-shrink: 0;
  }

  .banner-text {
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .banner-text strong {
    font-weight: 700;
  }

  .banner-text span {
    opacity: 0.9;
  }
</style>
