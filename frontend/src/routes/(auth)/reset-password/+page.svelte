<script lang="ts">
  import { page } from '$app/state';
  import { api } from '$lib/api/client.js';
  import { ApiError } from '$lib/api/client.js';

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
      await api.post('/api/v1/auth/password/reset', { email });
      emailSent = true;
    } catch (err) {
      if (err instanceof ApiError) {
        error = err.body.error_description || err.body.error || 'Failed to send reset email';
      } else {
        error = 'An unexpected error occurred. Please try again.';
      }
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
      await api.post('/api/v1/auth/password/confirm', {
        token,
        password: newPassword,
      });
      step = 'done';
    } catch (err) {
      if (err instanceof ApiError) {
        error = err.body.error_description || err.body.error || 'Failed to reset password';
      } else {
        error = 'An unexpected error occurred. Please try again.';
      }
    } finally {
      loading = false;
    }
  }
</script>

<svelte:head>
  <title>Reset password - HybridSocial</title>
</svelte:head>

<div>
  {#if step === 'done'}
    <div class="success-icon" aria-hidden="true">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
        <polyline points="22 4 12 14.01 9 11.01"/>
      </svg>
    </div>
    <h1 class="auth-title success-title">Password reset</h1>
    <p class="auth-subtitle success-subtitle">
      Your password has been reset successfully. You can now log in with your new password.
    </p>
    <a href="/login" class="auth-submit" style="text-decoration: none; text-align: center;">
      Back to login
    </a>
  {:else if step === 'request'}
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
      <div class="form-field">
        <label for="reset-email" class="form-label">Email</label>
        <input
          id="reset-email"
          type="email"
          class="form-input"
          placeholder="you@example.com"
          bind:value={email}
          required
          disabled={loading}
          autocomplete="email"
        />
      </div>

      <button type="submit" class="auth-submit" disabled={loading || !email}>
        {#if loading}
          <span class="spinner" aria-hidden="true"></span>
          Sending...
        {:else}
          Send reset link
        {/if}
      </button>
    </form>

    <p class="auth-footer">
      Remember your password? <a href="/login">Log in</a>
    </p>

    {#if emailSent}
      <p class="auth-footer" style="margin-block-start: var(--space-2);">
        Have a token? <button type="button" class="inline-link" onclick={() => { step = 'reset'; }}>Enter it here</button>
      </p>
    {/if}
  {:else}
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
        <div class="form-field">
          <label for="reset-token" class="form-label">Reset token</label>
          <input
            id="reset-token"
            type="text"
            class="form-input"
            placeholder="Paste the token from your email"
            bind:value={token}
            required
            disabled={loading}
          />
        </div>
      {/if}

      <div class="form-field">
        <label for="new-password" class="form-label">New password</label>
        <input
          id="new-password"
          type="password"
          class="form-input"
          placeholder="At least 16 characters"
          bind:value={newPassword}
          required
          minlength={16}
          disabled={loading}
          autocomplete="new-password"
        />
      </div>

      <div class="form-field">
        <label for="confirm-new-password" class="form-label">Confirm new password</label>
        <input
          id="confirm-new-password"
          type="password"
          class="form-input"
          class:form-input-error={passwordMismatch}
          placeholder="Repeat your new password"
          bind:value={confirmPassword}
          required
          disabled={loading}
          autocomplete="new-password"
        />
        {#if passwordMismatch}
          <p class="field-error" role="alert">Passwords do not match</p>
        {/if}
      </div>

      <button
        type="submit"
        class="auth-submit"
        disabled={loading || !token || !newPassword || passwordMismatch}
      >
        {#if loading}
          <span class="spinner" aria-hidden="true"></span>
          Resetting...
        {:else}
          Reset password
        {/if}
      </button>
    </form>

    <p class="auth-footer">
      <a href="/login">Back to login</a>
    </p>
  {/if}
</div>

<style>
  .auth-title {
    font-size: var(--text-xl);
    font-weight: var(--font-bold);
    color: var(--color-text);
    margin-block-end: var(--space-1);
  }

  .success-title {
    text-align: center;
  }

  .auth-subtitle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-6);
  }

  .success-subtitle {
    text-align: center;
  }

  .success-icon {
    display: flex;
    justify-content: center;
    margin-block-end: var(--space-4);
    color: var(--color-success);
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

  .auth-success {
    padding: var(--space-3);
    margin-block-end: var(--space-4);
    background: var(--color-success-light);
    border: 1px solid var(--color-success);
    border-radius: var(--radius-md);
    color: var(--color-success);
    font-size: var(--text-sm);
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

  .form-input-error {
    border-color: var(--color-danger);
  }

  .field-error {
    font-size: var(--text-xs);
    color: var(--color-danger);
    margin-block-start: var(--space-1);
  }

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

  .auth-footer {
    text-align: center;
    margin-block-start: var(--space-6);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .inline-link {
    background: none;
    border: none;
    color: var(--color-primary);
    font-size: inherit;
    cursor: pointer;
    padding: 0;
    text-decoration: underline;
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
