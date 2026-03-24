<script lang="ts">
  import { goto } from '$app/navigation';
  import { api, ApiError } from '$lib/api/client.js';
  import { setTokens, setUser } from '$lib/stores/auth.js';
  import { getCurrentUser } from '$lib/api/auth.js';
  import { subscribeToPush } from '$lib/utils/push.js';
  import { tError } from '$lib/utils/i18n.js';

  let email = $state('');
  let password = $state('');
  let showPassword = $state(false);
  let otpCode = $state('');
  let error = $state('');
  let loading = $state(false);
  let otpRequired = $state(false);
  let otpIdentityId = $state('');
  let otpCountdown = $state(60);
  let otpExpired = $state(false);
  let countdownInterval: ReturnType<typeof setInterval> | null = null;

  function startCountdown() {
    otpCountdown = 60;
    otpExpired = false;
    if (countdownInterval) clearInterval(countdownInterval);
    countdownInterval = setInterval(() => {
      otpCountdown -= 1;
      if (otpCountdown <= 0) {
        otpExpired = true;
        if (countdownInterval) clearInterval(countdownInterval);
      }
    }, 1000);
  }

  function formatCountdown(seconds: number): string {
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
  }

  async function handleSubmit(e: SubmitEvent) {
    e.preventDefault();
    error = '';
    loading = true;

    try {
      if (otpRequired && otpCode) {
        const result = await api.post<{
          access_token?: string;
          refresh_token?: string;
          expires_in?: number;
          identity_id?: string;
        }>('/api/v1/auth/2fa/login', {
          identity_id: otpIdentityId,
          code: otpCode
        });

        if (result.access_token && result.refresh_token) {
          if (countdownInterval) clearInterval(countdownInterval);
          setTokens({
            access_token: result.access_token,
            refresh_token: result.refresh_token,
            expires_in: result.expires_in || 900,
            token_type: 'Bearer',
            identity_id: result.identity_id || ''
          });
          try {
            const user = await getCurrentUser();
            setUser(user);
          } catch {}
          subscribeToPush(result.access_token);
          await goto('/home');
        }
      } else {
        const result = await api.post<{
          access_token?: string;
          refresh_token?: string;
          otp_required?: boolean;
          identity_id?: string;
          expires_in?: number;
        }>('/api/v1/auth/login', { email, password });

        if (result.otp_required) {
          otpRequired = true;
          otpIdentityId = result.identity_id || '';
          startCountdown();
          loading = false;
          return;
        }

        if (result.access_token && result.refresh_token) {
          setTokens({
            access_token: result.access_token,
            refresh_token: result.refresh_token,
            expires_in: result.expires_in || 900,
            token_type: 'Bearer',
            identity_id: result.identity_id || ''
          });
          try {
            const user = await getCurrentUser();
            setUser(user);
          } catch {}
          subscribeToPush(result.access_token);
          await goto('/home');
        }
      }
    } catch (err) {
      if (err instanceof ApiError) {
        error = err.body.error_description || tError(err.body.error);
      } else {
        error = 'An unexpected error occurred. Please try again.';
      }
    } finally {
      loading = false;
    }
  }

  function resetOtp() {
    otpRequired = false;
    otpCode = '';
    otpIdentityId = '';
    otpExpired = false;
    error = '';
    if (countdownInterval) clearInterval(countdownInterval);
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') {
      const form = (e.target as HTMLElement).closest('form');
      if (form) form.requestSubmit();
    }
  }
</script>

<svelte:head>
  <title>Sign in - HybridSocial</title>
</svelte:head>

