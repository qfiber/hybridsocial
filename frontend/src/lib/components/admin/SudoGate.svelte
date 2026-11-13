<script lang="ts">
  import { api, ApiError } from '$lib/api/client.js';
  import { currentUser } from '$lib/stores/auth.js';
  import { tError } from '$lib/utils/i18n.js';

  interface Props {
    onUnlocked: (expiresAt: string) => void;
  }

  let { onUnlocked }: Props = $props();

  let password = $state('');
  let otpCode = $state('');
  let showPassword = $state(false);
  let loading = $state(false);
  let error = $state('');
  let user = $derived($currentUser);

  // Mirror the backend gate: either a TOTP authenticator OR a security
  // key satisfies the second factor. If both are enabled the user
  // gets the security-key path by default and a "use code instead"
  // toggle, since touching a key is faster than typing a code.
  let hasKey = $derived((user as { security_keys_enabled?: boolean } | null)?.security_keys_enabled === true);
  let hasOtp = $derived(user?.two_factor_enabled === true);
  let useKey = $state(false);

  // Re-resolve `useKey` whenever the user's factor mix changes.
  $effect(() => {
    if (hasKey && !hasOtp) useKey = true;
    else if (!hasKey && hasOtp) useKey = false;
    else if (hasKey && hasOtp) useKey = true;
  });

  function decodeBase64Url(s: string): Uint8Array {
    const pad = '='.repeat((4 - (s.length % 4)) % 4);
    const b64 = (s + pad).replace(/-/g, '+').replace(/_/g, '/');
    return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  }

  function encodeBase64Url(bytes: ArrayBuffer): string {
    return btoa(String.fromCharCode(...new Uint8Array(bytes)))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '');
  }

  async function handleTotpSubmit(e: SubmitEvent) {
    e.preventDefault();
    if (loading) return;
    error = '';
    loading = true;

    try {
      const res = await api.post<{ status: string; expires_at: string }>(
        '/api/v1/admin/sudo',
        { password, code: otpCode },
      );
      password = '';
      otpCode = '';
      onUnlocked(res.expires_at);
    } catch (err) {
      error = err instanceof ApiError
        ? err.body.error_description || tError(err.body.error)
        : 'An unexpected error occurred. Please try again.';
    } finally {
      loading = false;
    }
  }

  async function handleKeySubmit(e: SubmitEvent) {
    e.preventDefault();
    if (loading) return;
    error = '';

    if (!navigator.credentials) {
      error = 'Security keys are not supported in this browser.';
      return;
    }

    loading = true;
    try {
      const opts = await api.get<{
        challenge: string;
        rpId: string;
        timeout: number;
        userVerification: string;
        allowCredentials: { type: string; id: string }[];
      }>('/api/v1/admin/sudo/webauthn_challenge');

      // Loose typing here matches the existing login passkey flow —
      // strict PublicKeyCredentialRequestOptions clashes with the
      // ArrayBufferLike Uint8Array overload Svelte's tsconfig pulls in.
      const publicKey = {
        challenge: decodeBase64Url(opts.challenge),
        rpId: opts.rpId,
        timeout: opts.timeout,
        userVerification: (opts.userVerification || 'preferred') as UserVerificationRequirement,
        allowCredentials: (opts.allowCredentials || []).map((c) => ({
          type: c.type as 'public-key',
          id: decodeBase64Url(c.id),
        })),
      };

      const assertion = (await navigator.credentials.get({ publicKey } as CredentialRequestOptions)) as PublicKeyCredential | null;
      if (!assertion) throw new Error('No assertion returned');
      const r = assertion.response as AuthenticatorAssertionResponse;

      const res = await api.post<{ status: string; expires_at: string }>('/api/v1/admin/sudo', {
        password,
        webauthn: {
          credential_id: encodeBase64Url(assertion.rawId),
          client_data_json: encodeBase64Url(r.clientDataJSON),
          authenticator_data: encodeBase64Url(r.authenticatorData),
          signature: encodeBase64Url(r.signature),
        },
      });

      password = '';
      onUnlocked(res.expires_at);
    } catch (err) {
      if (err instanceof ApiError) {
        error = err.body.error_description || tError(err.body.error);
      } else if (err instanceof Error && err.name === 'NotAllowedError') {
        error = 'Security key tap was cancelled or timed out.';
      } else {
        error = 'Security key authentication failed. Try again or use your authenticator code.';
      }
    } finally {
      loading = false;
    }
  }
</script>

