<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { ApiError } from '$lib/api/client.js';
  import { solvePow, type PowChallenge, type PowSolution } from '$lib/utils/pow.js';

  let handle = $state('');
  let email = $state('');
  let password = $state('');
  let passwordConfirm = $state('');
  let agreedToTerms = $state(false);
  let error = $state('');
  let fieldErrors = $state<Record<string, string>>({});
  let loading = $state(false);
  let success = $state(false);

  // PoW challenge
  let powSolution = $state<PowSolution | null>(null);
  let powSolving = $state(false);

  // Turnstile
  let turnstileToken = $state('');
  let turnstileEnabled = $state(false);
  let turnstileContainer: HTMLDivElement | undefined = $state();

  let passwordMismatch = $derived(
    passwordConfirm.length > 0 && password !== passwordConfirm
  );

  let formValid = $derived(
    handle.length > 0 &&
    email.length > 0 &&
    password.length >= 16 &&
    password === passwordConfirm &&
    agreedToTerms &&
    !powSolving
  );

  onMount(() => {
    fetchPowChallenge();
    checkTurnstile();
  });

  async function fetchPowChallenge() {
    try {
      powSolving = true;
      const challenge = await api.get<PowChallenge>('/api/v1/auth/pow-challenge');
      powSolution = await solvePow(challenge);
    } catch {
      // PoW not required or endpoint not available yet
      powSolution = null;
    } finally {
      powSolving = false;
    }
  }

  async function checkTurnstile() {
    try {
      const info = await api.get<{ turnstile_enabled?: boolean; turnstile_site_key?: string }>(
        '/api/v1/instance/info'
      );
      if (info.turnstile_enabled && info.turnstile_site_key) {
        turnstileEnabled = true;
        loadTurnstileScript(info.turnstile_site_key);
      }
    } catch {
      // Instance info not available yet
    }
  }

  function loadTurnstileScript(siteKey: string) {
    if (typeof document === 'undefined') return;
    const script = document.createElement('script');
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onTurnstileLoad';
    script.async = true;
    (window as unknown as Record<string, unknown>).onTurnstileLoad = () => {
      if (turnstileContainer) {
        (window as unknown as Record<string, { render: (el: HTMLElement, opts: Record<string, unknown>) => void }>).turnstile.render(
          turnstileContainer,
          {
            sitekey: siteKey,
            callback: (token: string) => { turnstileToken = token; },
          }
        );
      }
    };
    document.head.appendChild(script);
  }

  async function handleSubmit(e: SubmitEvent) {
    e.preventDefault();
    error = '';
    fieldErrors = {};

    if (password !== passwordConfirm) {
      fieldErrors.password_confirm = 'Passwords do not match';
      return;
    }

    loading = true;

    try {
      const body: Record<string, unknown> = {
        handle,
        email,
        password,
      };

      if (powSolution) {
        body.pow_solution = powSolution;
      }

      if (turnstileEnabled && turnstileToken) {
        body.turnstile_token = turnstileToken;
      }

      await api.post('/api/v1/auth/register', body);
      success = true;
    } catch (err) {
      if (err instanceof ApiError) {
        error = err.body.error_description || err.body.error || 'Registration failed';
        if (err.body.details) {
          fieldErrors = {};
          for (const [field, messages] of Object.entries(err.body.details)) {
            fieldErrors[field] = messages[0];
          }
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
  <title>Create account - HybridSocial</title>
</svelte:head>

{#if success}
  <div>
    <div class="success-icon" aria-hidden="true">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
        <polyline points="22 4 12 14.01 9 11.01"/>
      </svg>
    </div>
    <h1 class="auth-title success-title">Check your email</h1>
    <p class="auth-subtitle">
      We sent a confirmation link to <strong>{email}</strong>.
      Please check your inbox and click the link to activate your account.
    </p>
    <p class="auth-footer">
      <a href="/login">Back to login</a>
    </p>
  </div>
{:else}
  <div>
    <h1 class="auth-title">Create your account</h1>
    <p class="auth-subtitle">Join the conversation</p>

    {#if error}
      <div class="auth-error" role="alert">
        <span class="auth-error-icon" aria-hidden="true">!</span>
        {error}
      </div>
    {/if}

    <form onsubmit={handleSubmit} novalidate>
      <div class="form-field">
        <label for="handle" class="form-label">Handle</label>
        <div class="handle-wrapper">
          <span class="handle-prefix" aria-hidden="true">@</span>
          <input
            id="handle"
            type="text"
            class="form-input handle-input"
            class:form-input-error={!!fieldErrors.handle}
            placeholder="yourname"
            bind:value={handle}
            required
            disabled={loading}
            autocomplete="username"
            pattern="[a-zA-Z0-9_]+"
          />
        </div>
        {#if fieldErrors.handle}
          <p class="field-error" role="alert">{fieldErrors.handle}</p>
        {/if}
      </div>

      <div class="form-field">
        <label for="reg-email" class="form-label">Email</label>
        <input
          id="reg-email"
          type="email"
          class="form-input"
          class:form-input-error={!!fieldErrors.email}
          placeholder="you@example.com"
          bind:value={email}
          required
          disabled={loading}
          autocomplete="email"
        />
        {#if fieldErrors.email}
          <p class="field-error" role="alert">{fieldErrors.email}</p>
        {/if}
      </div>

      <div class="form-field">
        <label for="reg-password" class="form-label">Password</label>
        <input
          id="reg-password"
          type="password"
          class="form-input"
          class:form-input-error={!!fieldErrors.password}
          placeholder="At least 16 characters"
          bind:value={password}
          required
          minlength={16}
          disabled={loading}
          autocomplete="new-password"
        />
        {#if fieldErrors.password}
          <p class="field-error" role="alert">{fieldErrors.password}</p>
        {/if}
      </div>

      <div class="form-field">
        <label for="reg-password-confirm" class="form-label">Confirm password</label>
        <input
          id="reg-password-confirm"
          type="password"
          class="form-input"
          class:form-input-error={passwordMismatch}
          placeholder="Repeat your password"
          bind:value={passwordConfirm}
          required
          disabled={loading}
          autocomplete="new-password"
        />
        {#if passwordMismatch}
          <p class="field-error" role="alert">Passwords do not match</p>
        {/if}
      </div>

      {#if turnstileEnabled}
        <div class="form-field">
          <div bind:this={turnstileContainer}></div>
        </div>
      {/if}

      <div class="form-field checkbox-field">
        <label class="checkbox-label">
          <input
            type="checkbox"
            bind:checked={agreedToTerms}
            disabled={loading}
            class="checkbox-input"
          />
          <span class="checkbox-text">
            I agree to the <a href="/terms" target="_blank" rel="noopener">Terms of Service</a>
            and <a href="/privacy" target="_blank" rel="noopener">Privacy Policy</a>
          </span>
        </label>
      </div>

      {#if powSolving}
        <p class="pow-status">
          <span class="spinner-small" aria-hidden="true"></span>
          Solving challenge...
        </p>
      {/if}

      <button type="submit" class="auth-submit" disabled={loading || !formValid}>
        {#if loading}
          <span class="spinner" aria-hidden="true"></span>
          Creating account...
        {:else}
          Create account
        {/if}
      </button>
    </form>

    <p class="auth-footer">
      Already have an account? <a href="/login">Log in</a>
    </p>
  </div>
{/if}

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
    text-align: start;
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

  .handle-wrapper {
    position: relative;
    display: flex;
    align-items: center;
  }

  .handle-prefix {
    position: absolute;
    inset-inline-start: var(--space-3);
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    pointer-events: none;
  }

  .handle-input {
    padding-inline-start: var(--space-6);
  }

  .field-error {
    font-size: var(--text-xs);
    color: var(--color-danger);
    margin-block-start: var(--space-1);
  }

  .checkbox-field {
    margin-block-start: var(--space-4);
  }

  .checkbox-label {
    display: flex;
    align-items: flex-start;
    gap: var(--space-2);
    cursor: pointer;
  }

  .checkbox-input {
    margin-block-start: 2px;
    accent-color: var(--color-primary);
    flex-shrink: 0;
  }

  .checkbox-text {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: var(--leading-normal);
  }

  .pow-status {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-3);
  }

  .spinner-small {
    display: inline-block;
    width: 12px;
    height: 12px;
    border: 2px solid var(--color-text-tertiary);
    border-inline-end-color: transparent;
    border-radius: var(--radius-full);
    animation: spin 0.6s linear infinite;
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