<div class="signin-card">
  <div class="signin-logo">
    <svg width="44" height="44" viewBox="0 0 28 28" fill="none" aria-hidden="true">
      <rect rx="6" width="28" height="28" fill="var(--color-primary)" />
      <text x="14" y="19.5" text-anchor="middle" fill="white" font-size="15" font-weight="700">H</text>
    </svg>
  </div>

  <h1 class="signin-title">Sign in to your server</h1>
  <p class="signin-subtitle">Enter your credentials to continue</p>

  {#if error}
    <div class="auth-error" role="alert">
      <span class="auth-error-icon" aria-hidden="true">!</span>
      {error}
    </div>
  {/if}

  <form onsubmit={handleSubmit} novalidate>
    {#if !otpRequired}
      <div class="form-field">
        <input
          id="email"
          type="email"
          class="form-input"
          placeholder="Email or username"
          bind:value={email}
          required
          disabled={loading}
          autocomplete="email"
        />
      </div>

      <div class="form-field">
        <div class="input-with-icon">
          <input
            id="password"
            type={showPassword ? 'text' : 'password'}
            class="form-input"
            placeholder="Password"
            bind:value={password}
            required
            disabled={loading}
            autocomplete="current-password"
            onkeydown={handleKeydown}
          />
          <button
            type="button"
            class="password-toggle"
            onclick={() => showPassword = !showPassword}
            tabindex={-1}
            aria-label={showPassword ? 'Hide password' : 'Show password'}
          >
            {#if showPassword}
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94" />
                <path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19" />
                <line x1="1" y1="1" x2="23" y2="23" />
              </svg>
            {:else}
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
                <circle cx="12" cy="12" r="3" />
              </svg>
            {/if}
          </button>
        </div>
      </div>
    {:else}
      {#if otpExpired}
        <div class="otp-expired">
          <p class="otp-expired-text">Verification expired. Please try again.</p>
        </div>
      {:else}
        <div class="form-field">
          <div class="otp-header">
            <label for="otp" class="form-label">Two-factor code</label>
            <span class="otp-timer" class:otp-timer-warning={otpCountdown <= 10}>
              {formatCountdown(otpCountdown)}
            </span>
          </div>
          <p class="form-hint">Enter the code from your authenticator app</p>
          <input
            id="otp"
            type="text"
            inputmode="numeric"
            pattern="[0-9]*"
            maxlength={6}
            class="form-input otp-input"
            placeholder="000000"
            bind:value={otpCode}
            required
            disabled={loading}
            autocomplete="one-time-code"
            onkeydown={handleKeydown}
          />
        </div>
      {/if}
    {/if}

    {#if otpExpired}
      <button type="button" class="auth-submit" onclick={resetOtp}>
        Try Again
      </button>
    {:else}
      <button type="submit" class="auth-submit" disabled={loading || (otpRequired && otpExpired)}>
        {#if loading}
          <span class="spinner" aria-hidden="true"></span>
          Signing in...
        {:else if otpRequired}
          Verify
        {:else}
          Sign in
        {/if}
      </button>
    {/if}
  </form>

  {#if otpRequired && !otpExpired}
    <button
      type="button"
      class="auth-back-btn"
      onclick={resetOtp}
    >
      Back to sign in
    </button>
  {/if}

  {#if !otpRequired}
    <div class="divider">
      <span>or</span>
    </div>

    <a href="/register" class="create-account-btn">Create account</a>
  {/if}
</div>

{#if !otpRequired}
  <div class="new-to-hs">
    <h3 class="new-to-hs-title">New to HybridSocial?</h3>
    <p class="new-to-hs-desc">
      Create your own server in minutes or join a community run by others.
    </p>
    <a href="/register" class="new-to-hs-link">Create a server &rarr;</a>
    <a href="/explore" class="new-to-hs-link">Explore servers &rarr;</a>
  </div>
{/if}

<style>
  /* ---- Sign-in card ---- */
  .signin-card {
    background: white;
    border-radius: var(--radius-xl);
    padding: var(--space-8);
    border: 1px solid var(--color-border);
  }

  .signin-logo {
    display: flex;
    justify-content: center;
    margin-block-end: var(--space-6);
  }

  .signin-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
    text-align: center;
    margin-block-end: var(--space-1);
  }

  .signin-subtitle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    text-align: center;
    margin-block-end: var(--space-6);
  }

  /* ---- Error ---- */
  .auth-error {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-3);
    margin-block-end: var(--space-4);
    background: var(--color-danger-soft);
    border: 1px solid var(--color-danger);
    border-radius: var(--radius-md);
    color: var(--color-danger);
    font-size: var(--text-sm);
  }

  .auth-error-icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 20px;
    height: 20px;
    border-radius: var(--radius-full);
    background: var(--color-danger);
    color: white;
    font-size: var(--text-xs);
    font-weight: 700;
    flex-shrink: 0;
  }

  /* ---- Form ---- */
  .form-field {
    margin-block-end: var(--space-3);
  }

  .form-label {
    display: block;
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
    margin-block-end: var(--space-1);
  }

  .form-hint {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-2);
  }

  .form-input {
    display: block;
    width: 100%;
    height: 44px;
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    font-size: var(--text-sm);
    color: var(--color-text);
    background-color: var(--color-bg);
    transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
  }

  .form-input::placeholder {
    color: var(--color-text-tertiary);
  }

  .form-input:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px var(--color-primary-soft);
  }

  .form-input:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .input-with-icon {
    position: relative;
  }

  .input-with-icon .form-input {
    padding-inline-end: 44px;
  }

  .password-toggle {
    position: absolute;
    right: 0;
    top: 0;
    height: 44px;
    width: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: none;
    border: none;
    color: var(--color-text-tertiary);
    cursor: pointer;
  }

  .password-toggle:hover {
    color: var(--color-text-secondary);
  }

  /* ---- OTP ---- */
  .otp-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-block-end: var(--space-1);
  }

  .otp-header .form-label {
    margin-block-end: 0;
  }

  .otp-timer {
    font-family: var(--font-mono, monospace);
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text-secondary);
    background: var(--color-surface);
    padding: var(--space-1) var(--space-2);
    border-radius: var(--radius-sm);
  }

  .otp-timer-warning {
    color: var(--color-danger);
    background: var(--color-danger-soft);
  }

  .otp-expired {
    text-align: center;
    padding: var(--space-8) var(--space-4);
  }

  .otp-expired-text {
    color: var(--color-danger);
    font-size: var(--text-sm);
    font-weight: 500;
  }

  .otp-input {
    text-align: center;
    letter-spacing: 0.5em;
    font-size: var(--text-lg);
    font-weight: 600;
  }

  /* ---- Buttons ---- */
  .auth-submit {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    width: 100%;
    height: 44px;
    margin-block-start: var(--space-4);
    padding: var(--space-2) var(--space-4);
    background: var(--color-primary);
    color: var(--color-text-on-primary);
    border: none;
    border-radius: var(--radius-lg);
    font-size: var(--text-sm);
    font-weight: 600;
    cursor: pointer;
    transition: background-color var(--transition-fast);
  }

  .auth-submit:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .auth-submit:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .auth-back-btn {
    display: block;
    width: 100%;
    margin-block-start: var(--space-3);
    padding: var(--space-2);
    background: transparent;
    border: none;
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
    cursor: pointer;
  }

  .auth-back-btn:hover {
    color: var(--color-text);
  }

  /* ---- Divider ---- */
  .divider {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    margin: var(--space-5) 0;
  }

  .divider::before,
  .divider::after {
    content: '';
    flex: 1;
    height: 1px;
    background: var(--color-border);
  }

  .divider span {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  /* ---- Create account ---- */
  .create-account-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 100%;
    height: 44px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-primary);
    text-decoration: none;
    transition: background-color var(--transition-fast), border-color var(--transition-fast);
  }

  .create-account-btn:hover {
    background: var(--color-surface);
    border-color: var(--color-primary);
  }

  /* ---- New to HS box ---- */
  .new-to-hs {
    margin-block-start: var(--space-4);
    padding: var(--space-5);
    background: white;
    border-radius: var(--radius-xl);
    border: 1px solid var(--color-border);
  }

  .new-to-hs-title {
    font-size: var(--text-sm);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-1);
  }

  .new-to-hs-desc {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    line-height: 1.5;
    margin-block-end: var(--space-3);
  }

  .new-to-hs-link {
    display: block;
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-primary);
    text-decoration: none;
    margin-block-end: var(--space-1);
  }

  .new-to-hs-link:hover {
    text-decoration: underline;
  }

  /* ---- Entrance animations ---- */
  @keyframes fadeUp {
    from {
      opacity: 0;
      transform: translateY(16px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  @keyframes scaleIn {
    from {
      opacity: 0;
      transform: scale(0.92);
    }
    to {
      opacity: 1;
      transform: scale(1);
    }
  }

  .signin-logo {
    animation: scaleIn 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.1s both;
  }

  .signin-title {
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.15s both;
  }

  .signin-subtitle {
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.2s both;
  }

  .form-field:nth-child(1) {
    animation: fadeUp 0.45s cubic-bezier(0.22, 1, 0.36, 1) 0.25s both;
  }

  .form-field:nth-child(2) {
    animation: fadeUp 0.45s cubic-bezier(0.22, 1, 0.36, 1) 0.3s both;
  }

  .auth-submit {
    animation: fadeUp 0.45s cubic-bezier(0.22, 1, 0.36, 1) 0.35s both;
  }

  .divider {
    animation: fadeUp 0.4s cubic-bezier(0.22, 1, 0.36, 1) 0.4s both;
  }

  .create-account-btn {
    animation: fadeUp 0.4s cubic-bezier(0.22, 1, 0.36, 1) 0.45s both;
  }

  .new-to-hs {
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.5s both;
  }

  /* Interactive hover lift on cards */
  .signin-card {
    transition: box-shadow 0.3s ease;
  }

  .signin-card:focus-within {
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.06);
  }

  .new-to-hs {
    transition: box-shadow 0.3s ease;
  }

  .new-to-hs:hover {
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.04);
  }

  /* Smooth focus transitions on inputs */
  .form-input {
    transition: border-color 0.25s ease, box-shadow 0.25s ease, transform 0.15s ease;
  }

  .form-input:focus {
    transform: translateY(-1px);
  }

  /* Button press effect */
  .auth-submit:active:not(:disabled) {
    transform: scale(0.985);
  }

  .create-account-btn:active {
    transform: scale(0.985);
  }

  @media (prefers-reduced-motion: reduce) {
    .signin-logo,
    .signin-title,
    .signin-subtitle,
    .form-field,
    .auth-submit,
    .divider,
    .create-account-btn,
    .new-to-hs {
      animation: none !important;
    }

    .form-input:focus {
      transform: none;
    }
  }

  /* ---- Spinner ---- */
  .spinner {
    display: inline-block;
    width: 16px;
    height: 16px;
    border: 2px solid currentColor;
    border-inline-end-color: transparent;
    border-radius: var(--radius-full);
    animation: spin 0.6s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }
</style>
