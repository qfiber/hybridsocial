<script lang="ts">
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';
  import { api, ApiError } from '$lib/api/client.js';
  import { setUser, currentUser } from '$lib/stores/auth.js';
  import { getCurrentUser } from '$lib/api/auth.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import { subscribeToPush } from '$lib/utils/push.js';
  import { tError } from '$lib/utils/i18n.js';
  import { solvePow, type PowChallenge, type PowSolution } from '$lib/utils/pow.js';
  import { instanceName } from '$lib/stores/instance.js';
  import BrandMark from '$lib/components/ui/BrandMark.svelte';
  import Captcha from '$lib/components/auth/Captcha.svelte';

  let email = $state('');
  let password = $state('');
  let showPassword = $state(false);
  let otpCode = $state('');
  let error = $state('');

  // Email-confirmation gate: shown when login returns auth.email_not_confirmed.
  let emailUnconfirmed = $state(false);
  let unconfirmedEmail = $state('');
  let contactEmail = $state('');
  let resending = $state(false);
  let resendMsg = $state('');
  let loading = $state(false);
  let passkeyLoading = $state(false);
  let passkeyMode = $state(false);
  let passkeyEmail = $state('');
  let passkeyStep = $state<'email' | 'key'>('email');
  let passkeyError = $state('');
  let otpRequired = $state(false);
  let otpIdentityId = $state('');
  let otpCountdown = $state(60);
  let otpExpired = $state(false);

  // Anti-abuse gates on the credential step (blunts credential stuffing /
  // brute force). Not applied to the 2FA step — that first login already
  // passed them.
  let powSolution = $state<PowSolution | null>(null);
  let powSolving = $state(false);
  let captchaProvider = $state('none');
  let captchaSiteKey = $state('');
  let captchaToken = $state('');
  let captcha: { getToken: () => Promise<string>; reset: () => void } | undefined = $state();
  let captchaWidget = $derived(
    captchaProvider === 'turnstile' || captchaProvider === 'hcaptcha'
  );

  // Where to land after a successful login. Set by flows that interrupt the
  // user mid-task — currently the OAuth consent screen at /authorize.
  let nextPath = $state('/home');

  // Only same-origin paths: an absolute URL (or a protocol-relative "//host")
  // would turn login into an open redirect.
  function safeNext(value: string | null): string {
    if (!value) return '/home';
    if (!value.startsWith('/') || value.startsWith('//') || value.startsWith('/\\')) return '/home';
    return value;
  }

  onMount(() => {
    // Pre-fill the identifier when arriving from the account switcher's
    // "switch to @handle" / "add account" links (?handle=...).
    try {
      const params = new URL(window.location.href).searchParams;
      const h = params.get('handle');
      if (h) email = h;
      nextPath = safeNext(params.get('next'));
    } catch {
      /* ignore */
    }
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
      const info = await api.get<{
        captcha_provider?: string;
        captcha_site_key?: string;
        contact_email?: string;
      }>('/api/v1/instance/info');
      if (info.captcha_provider && info.captcha_provider !== 'none' && info.captcha_site_key) {
        captchaProvider = info.captcha_provider;
        captchaSiteKey = info.captcha_site_key;
      }
      contactEmail = info.contact_email || '';
    } catch {
      /* treat as disabled */
    }
  }
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

        if (result.access_token) {
          if (countdownInterval) clearInterval(countdownInterval);
          // Cookies set by response — just fetch user and redirect
          try {
            const user = await getCurrentUser();
            setUser(user);
          } catch {}
          subscribeToPush();
          await goto(nextPath);
        }
      } else {
        const body: Record<string, unknown> = { email, password };
        if (powSolution) {
          body.pow_prefix = powSolution.challenge;
          body.pow_nonce = powSolution.nonce;
        }
        if (captchaProvider !== 'none' && captcha) {
          body.captcha_token = await captcha.getToken();
        }

        const result = await api.post<{
          access_token?: string;
          refresh_token?: string;
          otp_required?: boolean;
          identity_id?: string;
          expires_in?: number;
        }>('/api/v1/auth/login', body);

        if (result.otp_required) {
          otpRequired = true;
          otpIdentityId = result.identity_id || '';
          startCountdown();
          loading = false;
          return;
        }

        if (result.access_token) {
          // Cookies set by response — just fetch user and redirect
          try {
            const user = await getCurrentUser();
            setUser(user);
          } catch {}
          subscribeToPush();
          await goto(nextPath);
        }
      }
    } catch (err) {
      if (err instanceof ApiError && err.body.error === 'auth.email_not_confirmed') {
        // Swap to the confirm-your-email gate instead of a bare error.
        unconfirmedEmail = email;
        resendMsg = '';
        emailUnconfirmed = true;
      } else if (err instanceof ApiError) {
        error = err.body.error_description || tError(err.body.error);
      } else {
        error = 'An unexpected error occurred. Please try again.';
      }
      // PoW + captcha tokens are single-use; refresh them so a retry
      // (e.g. after a wrong password) isn't rejected as a stale challenge.
      if (!otpRequired) {
        fetchPow();
        captcha?.reset();
      }
    } finally {
      loading = false;
    }
  }

  async function resendConfirmation() {
    if (resending || !unconfirmedEmail) return;
    resending = true;
    resendMsg = '';
    try {
      await api.post('/api/v1/auth/resend_confirmation', { email: unconfirmedEmail });
      resendMsg = 'Sent. Check your inbox (and spam) for the activation link.';
    } catch (err) {
      if (err instanceof ApiError && err.status === 429) {
        resendMsg = "You've hit the resend limit (2 per hour). Please wait, or contact support below.";
      } else {
        resendMsg = 'Could not resend right now. Please try again shortly.';
      }
    } finally {
      resending = false;
    }
  }

  function openPasskeyMode() {
    passkeyMode = true;
    passkeyStep = 'email';
    passkeyEmail = email.trim();  // pre-fill from main form if they typed it
    passkeyError = '';
  }

  function closePasskeyMode() {
    passkeyMode = false;
    passkeyStep = 'email';
    passkeyError = '';
  }

  async function passkeyNext() {
    if (!passkeyEmail.trim()) {
      passkeyError = 'Please enter your email.';
      return;
    }
    passkeyStep = 'key';
    passkeyError = '';
    await loginWithPasskey();
  }

  async function loginWithPasskey() {
    if (!navigator.credentials) {
      passkeyError = 'WebAuthn is not supported in this browser.';
      return;
    }

    passkeyLoading = true;
    passkeyError = '';
    try {
      const options = await api.post<any>('/api/v1/auth/webauthn/login/challenge', { email: passkeyEmail.trim() });

      // 2. Ask browser to authenticate with the key
      const publicKey = {
        challenge: Uint8Array.from(atob(options.challenge.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0)),
        rpId: options.rpId,
        timeout: options.timeout,
        userVerification: (options.userVerification || 'preferred') as UserVerificationRequirement,
        allowCredentials: options.allowCredentials.map((c: any) => ({
          type: c.type as 'public-key',
          id: Uint8Array.from(atob(c.id.replace(/-/g, '+').replace(/_/g, '/')), ch => ch.charCodeAt(0)),
        })),
      };

      const assertion = await navigator.credentials.get({ publicKey }) as PublicKeyCredential;
      if (!assertion) throw new Error('No assertion returned');

      const response = assertion.response as AuthenticatorAssertionResponse;

      // 3. Verify with server and get tokens
      const result = await api.post<any>('/api/v1/auth/webauthn/login/verify', {
        email: passkeyEmail.trim(),
        credential_id: btoa(String.fromCharCode(...new Uint8Array(assertion.rawId))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, ''),
        sign_count: new DataView(response.authenticatorData.slice(33, 37)).getUint32(0),
      });

      if (result.access_token) {
        // Cookies set by response — just fetch user and redirect
        const user = await getCurrentUser();
        setUser(user);
        subscribeToPush();
        goto(nextPath);
      }
    } catch (e) {
      passkeyStep = 'email';
      if (e instanceof Error && e.name === 'NotAllowedError') {
        passkeyError = 'Authentication was cancelled or no matching key found.';
      } else {
        passkeyError = 'Authentication failed. Please check your email and try again.';
      }
    } finally {
      passkeyLoading = false;
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
  <title>Sign in - {$instanceName}</title>
</svelte:head>

<div class="auth-card">
  <div class="auth-logo">
    <BrandMark size={40} />
  </div>

  {#if emailUnconfirmed}
    <h1 class="auth-title">Confirm your email</h1>
    <p class="auth-subtitle">
      You need to activate your email before you can use {$instanceName}.
    </p>
    <p class="auth-gate-text">
      We sent a confirmation link to <strong>{unconfirmedEmail}</strong>. Open it to
      activate your account, then sign in.
    </p>

    {#if resendMsg}
      <div class="auth-gate-note" role="status">{resendMsg}</div>
    {/if}

    <button
      type="button"
      class="auth-submit"
      disabled={resending}
      onclick={resendConfirmation}
    >
      {resending ? 'Sending…' : 'Resend activation email'}
    </button>

    <p class="auth-gate-support">
      Didn't get it, or can't activate your account?
      {#if contactEmail}
        Email <a href="mailto:{contactEmail}">{contactEmail}</a> and we'll help you out.
      {:else}
        Contact the instance administrator for help.
      {/if}
    </p>

    <button
      type="button"
      class="auth-back-btn"
      onclick={() => { emailUnconfirmed = false; resendMsg = ''; }}
    >
      Back to sign in
    </button>
  {:else}
  <h1 class="auth-title">Sign in to your server</h1>
  <p class="auth-subtitle">Enter your credentials to continue</p>

  {#if $currentUser}
    <!-- Reaching /login (e.g. via "Add another account") does NOT log the
         current account out — the session is still live. Make that visible
         and give a one-tap way back so bailing out doesn't feel like a
         logout. Signing in below simply switches to the new account. -->
    <div class="active-session" role="note">
      <Avatar
        src={$currentUser.avatar_url}
        name={$currentUser.display_name || $currentUser.handle}
        size="sm"
      />
      <div class="active-session-text">
        <span class="active-session-label">Still signed in as</span>
        <span class="active-session-handle">@{$currentUser.handle}</span>
      </div>
      <button type="button" class="active-session-back" onclick={() => goto('/home')}>
        Back to app
      </button>
    </div>
  {/if}

  {#if error}
    <div class="auth-error" role="alert">
      <span class="auth-error-icon" aria-hidden="true">!</span>
      {error}
    </div>
  {/if}

  <form onsubmit={handleSubmit} novalidate>
    {#if !otpRequired}
      <div class="auth-field">
        <label class="auth-label" for="email">EMAIL OR USERNAME</label>
        <input
          id="email"
          type="text"
          class="auth-input"
          placeholder="Email or username"
          bind:value={email}
          required
          disabled={loading}
          autocomplete="username"
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
          <span class="auth-sep"> · </span>
          <a href="/recover" class="auth-link">Lost email access?</a>
        </div>
      </div>

      {#if captchaProvider !== 'none' && captchaSiteKey}
        <div class="auth-field">
          <Captcha
            bind:this={captcha}
            provider={captchaProvider}
            siteKey={captchaSiteKey}
            bind:token={captchaToken}
            action="login"
          />
        </div>
      {/if}
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
      <button
        type="submit"
        class="auth-submit"
        disabled={loading ||
          (otpRequired && otpExpired) ||
          (!otpRequired && ((captchaWidget && !captchaToken) || powSolving))}
      >
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

    <button type="button" class="auth-passkey-btn" onclick={openPasskeyMode}>
      <span class="material-symbols-outlined" style="font-size: 20px">key</span>
      Sign in with Security Key
    </button>

    <a href="/register" class="auth-alt-btn">Create account</a>
  {/if}
  {/if}
</div>

<!-- Security Key Login Modal -->
{#if passkeyMode}
  <div class="passkey-overlay" onclick={closePasskeyMode} role="presentation">
    <div class="passkey-modal" onclick={(e) => e.stopPropagation()}>
      <button type="button" class="passkey-close" onclick={closePasskeyMode} aria-label="Close">
        <span class="material-symbols-outlined">close</span>
      </button>

      <div class="passkey-icon-wrap">
        <span class="material-symbols-outlined passkey-icon">key</span>
      </div>

      {#if passkeyStep === 'email'}
        <h2 class="passkey-title">Sign in with Security Key</h2>
        <p class="passkey-desc">Enter your email, then use your security key, passkey, or biometric to sign in.</p>

        {#if passkeyError}
          <div class="passkey-error">{passkeyError}</div>
        {/if}

        <form onsubmit={(e) => { e.preventDefault(); passkeyNext(); }}>
          <input
            type="email"
            class="passkey-input"
            placeholder="Email address"
            bind:value={passkeyEmail}
            autofocus
          />
          <button type="submit" class="passkey-next-btn" disabled={!passkeyEmail.trim()}>
            Next
          </button>
        </form>
      {:else}
        <h2 class="passkey-title">Touch your security key</h2>
        <p class="passkey-desc">
          {#if passkeyLoading}
            Waiting for your security key, passkey, or biometric...
          {:else}
            Ready to authenticate.
          {/if}
        </p>

        {#if passkeyLoading}
          <div class="passkey-waiting">
            <div class="passkey-pulse"></div>
          </div>
        {/if}

        <button type="button" class="passkey-back" onclick={() => { passkeyStep = 'email'; passkeyError = ''; }}>
          <span class="material-symbols-outlined rtl-mirror" style="font-size: 16px">arrow_back</span>
          Use a different email
        </button>
      {/if}
    </div>
  </div>
{/if}

{#if !otpRequired}
  <div class="auth-info-card">
    <h3 class="auth-info-title">New to {$instanceName}?</h3>
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
    text-align: center;
    margin-block-end: 4px;
  }

  .auth-subtitle {
    font-size: 0.875rem;
    color: var(--color-text-secondary);
    text-align: center;
    margin-block-end: 24px;
  }

  /* ---- Still-signed-in banner ---- */
  .active-session {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 12px;
    margin-block-end: 20px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg, 12px);
    background: var(--color-surface-2, rgba(127, 127, 127, 0.08));
  }

  .active-session-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
    line-height: 1.2;
  }

  .active-session-label {
    font-size: 0.75rem;
    color: var(--color-text-secondary);
  }

  .active-session-handle {
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .active-session-back {
    margin-inline-start: auto;
    flex-shrink: 0;
    padding: 6px 12px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full, 999px);
    background: transparent;
    color: var(--color-text);
    font-size: 0.8125rem;
    font-weight: 500;
    cursor: pointer;
    transition: background 150ms ease, border-color 150ms ease;
  }

  .active-session-back:hover {
    background: var(--color-surface);
    border-color: var(--color-text-tertiary);
  }

  /* ---- Error ---- */
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

  .auth-hint {
    font-size: 0.75rem;
    color: var(--color-text-tertiary);
    margin-block-end: 8px;
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
    color: var(--color-text-tertiary);
    cursor: pointer;
    transition: color 0.15s ease;
  }

  .auth-password-toggle:hover {
    color: var(--color-text-secondary);
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
    color: var(--color-text-secondary);
    background: var(--color-surface-container-high);
    padding: 4px 10px;
    border-radius: 8px;
  }

  .auth-otp-timer-warning {
    color: var(--color-danger);
    background: var(--color-danger-soft);
  }

  .auth-otp-expired {
    text-align: center;
    padding: 32px 16px;
  }

  .auth-otp-expired-text {
    color: var(--color-danger);
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

  .auth-back-btn {
    display: block;
    width: 100%;
    margin-block-start: 12px;
    padding: 10px;
    background: transparent;
    border: none;
    border-radius: 9999px;
    color: var(--color-text-secondary);
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
    background: var(--scrim-soft);
  }

  .auth-divider span {
    font-size: 0.8125rem;
    color: var(--color-text-tertiary);
  }

  /* ---- Create account ---- */
  .auth-passkey-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    width: 100%;
    height: 46px;
    margin-block-end: 12px;
    background: var(--color-surface);
    border: 2px solid var(--color-border);
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-text);
    cursor: pointer;
    transition: border-color 150ms ease, background 150ms ease;
  }

  .auth-passkey-btn:hover:not(:disabled) {
    border-color: var(--color-primary);
    background: var(--color-primary-soft, rgba(var(--color-primary-rgb), 0.05));
  }

  .auth-passkey-btn:disabled { opacity: 0.5; cursor: not-allowed; }

  /* Passkey modal */
  .passkey-overlay {
    position: fixed; inset: 0;
    background: var(--scrim-medium); backdrop-filter: blur(4px);
    display: flex; align-items: center; justify-content: center;
    z-index: 10000; animation: fade-in 0.15s ease;
  }
  @keyframes fade-in { from { opacity: 0; } to { opacity: 1; } }

  .passkey-modal {
    background: var(--color-surface-container-lowest); border-radius: 20px; padding: 32px;
    max-width: 400px; width: 90%; position: relative;
    box-shadow: 0 20px 60px rgba(0,0,0,0.2);
    animation: modal-in 0.2s cubic-bezier(0.22,1,0.36,1);
    text-align: center;
  }
  @keyframes modal-in { from { opacity: 0; transform: scale(0.95) translateY(8px); } to { opacity: 1; transform: scale(1) translateY(0); } }

  .passkey-close {
    position: absolute; top: 16px; inset-inline-end: 16px;
    background: none; border: none; color: var(--color-text-tertiary); cursor: pointer;
    padding: 4px; border-radius: 50%;
  }
  .passkey-close:hover { color: var(--color-text-secondary); background: var(--color-surface-container); }

  .passkey-icon-wrap { margin-bottom: 16px; }
  .passkey-icon { font-size: 40px; color: var(--color-primary); }

  .passkey-title { font-size: 1.25rem; font-weight: 700; margin-bottom: 6px; }
  .passkey-desc { font-size: 0.875rem; color: var(--color-text-secondary); margin-bottom: 20px; line-height: 1.4; }

  .passkey-error {
    padding: 10px 14px; margin-bottom: 16px;
    background: var(--color-danger-soft); border-radius: 10px; color: var(--color-danger);
    font-size: 0.8125rem;
  }

  .passkey-input {
    display: block; width: 100%; height: 46px;
    padding: 0 16px; background: var(--color-surface-container-high); border: none; border-radius: 10px;
    font-size: 0.875rem; color: var(--color-text); margin-bottom: 12px;
  }
  .passkey-input:focus { outline: none; background: var(--color-surface-container-lowest); box-shadow: 0 0 0 2px rgba(var(--color-primary-rgb),0.2); }

  .passkey-next-btn {
    display: block; width: 100%; height: 46px;
    background: linear-gradient(135deg, var(--color-primary), var(--color-primary-hover, var(--color-primary)));
    color: white; border: none; border-radius: 9999px;
    font-size: 0.875rem; font-weight: 600; cursor: pointer;
  }
  .passkey-next-btn:disabled { opacity: 0.5; cursor: not-allowed; }
  .passkey-next-btn:hover:not(:disabled) { box-shadow: 0 4px 14px rgba(var(--color-primary-rgb),0.25); }

  .passkey-waiting { display: flex; justify-content: center; margin: 20px 0; }
  .passkey-pulse {
    width: 60px; height: 60px; border-radius: 50%;
    background: var(--color-primary-soft, rgba(var(--color-primary-rgb),0.1));
    animation: pulse-ring 1.5s ease-in-out infinite;
  }
  @keyframes pulse-ring {
    0% { transform: scale(0.8); opacity: 0.5; }
    50% { transform: scale(1.2); opacity: 1; }
    100% { transform: scale(0.8); opacity: 0.5; }
  }

  .passkey-back {
    display: inline-flex; align-items: center; gap: 4px;
    background: none; border: none; color: var(--color-text-secondary);
    font-size: 0.8125rem; cursor: pointer; margin-top: 16px;
  }
  .passkey-back:hover { color: var(--color-text-secondary); }

  .auth-alt-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 100%;
    height: 46px;
    border: 1.5px solid var(--scrim-soft);
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-primary);
    text-decoration: none;
    transition: background-color 0.15s ease, border-color 0.15s ease;
  }

  .auth-alt-btn:hover {
    background: var(--scrim-tint);
    border-color: var(--color-primary);
  }

  /* ---- Info card ---- */
  .auth-info-card {
    margin-block-start: 16px;
    padding: 20px 24px;
    background: var(--color-surface-container-lowest);
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
    color: var(--color-text-secondary);
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

  .auth-gate-text {
    font-size: 0.9rem;
    line-height: 1.55;
    color: var(--color-text-secondary);
    text-align: center;
    margin: 0 0 20px;
  }

  .auth-gate-note {
    font-size: 0.85rem;
    line-height: 1.5;
    color: var(--color-text);
    background: var(--color-surface-container-low, rgba(0, 0, 0, 0.04));
    border: 1px solid var(--color-border);
    border-radius: 10px;
    padding: 10px 14px;
    margin-bottom: 16px;
    text-align: center;
  }

  .auth-gate-support {
    font-size: 0.8rem;
    line-height: 1.5;
    color: var(--color-text-tertiary);
    text-align: center;
    margin: 18px 0 0;
  }

  .auth-gate-support a {
    color: var(--color-primary);
    text-decoration: none;
  }
  .auth-gate-support a:hover {
    text-decoration: underline;
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
