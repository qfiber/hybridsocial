<script lang="ts">
  import { goto } from '$app/navigation';
  import { browser } from '$app/environment';
  import { get } from 'svelte/store';
  import { onMount, onDestroy } from 'svelte';
  import { authStore, currentUser, isStaff, initAuth } from '$lib/stores/auth.js';
  import { sudoExpiresAt, isSudoValid } from '$lib/stores/admin-sudo.js';
  import { api } from '$lib/api/client.js';
  import AdminSidebar from '$lib/components/admin/AdminSidebar.svelte';
  import AdminTopBar from '$lib/components/admin/AdminTopBar.svelte';
  import { page } from '$app/state';
  import SudoGate from '$lib/components/admin/SudoGate.svelte';
  import Toast from '$lib/components/ui/Toast.svelte';

  let { children } = $props();
  let authorized = $state(false);
  let checking = $state(true);
  let checkingSudo = $state(true);
  let user = $derived($currentUser);
  // Admin sessions are high-value — the backend enforces the same rule,
  // but gating the UI up-front avoids rendering a panel whose every
  // request would 403 with admin.otp_required.
  // Either a TOTP authenticator or a registered security key satisfies
  // the staff 2FA gate (matches RequireAdmin on the backend) — so a
  // user with a passkey shouldn't see the "enable 2FA" wall.
  let needsOtp = $derived(
    !!user &&
      user.two_factor_enabled !== true &&
      (user as { security_keys_enabled?: boolean }).security_keys_enabled !== true,
  );
  let sudoOk = $derived(isSudoValid($sudoExpiresAt));

  let expiryTimer: ReturnType<typeof setInterval> | null = null;

  // Drawer state for narrow screens; any navigation closes it.
  let navOpen = $state(false);
  $effect(() => {
    void page.url.pathname;
    navOpen = false;
  });

  function onKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape' && navOpen) navOpen = false;
  }

  function onSudoRequired() {
    sudoExpiresAt.set(null);
  }

  async function fetchSudoStatus() {
    try {
      const res = await api.get<{ sudo: boolean; expires_at: string | null }>(
        '/api/v1/admin/sudo'
      );
      sudoExpiresAt.set(res.sudo ? res.expires_at : null);
    } catch {
      sudoExpiresAt.set(null);
    } finally {
      checkingSudo = false;
    }
  }

  function handleUnlocked(expiresAt: string) {
    sudoExpiresAt.set(expiresAt);
  }

  onMount(async () => {
    // Ensure auth is fully initialized (handles page refresh with cookie-based session)
    let state = get(authStore);
    if (!state.initialized) {
      await initAuth();
      state = get(authStore);
    }

    // Not logged in
    if (!state.user) {
      goto('/login', { replaceState: true });
      return;
    }

    // Not staff — don't reveal that admin exists
    if (!isStaff() && !state.user.is_admin) {
      goto('/home', { replaceState: true });
      return;
    }

    authorized = true;
    checking = false;

    // Probe sudo status if ANY second factor is set up (TOTP or a
    // security key). The needsOtp branch short-circuits rendering for
    // users with no second factor at all. Previously this only checked
    // TOTP, so security-key admins never detected an existing sudo
    // window and got re-prompted on every refresh.
    if (
      state.user.two_factor_enabled ||
      (state.user as { security_keys_enabled?: boolean }).security_keys_enabled
    ) {
      await fetchSudoStatus();
    } else {
      checkingSudo = false;
    }

    window.addEventListener('admin-sudo-required', onSudoRequired);

    // Watchdog: when the stored expiry passes, re-check before locking, since
    // activity in another tab may have extended the same window. This covers
    // the case without waiting for the next admin API call to 403.
    expiryTimer = setInterval(() => {
      const exp = get(sudoExpiresAt);
      if (exp && !isSudoValid(exp)) fetchSudoStatus();
    }, 30000);
  });

  onDestroy(() => {
    if (browser) window.removeEventListener('admin-sudo-required', onSudoRequired);
    if (expiryTimer) clearInterval(expiryTimer);
  });

  // Watch for logout or role changes while on admin pages
  $effect(() => {
    if (!browser || checking) return;

    const state = get(authStore);
    if (state.initialized && !state.user) {
      goto('/login', { replaceState: true });
    }
  });
</script>

<svelte:window onkeydown={onKeydown} />

{#if authorized}
  <div class="admin-layout">
    <AdminSidebar open={navOpen} onclose={() => (navOpen = false)} />
    <div class="admin-main">
      <AdminTopBar menuOpen={navOpen} onmenu={() => (navOpen = !navOpen)} />
      <main class="admin-content">
        {#if needsOtp}
          <div class="otp-gate" role="alert">
            <div class="otp-gate-card">
              <div class="otp-gate-icon" aria-hidden="true">
                <svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
                  <rect x="3" y="11" width="18" height="11" rx="2" />
                  <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                </svg>
              </div>
              <h2 class="otp-gate-title">Enable two-factor authentication</h2>
              <p class="otp-gate-text">
                Admin accounts must have 2FA enabled before they can access
                the admin panel. This protects the instance from a
                compromised staff password.
              </p>
              <a class="otp-gate-btn" href="/settings/security">
                Set up two-factor authentication
              </a>
              <p class="otp-gate-hint">
                You'll be brought back here after you finish setup.
              </p>
            </div>
          </div>
        {:else if checkingSudo}
          <div class="admin-loading">
            <div class="admin-loading-spinner"></div>
          </div>
        {:else if !sudoOk}
          <SudoGate onUnlocked={handleUnlocked} />
        {:else}
          {@render children()}
        {/if}
      </main>
    </div>
  </div>
  <Toast />
{:else}
  <div class="admin-loading">
    <div class="admin-loading-spinner"></div>
  </div>
{/if}

<style>
  .admin-layout {
    display: flex;
    min-height: 100vh;
  }

  .admin-main {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    background: var(--color-bg);
  }

  .admin-content {
    flex: 1;
    min-width: 0;
    padding: var(--space-6) var(--space-8);
  }

  .admin-loading {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
  }

  .admin-loading-spinner {
    width: 32px;
    height: 32px;
    border: 3px solid var(--color-border);
    border-top-color: var(--color-primary);
    border-radius: 50%;
    animation: spin 0.6s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  @media (max-width: 1024px) {
    .admin-content {
      padding: var(--space-4);
    }
  }

  .otp-gate {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: calc(100vh - var(--space-12));
    padding: var(--space-4);
  }

  .otp-gate-card {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-8);
    max-width: 440px;
    width: 100%;
    text-align: center;
    box-shadow: 0 4px 24px var(--scrim-soft);
  }

  .otp-gate-icon {
    margin-block-end: var(--space-4);
    display: flex;
    justify-content: center;
  }

  .otp-gate-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-3);
  }

  .otp-gate-text {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.6;
    margin-block-end: var(--space-6);
  }

  .otp-gate-btn {
    display: inline-block;
    padding: var(--space-3) var(--space-6);
    background: var(--color-primary);
    color: var(--color-text-on-primary);
    border-radius: var(--radius-lg);
    font-size: var(--text-base);
    font-weight: 600;
    text-decoration: none;
    transition: background 0.15s ease;
  }

  .otp-gate-btn:hover {
    background: var(--color-primary-hover);
    text-decoration: none;
  }

  .otp-gate-hint {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-start: var(--space-4);
  }
</style>