<div class="sudo-gate" role="dialog" aria-labelledby="sudo-title">
  <div class="sudo-card">
    <div class="sudo-icon" aria-hidden="true">
      <svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">
        <rect x="3" y="11" width="18" height="11" rx="2" />
        <path d="M7 11V7a5 5 0 0 1 10 0v4" />
      </svg>
    </div>

    <h2 id="sudo-title" class="sudo-title">Confirm it's you</h2>
    <p class="sudo-text">
      Admin access requires a fresh password and a second factor. This
      stays unlocked for 15 minutes of activity.
    </p>

    {#if user?.handle}
      <div class="sudo-user" aria-label="Signed in as">
        <span class="sudo-user-label">Signed in as</span>
        <span class="sudo-user-handle">@{user.handle}</span>
      </div>
    {/if}

    {#if error}
      <div class="sudo-error" role="alert">
        <span class="sudo-error-icon" aria-hidden="true">!</span>
        {error}
      </div>
    {/if}

    <form onsubmit={useKey ? handleKeySubmit : handleTotpSubmit} novalidate>
      <div class="sudo-field">
        <label for="sudo-password" class="sudo-label">PASSWORD</label>
        <div class="sudo-input-wrap">
          <input
            id="sudo-password"
            type={showPassword ? 'text' : 'password'}
            class="sudo-input"
            bind:value={password}
            required
            disabled={loading}
            autocomplete="current-password"
          />
          <button
            type="button"
            class="sudo-password-toggle"
            onclick={() => (showPassword = !showPassword)}
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

      {#if !useKey}
        <div class="sudo-field">
          <label for="sudo-otp" class="sudo-label">TWO-FACTOR CODE</label>
          <p class="sudo-hint">Code from your authenticator app</p>
          <input
            id="sudo-otp"
            type="text"
            inputmode="numeric"
            pattern="[0-9]*"
            maxlength={6}
            class="sudo-input sudo-otp-input"
            placeholder="000000"
            bind:value={otpCode}
            required
            disabled={loading}
            autocomplete="one-time-code"
          />
        </div>
      {:else}
        <div class="sudo-field">
          <span class="sudo-label">SECURITY KEY</span>
          <p class="sudo-hint">
            Tap or insert your registered key when prompted by the browser.
          </p>
        </div>
      {/if}

      <button type="submit" class="sudo-submit" disabled={loading}>
        {#if loading}
          <span class="sudo-spinner" aria-hidden="true"></span>
          Unlocking...
        {:else if useKey}
          Use security key
        {:else}
          Unlock admin panel
        {/if}
      </button>
    </form>

    {#if hasKey && hasOtp}
      <button
        type="button"
        class="sudo-toggle"
        onclick={() => { useKey = !useKey; error = ''; }}
        disabled={loading}
      >
        {useKey ? 'Use authenticator code instead' : 'Use security key instead'}
      </button>
    {/if}
  </div>
</div>

<style>
  .sudo-gate {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: calc(100vh - var(--space-12));
    padding: var(--space-4);
  }

  .sudo-card {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-8);
    max-width: 460px;
    width: 100%;
    box-shadow: var(--shadow-md);
  }

  .sudo-icon {
    margin-block-end: var(--space-4);
    display: flex;
    justify-content: center;
  }

  .sudo-title {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-2);
    text-align: center;
  }

  .sudo-text {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.6;
    margin-block-end: var(--space-5);
    text-align: center;
  }

  .sudo-user {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    padding: var(--space-3) var(--space-4);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    margin-block-end: var(--space-5);
  }

  .sudo-user-label {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .sudo-user-handle {
    font-size: var(--text-sm);
    color: var(--color-text);
    font-weight: 600;
  }

  .sudo-error {
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

  .sudo-error-icon {
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

  .sudo-field {
    margin-block-end: var(--space-4);
  }

  .sudo-label {
    display: block;
    font-size: var(--text-xs);
    font-weight: 700;
    color: var(--color-text-secondary);
    letter-spacing: 0.06em;
    margin-block-end: var(--space-2);
  }

  .sudo-hint {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-end: var(--space-2);
  }

  .sudo-input-wrap {
    position: relative;
  }

  .sudo-input {
    width: 100%;
    box-sizing: border-box;
    padding: 12px 14px;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-base);
    color: var(--color-text);
  }

  .sudo-input:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px rgba(var(--color-primary-rgb), 0.15);
  }

  .sudo-otp-input {
    font-variant-numeric: tabular-nums;
    letter-spacing: 0.3em;
    text-align: center;
    font-size: var(--text-lg);
  }

  .sudo-password-toggle {
    position: absolute;
    right: 8px;
    top: 50%;
    transform: translateY(-50%);
    padding: 6px;
    background: transparent;
    border: 0;
    cursor: pointer;
    color: var(--color-text-tertiary);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: var(--radius-sm);
  }

  .sudo-password-toggle:hover {
    color: var(--color-text);
  }

  .sudo-submit {
    width: 100%;
    padding: 12px 16px;
    background: var(--color-primary);
    color: var(--color-text-on-primary);
    border: 0;
    border-radius: var(--radius-md);
    font-size: var(--text-base);
    font-weight: 600;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    margin-block-start: var(--space-2);
  }

  .sudo-submit:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .sudo-submit:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .sudo-spinner {
    width: 14px;
    height: 14px;
    border: 2px solid currentColor;
    border-top-color: transparent;
    border-radius: 50%;
    animation: sudo-spin 0.6s linear infinite;
  }

  @keyframes sudo-spin {
    to { transform: rotate(360deg); }
  }

  .sudo-toggle {
    display: block;
    margin: var(--space-3) auto 0;
    background: transparent;
    border: 0;
    padding: 6px 8px;
    color: var(--color-primary);
    font-size: var(--text-xs);
    font-weight: 600;
    cursor: pointer;
  }

  .sudo-toggle:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .sudo-toggle:hover:not(:disabled) {
    text-decoration: underline;
  }
</style>
