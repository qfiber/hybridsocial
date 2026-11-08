<script lang="ts">
  import { page } from '$app/state';
  import { onMount } from 'svelte';
  import BrandMark from '$lib/components/ui/BrandMark.svelte';
  import Captcha from '$lib/components/auth/Captcha.svelte';
  import { api } from '$lib/api/client.js';
  import { ApiError } from '$lib/api/client.js';
  import { solvePow, type PowChallenge, type PowSolution } from '$lib/utils/pow.js';
  import { instanceName } from '$lib/stores/instance.js';

  // Check if we arrived with a token (from email link)
  let tokenFromUrl = $derived(page.url.searchParams.get('token') || '');

  let email = $state('');
  let token = $state('');
  let newPassword = $state('');
  let confirmPassword = $state('');
  let error = $state('');
  let loading = $state(false);

  // Step: 'request' = enter email, 'reset' = enter token + password, 'done' = success
  let step = $state<'request' | 'reset' | 'done'>('request');
  let emailSent = $state(false);

  // Anti-abuse gates on the "send reset email" step — same PoW + captcha as
  // signup/recovery, so this endpoint can't be used to spam reset emails.
  let powSolution = $state<PowSolution | null>(null);
  let powSolving = $state(false);
  let captchaProvider = $state('none');
  let captchaSiteKey = $state('');
  let captchaToken = $state('');
  let captcha: { getToken: () => Promise<string> } | undefined = $state();
  let captchaWidget = $derived(
    captchaProvider === 'turnstile' || captchaProvider === 'hcaptcha'
  );

  onMount(() => {
    fetchPow();
    checkCaptcha();
  });

  async function fetchPow() {
    try {
      powSolving = true;
      const challenge = await api.get<PowChallenge>('/api/v1/auth/pow-challenge');
      powSolution = await solvePow(challenge);
    } catch {
      powSolution = null;
    } finally {
      powSolving = false;
    }
  }

  async function checkCaptcha() {
    try {
      const info = await api.get<{ captcha_provider?: string; captcha_site_key?: string }>(
        '/api/v1/instance/info'
      );
      if (info.captcha_provider && info.captcha_provider !== 'none' && info.captcha_site_key) {
        captchaProvider = info.captcha_provider;
        captchaSiteKey = info.captcha_site_key;
      }
    } catch {
      /* treat as disabled */
    }
  }

  // If token in URL, jump to reset step
  $effect(() => {
    if (tokenFromUrl) {
      token = tokenFromUrl;
      step = 'reset';
    }
  });

  let passwordMismatch = $derived(
    confirmPassword.length > 0 && newPassword !== confirmPassword
  );

  async function handleRequestReset(e: SubmitEvent) {
    e.preventDefault();
    error = '';
    loading = true;

    try {
      const body: Record<string, unknown> = { email };
      if (powSolution) {
        body.pow_prefix = powSolution.challenge;
        body.pow_nonce = powSolution.nonce;
      }
      if (captchaProvider !== 'none' && captcha) {
        body.captcha_token = await captcha.getToken();
      }
      await api.post('/api/v1/auth/password/reset', body);
      emailSent = true;
    } catch (err) {
      if (err instanceof ApiError) {
        error = err.body.error_description || err.body.error || 'Failed to send reset email';
      } else {
        error = 'An unexpected error occurred. Please try again.';
      }
      // PoW is single-use; refresh it so the user can retry.
      fetchPow();
    } finally {
      loading = false;
    }
  }

  async function handleResetPassword(e: SubmitEvent) {
    e.preventDefault();
    error = '';

    if (newPassword !== confirmPassword) {
      error = 'Passwords do not match';
      return;
    }

    loading = true;

    try {
      await api.post('/api/v1/auth/password/change', {
        token,
        password: newPassword,
        password_confirmation: confirmPassword,
      });
      step = 'done';
    } catch (err) {
      if (err instanceof ApiError) {
        // Map backend error codes to clear, actionable messages.
        const code = err.body.error;
        if (code === 'auth.reset_token_expired') {
          error = 'This reset link has expired. Please request a new one below.';
        } else if (code === 'auth.invalid_reset_token') {
          error = 'This reset link is invalid or has already been used.';
        } else {
          // validation.failed etc. — ApiError.message already surfaces the
          // first field-level detail (e.g. the 16-character minimum).
          error = err.message || err.body.error_description || err.body.error || 'Failed to reset password';
        }
      } else {
        error = 'An unexpected error occurred. Please try again.';
      }
    } finally {
      loading = false;
    }
  }
