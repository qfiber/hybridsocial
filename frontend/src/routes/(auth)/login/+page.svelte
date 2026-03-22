<script lang="ts">
  import { goto } from '$app/navigation';
  import { api, ApiError } from '$lib/api/client.js';
  import { setTokens, setUser } from '$lib/stores/auth.js';
  import { getCurrentUser } from '$lib/api/auth.js';
  import { subscribeToPush } from '$lib/utils/push.js';

  let email = $state('');
  let password = $state('');
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
        // 2FA login — use the separate endpoint
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
        // Normal login
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
        error = err.body.error_description || err.body.error || 'Login failed';
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
  <title>Log in - HybridSocial</title>
</svelte:head>

<div>
  <h1 class="auth-title">Welcome back</h1>
  <p class="auth-subtitle">Log in to your account</p>

  {#if error}
    <div class="auth-error" role="alert">
      <span class="auth-error-icon" aria-hidden="true">!</span>
      {error}
    </div>
  {/if}

  <form onsubmit={handleSubmit} novalidate>
    {#if !otpRequired}
      <div class="form-field">
        <label for="email" class="form-label">Email</label>
        <input
          id="email"
          type="email"
          class="form-input"
          placeholder="you@example.com"
          bind:value={email}
          required
          disabled={loading}
          autocomplete="email"
        />
      </div>

      <div class="form-field">
        <div class="form-label-row">
          <label for="password" class="form-label">Password</label>
          <a href="/reset-password" class="form-link">Forgot password?</a>
        </div>
        <input
          id="password"
          type="password"
          class="form-input"
          placeholder="Your password"
          bind:value={password}
          required
          disabled={loading}
          autocomplete="current-password"
          onkeydown={handleKeydown}
        />
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
          Logging in...
        {:else if otpRequired}
          Verify
        {:else}
          Log in
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
      Back to login
    </button>
  {/if}

  <p class="auth-footer">
    Don't have an account? <a href="/register">Create account</a>
  </p>
</div>

<style>
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

  .auth-title {
    font-size: var(--text-xl);
    font-weight: var(--font-bold);
    color: var(--color-text);
    margin-block-end: var(--space-1);
  }

  .auth-subtitle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-6);
  }

  .auth-error {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-3);
    margin-block-end: var(--space-4);
    background: var(--color-danger-light);
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
    font-weight: var(--font-bold);
    flex-shrink: 0;
  }

  .form-field {
    margin-block-end: var(--space-4);
  }

  .form-label {
    display: block;
    font-size: var(--text-sm);
    font-weight: var(--font-medium);
    color: var(--color-text);
    margin-block-end: var(--space-1);
  }

  .form-label-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-block-end: var(--space-1);
  }

  .form-link {
    font-size: var(--text-sm);
    color: var(--color-primary);
  }

  .form-hint {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-2);
  }

  .form-input {
    display: block;
    width: 100%;
    height: 40px;
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
    box-shadow: 0 0 0 3px var(--color-primary-light);
  }

  .form-input:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .otp-input {
    text-align: center;
    letter-spacing: 0.5em;
    font-size: var(--text-lg);
    font-weight: var(--font-semibold);
  }

  .auth-submit {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    width: 100%;
    height: 44px;
    margin-block-start: var(--space-6);
    padding: var(--space-2) var(--space-4);
    background: var(--color-primary);
    color: var(--color-text-inverse);
    border: none;
    border-radius: var(--radius-lg);
    font-size: var(--text-sm);
    font-weight: var(--font-semibold);
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

  .auth-footer {
    text-align: center;
    margin-block-start: var(--space-6);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

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
