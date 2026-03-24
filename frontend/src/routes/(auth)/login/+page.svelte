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

<div class="auth-card">
  <div class="auth-logo">
    <svg width="40" height="40" viewBox="0 0 28 28" fill="none" aria-hidden="true">
      <rect rx="6" width="28" height="28" fill="var(--color-primary)" />
      <text x="14" y="19.5" text-anchor="middle" fill="white" font-size="15" font-weight="700">H</text>
    </svg>
  </div>

  <h1 class="auth-title">Sign in to your server</h1>
  <p class="auth-subtitle">Enter your credentials to continue</p>

  {#if error}
    <div class="auth-error" role="alert">
      <span class="auth-error-icon" aria-hidden="true">!</span>
      {error}
    </div>
  {/if}

  <form onsubmit={handleSubmit} novalidate>
    {#if !otpRequired}
      <div class="auth-field">
        <label class="auth-label" for="email">EMAIL</label>
        <input
          id="email"
          type="email"
          class="auth-input"
          placeholder="Email or username"
          bind:value={email}
          required
          disabled={loading}
          autocomplete="email"
        />
      </div>

      <div class="auth-field">
        <label class="auth-label" for="password">PASSWORD</label>
        <div class="auth-input-wrap">
          <input
            id="password"
            type={showPassword ? 'text' : 'password'}
            class="auth-input auth-input-password"
            placeholder="Password"
            bind:value={password}
            required
            disabled={loading}
            autocomplete="current-password"
            onkeydown={handleKeydown}
          />
          <button
            type="button"
            class="auth-password-toggle"
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
        <div class="auth-field-footer">
          <a href="/reset-password" class="auth-link">Forgot password?</a>
        </div>
      </div>
    {:else}
      {#if otpExpired}
        <div class="auth-otp-expired">
          <p class="auth-otp-expired-text">Verification expired. Please try again.</p>
        </div>
      {:else}
        <div class="auth-field">
          <div class="auth-otp-header">
            <label for="otp" class="auth-label">TWO-FACTOR CODE</label>
            <span class="auth-otp-timer" class:auth-otp-timer-warning={otpCountdown <= 10}>
              {formatCountdown(otpCountdown)}
            </span>
          </div>
          <p class="auth-hint">Enter the code from your authenticator app</p>
          <input
            id="otp"
            type="text"
            inputmode="numeric"
            pattern="[0-9]*"
            maxlength={6}
            class="auth-input auth-otp-input"
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
          <span class="auth-spinner" aria-hidden="true"></span>
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
    <div class="auth-divider">
      <span>or</span>
    </div>

    <a href="/register" class="auth-alt-btn">Create account</a>
  {/if}
</div>

{#if !otpRequired}
  <div class="auth-info-card">
    <h3 class="auth-info-title">New to HybridSocial?</h3>
    <p class="auth-info-desc">
      Create your own server in minutes or join a community run by others.
    </p>
    <a href="/register" class="auth-info-link">Create a server &rarr;</a>
    <a href="/explore" class="auth-info-link">Explore servers &rarr;</a>
  </div>
{/if}

<style>
  /* ---- Card ---- */
  .auth-card {
    background: white;
    border-radius: 14px;
    padding: 32px;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04), 0 4px 24px rgba(0, 0, 0, 0.06);
  }

  .auth-logo {
    display: flex;
    justify-content: center;
    margin-block-end: 24px;
  }

  .auth-title {
    font-family: 'Manrope', var(--font-sans);
    font-size: 1.25rem;
    font-weight: 700;
    color: var(--color-text);
    text-align: center;
    margin-block-end: 4px;
  }

  .auth-subtitle {
    font-size: 0.875rem;
    color: #6b7280;
    text-align: center;
    margin-block-end: 24px;
  }

  /* ---- Error ---- */
  .auth-error {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 12px 16px;
    margin-block-end: 16px;
    background: #fef2f2;
    border-radius: 10px;
    color: #dc2626;
    font-size: 0.875rem;
  }

  .auth-error-icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    background: #dc2626;
    color: white;
    font-size: 0.75rem;
    font-weight: 700;
    flex-shrink: 0;
  }

  /* ---- Fields ---- */
  .auth-field {
    margin-block-end: 16px;
  }

  .auth-label {
    display: block;
    font-size: 0.6875rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #6b7280;
    margin-block-end: 6px;
    margin-inline-start: 4px;
  }

  .auth-hint {
    font-size: 0.75rem;
    color: #9ca3af;
    margin-block-end: 8px;
    margin-inline-start: 4px;
  }

  .auth-input {
    display: block;
    width: 100%;
    height: 46px;
    padding: 0 16px;
    background: #e6e8e9;
    border: none;
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    transition: background-color 0.2s ease, box-shadow 0.2s ease;
  }

  .auth-input::placeholder {
    color: #9ca3af;
  }

  .auth-input:focus {
    outline: none;
    background: white;
    box-shadow: 0 0 0 2px rgba(var(--color-primary-rgb, 59, 130, 246), 0.2);
  }

  .auth-input:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .auth-input-wrap {
    position: relative;
  }

  .auth-input-password {
    padding-inline-end: 46px;
  }

  .auth-password-toggle {
    position: absolute;
    right: 0;
    top: 0;
    height: 46px;
    width: 46px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: none;
    border: none;
    color: #9ca3af;
    cursor: pointer;
    transition: color 0.15s ease;
  }

  .auth-password-toggle:hover {
    color: #6b7280;
  }

  .auth-field-footer {
    display: flex;
    justify-content: flex-end;
    margin-block-start: 8px;
  }

  .auth-link {
    font-size: 0.8125rem;
    color: var(--color-primary);
    text-decoration: none;
    font-weight: 500;
    transition: opacity 0.15s ease;
  }

  .auth-link:hover {
    opacity: 0.8;
  }

  /* ---- OTP ---- */
  .auth-otp-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-block-end: 4px;
  }

  .auth-otp-header .auth-label {
    margin-block-end: 0;
  }

  .auth-otp-timer {
    font-family: var(--font-mono, monospace);
    font-size: 0.8125rem;
    font-weight: 600;
    color: #6b7280;
    background: #e6e8e9;
    padding: 4px 10px;
    border-radius: 8px;
  }

  .auth-otp-timer-warning {
    color: #dc2626;
    background: #fef2f2;
  }

  .auth-otp-expired {
    text-align: center;
    padding: 32px 16px;
  }

  .auth-otp-expired-text {
    color: #dc2626;
    font-size: 0.875rem;
    font-weight: 500;
  }

  .auth-otp-input {
    text-align: center;
    letter-spacing: 0.5em;
    font-size: 1.125rem;
    font-weight: 600;
  }

  /* ---- Submit button ---- */
  .auth-submit {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    width: 100%;
    height: 46px;
    margin-block-start: 20px;
    padding: 0 20px;
    background: linear-gradient(135deg, var(--color-primary) 0%, var(--color-primary-hover, var(--color-primary)) 100%);
    color: white;
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    box-shadow: 0 4px 14px rgba(var(--color-primary-rgb, 59, 130, 246), 0.25);
    transition: box-shadow 0.15s ease, transform 0.1s ease, opacity 0.15s ease;
  }

  .auth-submit:hover:not(:disabled) {
    box-shadow: 0 6px 20px rgba(var(--color-primary-rgb, 59, 130, 246), 0.35);
  }

  .auth-submit:active:not(:disabled) {
    transform: scale(0.985);
  }

  .auth-submit:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .auth-back-btn {
    display: block;
    width: 100%;
    margin-block-start: 12px;
    padding: 10px;
    background: transparent;
    border: none;
    border-radius: 9999px;
    color: #6b7280;
    font-size: 0.875rem;
    cursor: pointer;
    transition: color 0.15s ease;
  }

  .auth-back-btn:hover {
    color: var(--color-text);
  }

  /* ---- Divider ---- */
  .auth-divider {
    display: flex;
    align-items: center;
    gap: 12px;
    margin: 20px 0;
  }

  .auth-divider::before,
  .auth-divider::after {
    content: '';
    flex: 1;
    height: 1px;
    background: rgba(0, 0, 0, 0.08);
  }

  .auth-divider span {
    font-size: 0.8125rem;
    color: #9ca3af;
  }

  /* ---- Create account ---- */
  .auth-alt-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 100%;
    height: 46px;
    border: 1.5px solid rgba(0, 0, 0, 0.1);
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-primary);
    text-decoration: none;
    transition: background-color 0.15s ease, border-color 0.15s ease;
  }

  .auth-alt-btn:hover {
    background: rgba(0, 0, 0, 0.02);
    border-color: var(--color-primary);
  }

  /* ---- Info card ---- */
  .auth-info-card {
    margin-block-start: 16px;
    padding: 20px 24px;
    background: white;
    border-radius: 14px;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04), 0 4px 24px rgba(0, 0, 0, 0.06);
  }

  .auth-info-title {
    font-family: 'Manrope', var(--font-sans);
    font-size: 0.875rem;
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: 4px;
  }

  .auth-info-desc {
    font-size: 0.75rem;
    color: #6b7280;
    line-height: 1.5;
    margin-block-end: 12px;
  }

  .auth-info-link {
    display: block;
    font-size: 0.875rem;
    font-weight: 500;
    color: var(--color-primary);
    text-decoration: none;
    margin-block-end: 4px;
    transition: opacity 0.15s ease;
  }

  .auth-info-link:hover {
    opacity: 0.8;
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

  .auth-logo {
    animation: scaleIn 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.1s both;
  }

  .auth-title {
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.15s both;
  }

  .auth-subtitle {
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.2s both;
  }

  .auth-field:nth-child(1) {
    animation: fadeUp 0.45s cubic-bezier(0.22, 1, 0.36, 1) 0.25s both;
  }

  .auth-field:nth-child(2) {
    animation: fadeUp 0.45s cubic-bezier(0.22, 1, 0.36, 1) 0.3s both;
  }

  .auth-submit {
    animation: fadeUp 0.45s cubic-bezier(0.22, 1, 0.36, 1) 0.35s both;
  }

  .auth-divider {
    animation: fadeUp 0.4s cubic-bezier(0.22, 1, 0.36, 1) 0.4s both;
  }

  .auth-alt-btn {
    animation: fadeUp 0.4s cubic-bezier(0.22, 1, 0.36, 1) 0.45s both;
  }

  .auth-info-card {
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.5s both;
  }

  /* Interactive effects */
  .auth-card {
    transition: box-shadow 0.3s ease;
  }

  .auth-card:focus-within {
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.04), 0 8px 32px rgba(0, 0, 0, 0.08);
  }

  @media (prefers-reduced-motion: reduce) {
    .auth-logo,
    .auth-title,
    .auth-subtitle,
    .auth-field,
    .auth-submit,
    .auth-divider,
    .auth-alt-btn,
    .auth-info-card {
      animation: none !important;
    }
  }

  /* ---- Spinner ---- */
  .auth-spinner {
    display: inline-block;
    width: 16px;
    height: 16px;
    border: 2px solid currentColor;
    border-inline-end-color: transparent;
    border-radius: 50%;
    animation: spin 0.6s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }
</style>