</script>

<svelte:head>
  <title>Reset password - {$instanceName}</title>
</svelte:head>

<div class="auth-card">
  {#if step === 'done'}
    <div class="auth-success-icon" aria-hidden="true">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
        <polyline points="22 4 12 14.01 9 11.01"/>
      </svg>
    </div>
    <h1 class="auth-title" style="text-align: center;">Password reset</h1>
    <p class="auth-subtitle" style="text-align: center;">
      Your password has been reset successfully. You can now log in with your new password.
    </p>
    <a href="/login" class="auth-submit" style="text-decoration: none; text-align: center;">
      Back to login
    </a>
  {:else if step === 'request'}
    <div class="auth-logo">
      <BrandMark size={40} />
    </div>

    <h1 class="auth-title">Reset your password</h1>
    <p class="auth-subtitle">Enter your email and we'll send you a reset link</p>

    {#if emailSent}
      <div class="auth-success" role="status">
        If an account exists with that email, we've sent a reset link. Check your inbox.
      </div>
    {/if}

    {#if error}
      <div class="auth-error" role="alert">
        <span class="auth-error-icon" aria-hidden="true">!</span>
        {error}
      </div>
    {/if}

    <form onsubmit={handleRequestReset} novalidate>
      <div class="auth-field">
        <label for="reset-email" class="auth-label">EMAIL</label>
        <input
          id="reset-email"
          type="email"
          class="auth-input"
          placeholder="you@example.com"
          bind:value={email}
          required
          disabled={loading}
          autocomplete="email"
        />
      </div>

      {#if captchaProvider !== 'none' && captchaSiteKey}
        <div class="auth-field">
          <Captcha
            bind:this={captcha}
            provider={captchaProvider}
            siteKey={captchaSiteKey}
            bind:token={captchaToken}
            action="password_reset"
          />
        </div>
      {/if}

      <button
        type="submit"
        class="auth-submit"
        disabled={loading || !email || powSolving || (captchaWidget && !captchaToken)}
      >
        {#if loading}
          <span class="auth-spinner" aria-hidden="true"></span>
          Sending...
        {:else}
          Send reset link
        {/if}
      </button>
    </form>

    <p class="auth-footer">
      Remember your password? <a href="/login" class="auth-footer-link">Log in</a>
    </p>

    {#if emailSent}
      <p class="auth-footer" style="margin-block-start: 8px;">
        Have a token? <button type="button" class="auth-inline-link" onclick={() => { step = 'reset'; }}>Enter it here</button>
      </p>
    {/if}
  {:else}
    <div class="auth-logo">
      <BrandMark size={40} />
    </div>

    <h1 class="auth-title">Set new password</h1>
    <p class="auth-subtitle">Enter your reset token and a new password</p>

    {#if error}
      <div class="auth-error" role="alert">
        <span class="auth-error-icon" aria-hidden="true">!</span>
        {error}
      </div>
    {/if}

    <form onsubmit={handleResetPassword} novalidate>
      {#if !tokenFromUrl}
        <div class="auth-field">
          <label for="reset-token" class="auth-label">RESET TOKEN</label>
          <input
            id="reset-token"
            type="text"
            class="auth-input"
            placeholder="Paste the token from your email"
            bind:value={token}
            required
            disabled={loading}
          />
        </div>
      {/if}

      <div class="auth-field">
        <label for="new-password" class="auth-label">NEW PASSWORD</label>
        <input
          id="new-password"
          type="password"
          class="auth-input"
          placeholder="At least 16 characters"
          bind:value={newPassword}
          required
          minlength={16}
          disabled={loading}
          autocomplete="new-password"
        />
      </div>

      <div class="auth-field">
        <label for="confirm-new-password" class="auth-label">CONFIRM NEW PASSWORD</label>
        <input
          id="confirm-new-password"
          type="password"
          class="auth-input"
          class:auth-input-error={passwordMismatch}
          placeholder="Repeat your new password"
          bind:value={confirmPassword}
          required
          disabled={loading}
          autocomplete="new-password"
        />
        {#if passwordMismatch}
          <p class="auth-field-error" role="alert">Passwords do not match</p>
        {/if}
      </div>

      <button
        type="submit"
        class="auth-submit"
        disabled={loading || !token || !newPassword || passwordMismatch}
      >
        {#if loading}
          <span class="auth-spinner" aria-hidden="true"></span>
          Resetting...
        {:else}
          Reset password
        {/if}
      </button>
    </form>

    <p class="auth-footer">
      <a href="/login" class="auth-footer-link">Back to login</a>
    </p>
  {/if}
</div>

<style>
  /* ---- Card ---- */
  .auth-card {
    background: var(--color-surface-container-lowest);
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
    font-family: var(--font-sans);
    font-size: 1.25rem;
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: 4px;
  }

  .auth-subtitle {
    font-size: 0.875rem;
    color: var(--color-text-secondary);
    margin-block-end: 24px;
  }

  .auth-success-icon {
    display: flex;
    justify-content: center;
    margin-block-end: 16px;
    color: var(--color-success);
  }

  /* ---- Error / Success ---- */
  .auth-error {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 12px 16px;
    margin-block-end: 16px;
    background: var(--color-danger-soft);
    border-radius: 10px;
    color: var(--color-danger);
    font-size: 0.875rem;
  }

  .auth-error-icon {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    background: var(--color-danger);
    color: white;
    font-size: 0.75rem;
    font-weight: 700;
    flex-shrink: 0;
  }

  .auth-success {
    padding: 12px 16px;
    margin-block-end: 16px;
    background: var(--color-success-soft);
    border-radius: 10px;
    color: var(--color-success);
    font-size: 0.875rem;
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
    color: var(--color-text-secondary);
    margin-block-end: 6px;
    margin-inline-start: 4px;
  }

  .auth-input {
    display: block;
    width: 100%;
    height: 46px;
    padding: 0 16px;
    background: var(--color-surface-container-high);
    border: none;
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    transition: background-color 0.2s ease, box-shadow 0.2s ease;
  }

  .auth-input::placeholder {
    color: var(--color-text-tertiary);
  }

  .auth-input:focus {
    outline: none;
    background: var(--color-surface-container-lowest);
    box-shadow: 0 0 0 2px rgba(var(--color-primary-rgb), 0.2);
  }

  .auth-input:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .auth-input-error {
    box-shadow: 0 0 0 2px #fca5a5;
  }

  .auth-field-error {
    font-size: 0.75rem;
    color: var(--color-danger);
    margin-block-start: 4px;
    margin-inline-start: 4px;
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
    box-shadow: 0 4px 14px rgba(var(--color-primary-rgb), 0.25);
    transition: box-shadow 0.15s ease, transform 0.1s ease, opacity 0.15s ease;
  }

  .auth-submit:hover:not(:disabled) {
    box-shadow: 0 6px 20px rgba(var(--color-primary-rgb), 0.35);
  }

  .auth-submit:active:not(:disabled) {
    transform: scale(0.985);
  }

  .auth-submit:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  /* ---- Footer ---- */
  .auth-footer {
    text-align: center;
    margin-block-start: 24px;
    font-size: 0.875rem;
    color: var(--color-text-secondary);
  }

  .auth-footer-link {
    color: var(--color-primary);
    text-decoration: none;
    font-weight: 500;
  }

  .auth-footer-link:hover {
    opacity: 0.8;
  }

  .auth-inline-link {
    background: none;
    border: none;
    color: var(--color-primary);
    font-size: inherit;
    cursor: pointer;
    padding: 0;
    font-weight: 500;
    text-decoration: underline;
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

  .auth-card {
    animation: fadeUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) 0.1s both;
    transition: box-shadow 0.3s ease;
  }

  .auth-card:focus-within {
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.04), 0 8px 32px rgba(0, 0, 0, 0.08);
  }

  @media (prefers-reduced-motion: reduce) {
    .auth-card {
      animation: none !important;
    }
  }
</style>
