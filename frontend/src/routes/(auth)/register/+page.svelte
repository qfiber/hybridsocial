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
  <div class="auth-card">
    <div class="auth-success-icon" aria-hidden="true">
      <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
        <polyline points="22 4 12 14.01 9 11.01"/>
      </svg>
    </div>
    <h1 class="auth-title" style="text-align: center;">Check your email</h1>
    <p class="auth-subtitle" style="text-align: center;">
      We sent a confirmation link to <strong>{email}</strong>.
      Please check your inbox and click the link to activate your account.
    </p>
    <p class="auth-footer">
      <a href="/login" class="auth-footer-link">Back to login</a>
    </p>
  </div>
{:else}
  <div class="auth-card">
    <div class="auth-logo">
      <svg width="40" height="40" viewBox="0 0 28 28" fill="none" aria-hidden="true">
        <rect rx="6" width="28" height="28" fill="var(--color-primary)" />
        <text x="14" y="19.5" text-anchor="middle" fill="white" font-size="15" font-weight="700">H</text>
      </svg>
    </div>

    <h1 class="auth-title">Create your account</h1>
    <p class="auth-subtitle">Join the conversation</p>

    {#if error}
      <div class="auth-error" role="alert">
        <span class="auth-error-icon" aria-hidden="true">!</span>
        {error}
      </div>
    {/if}

    <form onsubmit={handleSubmit} novalidate>
      <div class="auth-field">
        <label for="handle" class="auth-label">HANDLE</label>
        <div class="auth-handle-wrap">
          <span class="auth-handle-prefix" aria-hidden="true">@</span>
          <input
            id="handle"
            type="text"
            class="auth-input auth-handle-input"
            class:auth-input-error={!!fieldErrors.handle}
            placeholder="yourname"
            bind:value={handle}
            required
            disabled={loading}
            autocomplete="username"
            pattern="[a-zA-Z0-9_]+"
          />
        </div>
        {#if fieldErrors.handle}
          <p class="auth-field-error" role="alert">{fieldErrors.handle}</p>
        {/if}
      </div>

      <div class="auth-field">
        <label for="reg-email" class="auth-label">EMAIL</label>
        <input
          id="reg-email"
          type="email"
          class="auth-input"
          class:auth-input-error={!!fieldErrors.email}
          placeholder="you@example.com"
          bind:value={email}
          required
          disabled={loading}
          autocomplete="email"
        />
        {#if fieldErrors.email}
          <p class="auth-field-error" role="alert">{fieldErrors.email}</p>
        {/if}
      </div>

      <div class="auth-field">
        <label for="reg-password" class="auth-label">PASSWORD</label>
        <input
          id="reg-password"
          type="password"
          class="auth-input"
          class:auth-input-error={!!fieldErrors.password}
          placeholder="At least 16 characters"
          bind:value={password}
          required
          minlength={16}
          disabled={loading}
          autocomplete="new-password"
        />
        {#if fieldErrors.password}
          <p class="auth-field-error" role="alert">{fieldErrors.password}</p>
        {/if}
      </div>

      <div class="auth-field">
        <label for="reg-password-confirm" class="auth-label">CONFIRM PASSWORD</label>
        <input
          id="reg-password-confirm"
          type="password"
          class="auth-input"
          class:auth-input-error={passwordMismatch}
          placeholder="Repeat your password"
          bind:value={passwordConfirm}
          required
          disabled={loading}
          autocomplete="new-password"
        />
        {#if passwordMismatch}
          <p class="auth-field-error" role="alert">Passwords do not match</p>
        {/if}
      </div>

      {#if turnstileEnabled}
        <div class="auth-field">
          <div bind:this={turnstileContainer}></div>
        </div>
      {/if}

      <div class="auth-field auth-checkbox-field">
        <label class="auth-checkbox-label">
          <input
            type="checkbox"
            bind:checked={agreedToTerms}
            disabled={loading}
            class="auth-checkbox"
          />
          <span class="auth-checkbox-text">
            I agree to the <a href="/terms" target="_blank" rel="noopener" class="auth-link">Terms of Service</a>
            and <a href="/privacy" target="_blank" rel="noopener" class="auth-link">Privacy Policy</a>
          </span>
        </label>
      </div>

      {#if powSolving}
        <p class="auth-pow-status">
          <span class="auth-spinner-small" aria-hidden="true"></span>
          Solving challenge...
        </p>
      {/if}

      <button type="submit" class="auth-submit" disabled={loading || !formValid}>
        {#if loading}
          <span class="auth-spinner" aria-hidden="true"></span>
          Creating account...
        {:else}
          Create account
        {/if}
      </button>
    </form>

    <p class="auth-footer">
      Already have an account? <a href="/login" class="auth-footer-link">Log in</a>
    </p>
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
    margin-block-end: 4px;
  }

  .auth-subtitle {
    font-size: 0.875rem;
    color: #6b7280;
    margin-block-end: 24px;
  }

  .auth-success-icon {
    display: flex;
    justify-content: center;
    margin-block-end: 16px;
    color: #16a34a;
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

  .auth-input-error {
    box-shadow: 0 0 0 2px #fca5a5;
  }

  /* ---- Handle ---- */
  .auth-handle-wrap {
    position: relative;
    display: flex;
    align-items: center;
  }

  .auth-handle-prefix {
    position: absolute;
    inset-inline-start: 16px;
    color: #9ca3af;
    font-size: 0.875rem;
    pointer-events: none;
  }

  .auth-handle-input {
    padding-inline-start: 32px;
  }

  .auth-field-error {
    font-size: 0.75rem;
    color: #dc2626;
    margin-block-start: 4px;
    margin-inline-start: 4px;
  }

  /* ---- Checkbox ---- */
  .auth-checkbox-field {
    margin-block-start: 20px;
  }

  .auth-checkbox-label {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    cursor: pointer;
  }

  .auth-checkbox {
    margin-block-start: 2px;
    accent-color: var(--color-primary);
    flex-shrink: 0;
    width: 16px;
    height: 16px;
  }

  .auth-checkbox-text {
    font-size: 0.8125rem;
    color: #6b7280;
    line-height: 1.5;
  }

  .auth-link {
    color: var(--color-primary);
    text-decoration: none;
    font-weight: 500;
  }

  .auth-link:hover {
    opacity: 0.8;
  }

  /* ---- PoW ---- */
  .auth-pow-status {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 0.75rem;
    color: #6b7280;
    margin-block-end: 12px;
  }

  .auth-spinner-small {
    display: inline-block;
    width: 12px;
    height: 12px;
    border: 2px solid #9ca3af;
    border-inline-end-color: transparent;
    border-radius: 50%;
    animation: spin 0.6s linear infinite;
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

  /* ---- Footer ---- */
  .auth-footer {
    text-align: center;
    margin-block-start: 24px;
    font-size: 0.875rem;
    color: #6b7280;
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
