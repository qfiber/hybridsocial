<script lang="ts">
  import { page } from '$app/state';
  import { onMount } from 'svelte';
  import BrandMark from '$lib/components/ui/BrandMark.svelte';
  import { api } from '$lib/api/client.js';
  import { ApiError } from '$lib/api/client.js';
  import { instanceName } from '$lib/stores/instance.js';

  const token = $derived(page.url.searchParams.get('token') || '');

  // 'confirming' = calling the backend, 'done' = confirmed, 'error' = bad/expired token
  let status = $state<'confirming' | 'done' | 'error'>('confirming');
  let error = $state('');

  // Resend flow (shown on the error branch)
  let email = $state('');
  let resendLoading = $state(false);
  let resendSent = $state(false);

  onMount(confirm);

  async function confirm() {
    if (!token) {
      status = 'error';
      error = 'This confirmation link is missing its token. Please use the link from your email exactly as sent.';
      return;
    }

    status = 'confirming';
    error = '';

    try {
      await api.post('/api/v1/auth/confirm', { token });
      status = 'done';
    } catch (err) {
      status = 'error';
      if (err instanceof ApiError && err.body.error === 'auth.invalid_confirmation_token') {
        error = 'This confirmation link is invalid or has already been used. If your account is not yet active, request a new link below.';
      } else if (err instanceof ApiError) {
        error = err.body.error_description || err.body.error || 'We could not confirm your account.';
      } else {
        error = 'An unexpected error occurred. Please try again.';
      }
    }
  }

  async function handleResend(e: SubmitEvent) {
    e.preventDefault();
    resendLoading = true;
    try {
      await api.post('/api/v1/auth/resend_confirmation', { email });
      resendSent = true;
    } catch {
      // Endpoint is intentionally non-committal; treat any response as sent.
      resendSent = true;
    } finally {
      resendLoading = false;
    }
  }
</script>

<svelte:head>
  <title>Confirm your account - {$instanceName}</title>
</svelte:head>

<div class="auth-card">
  {#if status === 'confirming'}
    <div class="auth-logo">
      <BrandMark size={40} />
    </div>
    <h1 class="auth-title" style="text-align: center;">Confirming your account</h1>
    <p class="auth-subtitle" style="text-align: center;">
      <span class="auth-spinner auth-spinner-dark" aria-hidden="true"></span>
      Just a moment while we verify your email.
    </p>
  {:else if status === 'done'}
    <div class="auth-success-icon" aria-hidden="true">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
        <polyline points="22 4 12 14.01 9 11.01" />
      </svg>
    </div>
    <h1 class="auth-title" style="text-align: center;">Email confirmed</h1>
    <p class="auth-subtitle" style="text-align: center;">
      Your account is now active. You can log in and get started.
    </p>
    <a href="/login" class="auth-submit" style="text-decoration: none; text-align: center;">
      Continue to login
    </a>
  {:else}
    <div class="auth-logo">
      <BrandMark size={40} />
    </div>
    <h1 class="auth-title">Confirmation failed</h1>
    <p class="auth-subtitle">We couldn't confirm your account with this link.</p>

    <div class="auth-error" role="alert">
      <span class="auth-error-icon" aria-hidden="true">!</span>
      {error}
    </div>

    {#if resendSent}
      <div class="auth-success" role="status">
        If your account still needs confirming, we've sent a fresh link. Check your inbox.
      </div>
    {:else}
      <form onsubmit={handleResend} novalidate>
        <div class="auth-field">
          <label for="resend-email" class="auth-label">EMAIL</label>
          <input
            id="resend-email"
            type="email"
            class="auth-input"
            placeholder="you@example.com"
            bind:value={email}
            required
            disabled={resendLoading}
            autocomplete="email"
          />
        </div>
        <button type="submit" class="auth-submit" disabled={resendLoading || !email}>
          {#if resendLoading}
            <span class="auth-spinner" aria-hidden="true"></span>
            Sending...
          {:else}
            Send a new confirmation link
          {/if}
        </button>
      </form>
    {/if}

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
    font-family: 'Manrope', var(--font-sans);
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

  /* ---- Spinner ---- */
  .auth-spinner {
    display: inline-block;
    width: 16px;
    height: 16px;
    border: 2px solid currentColor;
    border-inline-end-color: transparent;
    border-radius: 50%;
    animation: spin 0.6s linear infinite;
    vertical-align: middle;
    margin-inline-end: 6px;
  }

  .auth-spinner-dark {
    color: var(--color-primary);
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  /* ---- Entrance animation ---- */
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
