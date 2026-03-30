<script lang="ts">
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';
  import { changePassword, setupTwoFactor, verifyTwoFactor, disableTwoFactor, getCurrentUser } from '$lib/api/auth.js';
  import type { TwoFactorSetup } from '$lib/api/types.js';
  import { authStore, setUser } from '$lib/stores/auth.js';
  import { addToast } from '$lib/stores/toast.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import QRCode from 'qrcode';

  import { api } from '$lib/api/client.js';

  // WebAuthn / Security Keys
  interface WebauthnCred { id: string; name: string; credential_id: string; sign_count: number; last_used_at: string | null; created_at: string; }
  let securityKeys = $state<WebauthnCred[]>([]);
  let keysLoading = $state(true);
  let keyName = $state('');
  let keyRegistering = $state(false);

  async function loadKeys() {
    try {
      securityKeys = await api.get<WebauthnCred[]>('/api/v1/auth/webauthn/credentials');
    } catch { /* */ }
    finally { keysLoading = false; }
  }

  async function registerKey() {
    if (!navigator.credentials) {
      addToast('WebAuthn not supported in this browser', 'error');
      return;
    }
    keyRegistering = true;
    try {
      // 1. Get challenge from server
      const options = await api.post<any>('/api/v1/auth/webauthn/register/challenge');

      // 2. Convert challenge and user.id to ArrayBuffer
      const publicKey = {
        challenge: Uint8Array.from(atob(options.challenge.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0)),
        rp: options.rp,
        user: {
          id: Uint8Array.from(atob(options.user.id.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0)),
          name: options.user.name,
          displayName: options.user.displayName,
        },
        pubKeyCredParams: options.pubKeyCredParams,
        timeout: options.timeout,
        attestation: options.attestation as AttestationConveyancePreference,
        authenticatorSelection: options.authenticatorSelection,
      };

      // 3. Create credential via browser
      const credential = await navigator.credentials.create({ publicKey }) as PublicKeyCredential;
      if (!credential) throw new Error('No credential returned');

      const response = credential.response as AuthenticatorAttestationResponse;

      // 4. Send to server
      await api.post('/api/v1/auth/webauthn/register/verify', {
        credential_id: btoa(String.fromCharCode(...new Uint8Array(credential.rawId))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, ''),
        public_key: btoa(String.fromCharCode(...new Uint8Array(response.getPublicKey?.() || new ArrayBuffer(0)))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, ''),
        name: keyName || 'Security Key',
        response: {
          attestationObject: btoa(String.fromCharCode(...new Uint8Array(response.attestationObject))),
          clientDataJSON: btoa(String.fromCharCode(...new Uint8Array(response.clientDataJSON))),
        }
      });

      keyName = '';
      addToast('Security key registered', 'success');
      await loadKeys();
    } catch (e) {
      addToast(e instanceof Error ? e.message : 'Failed to register key', 'error');
    } finally { keyRegistering = false; }
  }

  async function deleteKey(id: string) {
    try {
      await api.delete(`/api/v1/auth/webauthn/credentials/${id}`);
      securityKeys = securityKeys.filter(k => k.id !== id);
      addToast('Security key removed', 'success');
    } catch {
      addToast('Failed to remove key', 'error');
    }
  }

  // Password change
  let currentPassword = $state('');
  let newPassword = $state('');
  let confirmPassword = $state('');
  let passwordSaving = $state(false);
  let passwordSaved = $state(false);
  let passwordError: string | null = $state(null);

  // 2FA — load from user state
  let twoFactorEnabled = $state(false);

  onMount(async () => {
    const state = get(authStore);
    twoFactorEnabled = !!(state.user as any)?.two_factor_enabled;
    loadKeys();
  });

  let twoFactorSetup: TwoFactorSetup | null = $state(null);
  let verifyCode = $state('');
  let disableCode = $state('');
  let twoFALoading = $state(false);
  let twoFAError: string | null = $state(null);
  let twoFASuccess: string | null = $state(null);
  let showSetup = $state(false);
  let showDisable = $state(false);
  let qrDataUrl = $state('');

  async function handlePasswordChange() {
    passwordError = null;
    passwordSaved = false;

    if (newPassword !== confirmPassword) {
      passwordError = 'New passwords do not match';
      return;
    }

    if (newPassword.length < 16) {
      passwordError = 'Password must be at least 16 characters';
      return;
    }

    passwordSaving = true;
    try {
      await changePassword(currentPassword, newPassword);
      passwordSaved = true;
      currentPassword = '';
      newPassword = '';
      confirmPassword = '';
      setTimeout(() => { passwordSaved = false; }, 3000);
    } catch (e) {
      passwordError = e instanceof Error ? e.message : 'Failed to change password';
    } finally {
      passwordSaving = false;
    }
  }

  async function handleSetup2FA() {
    twoFAError = null;
    twoFALoading = true;
    try {
      twoFactorSetup = await setupTwoFactor();
      // Generate QR code from the otpauth URI
      if (twoFactorSetup.uri) {
        qrDataUrl = await QRCode.toDataURL(twoFactorSetup.uri, { width: 200, margin: 2 });
      }
      showSetup = true;
    } catch (e) {
      twoFAError = e instanceof Error ? e.message : 'Failed to setup 2FA';
    } finally {
      twoFALoading = false;
    }
  }

  async function handleVerify2FA() {
    twoFAError = null;
    twoFALoading = true;
    try {
      await verifyTwoFactor(verifyCode);
      twoFactorEnabled = true;
      showSetup = false;
      twoFactorSetup = null;
      verifyCode = '';
      twoFASuccess = 'Two-factor authentication enabled';
      setTimeout(() => { twoFASuccess = null; }, 3000);
      // Refresh user data so admin panel sees 2FA enabled
      try {
        const user = await getCurrentUser();
        setUser(user);
      } catch {};
    } catch (e) {
      twoFAError = e instanceof Error ? e.message : 'Invalid verification code';
    } finally {
      twoFALoading = false;
    }
  }

  async function handleDisable2FA() {
    twoFAError = null;
    twoFALoading = true;
    try {
      await disableTwoFactor(disableCode);
      twoFactorEnabled = false;
      showDisable = false;
      disableCode = '';
      twoFASuccess = 'Two-factor authentication disabled';
      setTimeout(() => { twoFASuccess = null; }, 3000);
    } catch (e) {
      twoFAError = e instanceof Error ? e.message : 'Invalid code';
    } finally {
      twoFALoading = false;
    }
  }
</script>

<div class="stitch-settings">
  <!-- Page header -->
  <div class="stitch-settings-header">
    <h1 class="stitch-settings-title">Account Settings</h1>
    <p class="stitch-settings-subtitle">Manage your profile, preferences, and account details</p>
  </div>

  <!-- Change Password -->
  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
        </svg>
      </span>
      <h2 class="stitch-section-title">Change Password</h2>
    </div>

    <div class="stitch-section-content">
      <form class="stitch-form" onsubmit={(e) => { e.preventDefault(); handlePasswordChange(); }}>
        <div class="stitch-field">
          <label class="stitch-label" for="current-password">CURRENT PASSWORD</label>
          <input
            id="current-password"
            type="password"
            class="stitch-input"
            bind:value={currentPassword}
            autocomplete="current-password"
            required
          />
        </div>

        <div class="stitch-field">
          <label class="stitch-label" for="new-password">NEW PASSWORD</label>
          <input
            id="new-password"
            type="password"
            class="stitch-input"
            bind:value={newPassword}
            autocomplete="new-password"
            minlength="16"
            placeholder="At least 16 characters"
            required
          />
        </div>

        <div class="stitch-field">
          <label class="stitch-label" for="confirm-password">CONFIRM NEW PASSWORD</label>
          <input
            id="confirm-password"
            type="password"
            class="stitch-input"
            bind:value={confirmPassword}
            autocomplete="new-password"
            required
          />
        </div>

        {#if passwordError}
          <div class="stitch-error">{passwordError}</div>
        {/if}

        {#if passwordSaved}
          <div class="stitch-success">Password changed successfully</div>
        {/if}

        <div class="stitch-actions">
          <button class="stitch-btn-primary" type="submit" disabled={passwordSaving}>
            {#if passwordSaving}
              <Spinner size={16} color="#fff" />
            {/if}
            Change Password
          </button>
        </div>
      </form>
    </div>
  </section>

  <!-- Two-Factor Authentication -->
  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
        </svg>
      </span>
      <h2 class="stitch-section-title">Two-Factor Authentication</h2>
    </div>

    <div class="stitch-section-content">
      <div class="stitch-form">
        {#if twoFASuccess}
          <div class="stitch-success">{twoFASuccess}</div>
        {/if}

        {#if twoFAError}
          <div class="stitch-error">{twoFAError}</div>
        {/if}

        {#if !twoFactorEnabled && !showSetup}
          <p class="stitch-description">
            Add an extra layer of security to your account by enabling two-factor authentication.
          </p>
          <div class="stitch-actions">
            <button class="stitch-btn-outline" type="button" onclick={handleSetup2FA} disabled={twoFALoading}>
              {#if twoFALoading}
                <Spinner size={16} />
              {/if}
              Enable 2FA
            </button>
          </div>
        {:else if showSetup && twoFactorSetup}
          <p class="stitch-description">
            Scan the QR code below with your authenticator app (like Google Authenticator or Authy), then enter the verification code.
          </p>

          <div class="stitch-qr">
            <img src={qrDataUrl} alt="2FA QR Code" class="stitch-qr-img" />
          </div>

          <div class="stitch-secret">
            <span class="stitch-label">MANUAL ENTRY KEY</span>
            <code class="stitch-secret-code">{twoFactorSetup.secret}</code>
          </div>

          {#if twoFactorSetup.backup_codes?.length > 0}
            <div class="stitch-backup">
              <span class="stitch-label">BACKUP CODES (SAVE THESE SOMEWHERE SAFE)</span>
              <div class="stitch-codes-grid">
                {#each twoFactorSetup.backup_codes as code}
                  <code class="stitch-backup-code">{code}</code>
                {/each}
              </div>
            </div>
          {/if}

          <form onsubmit={(e) => { e.preventDefault(); handleVerify2FA(); }}>
            <div class="stitch-field">
              <label class="stitch-label" for="verify-code">VERIFICATION CODE</label>
              <input
                id="verify-code"
                type="text"
                class="stitch-input"
                bind:value={verifyCode}
                placeholder="Enter 6-digit code"
                maxlength="6"
                autocomplete="one-time-code"
                required
              />
            </div>
            <div class="stitch-actions" style="margin-block-start: 16px;">
              <button class="stitch-btn-ghost" type="button" onclick={() => { showSetup = false; twoFactorSetup = null; }}>
                Cancel
              </button>
              <button class="stitch-btn-primary" type="submit" disabled={twoFALoading}>
                {#if twoFALoading}
                  <Spinner size={16} color="#fff" />
                {/if}
                Verify & Enable
              </button>
            </div>
          </form>
        {:else if twoFactorEnabled && !showDisable}
          <div class="stitch-status-row">
            <div class="stitch-status-info">
              <span class="stitch-status-label">Two-factor authentication</span>
              <span class="stitch-status-value stitch-status-enabled">Enabled</span>
            </div>
            <button class="stitch-btn-danger" type="button" onclick={() => { showDisable = true; }}>
              Disable 2FA
            </button>
          </div>
        {:else if showDisable}
          <form onsubmit={(e) => { e.preventDefault(); handleDisable2FA(); }}>
            <div class="stitch-field">
              <label class="stitch-label" for="disable-code">ENTER YOUR 2FA CODE TO DISABLE</label>
              <input
                id="disable-code"
                type="text"
                class="stitch-input"
                bind:value={disableCode}
                placeholder="Enter 6-digit code"
                maxlength="6"
                autocomplete="one-time-code"
                required
              />
            </div>
            <div class="stitch-actions" style="margin-block-start: 16px;">
              <button class="stitch-btn-ghost" type="button" onclick={() => { showDisable = false; }}>
                Cancel
              </button>
              <button class="stitch-btn-danger" type="submit" disabled={twoFALoading}>
                {#if twoFALoading}
                  <Spinner size={16} color="#fff" />
                {/if}
                Disable 2FA
              </button>
            </div>
          </form>
        {/if}
      </div>
    </div>
  </section>

  <!-- Security Keys (WebAuthn/FIDO2) -->
  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 11-7.778 7.778 5.5 5.5 0 017.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4"/>
        </svg>
      </span>
      <div>
        <h2 class="stitch-section-title">Security Keys</h2>
        <p class="stitch-section-desc">Use a hardware security key, biometric, or passkey (e.g. YubiKey, Bitwarden, Touch ID) for secure login.</p>
      </div>
    </div>
    <div class="stitch-section-content">
      {#if keysLoading}
        <div style="padding: 16px; text-align: center"><Spinner /></div>
      {:else}
        {#if securityKeys.length > 0}
          <div class="keys-list">
            {#each securityKeys as key (key.id)}
              <div class="key-item">
                <div class="key-info">
                  <span class="material-symbols-outlined key-icon">key</span>
                  <div>
                    <span class="key-name">{key.name}</span>
                    <span class="key-meta">
                      Added {new Date(key.created_at).toLocaleDateString()}
                      {#if key.last_used_at}
                         &middot; Last used {new Date(key.last_used_at).toLocaleDateString()}
                      {/if}
                      &middot; Used {key.sign_count} times
                    </span>
                  </div>
                </div>
                <button type="button" class="key-remove" onclick={() => deleteKey(key.id)}>
                  <span class="material-symbols-outlined" style="font-size: 18px">delete</span>
                </button>
              </div>
            {/each}
          </div>
        {/if}

        <div class="key-add-form">
          <input type="text" class="key-name-input" bind:value={keyName} placeholder="Key name (e.g. YubiKey, Bitwarden)" />
          <button type="button" class="key-add-btn" onclick={registerKey} disabled={keyRegistering}>
            <span class="material-symbols-outlined" style="font-size: 18px">add</span>
            {keyRegistering ? 'Waiting for key...' : 'Add Security Key'}
          </button>
        </div>
      {/if}
    </div>
  </section>

</div>

<style>
  /* ---- Page layout ---- */
  .stitch-settings {
    max-width: 720px;
  }

  .stitch-settings-header {
    margin-block-end: 32px;
  }

  .stitch-settings-title {
    font-family: 'Manrope', var(--font-sans);
    font-size: 1.875rem;
    font-weight: 800;
    letter-spacing: -0.025em;
    color: var(--color-text);
    margin: 0;
  }

  .stitch-settings-subtitle {
    font-size: 0.875rem;
    color: #6b7280;
    margin-block-start: 4px;
  }

  .stitch-section {
    margin-block-end: 24px;
  }

  .stitch-section-heading {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-block-end: 16px;
  }

  .stitch-section-icon {
    color: var(--color-primary);
    display: flex;
    align-items: center;
  }

  .stitch-section-title {
    font-size: 1.125rem;
    font-weight: 700;
    color: var(--color-text);
    margin: 0;
  }

  .stitch-section-content {
    background: #f2f4f5;
    border-radius: 16px;
    overflow: hidden;
  }

  .stitch-form {
    padding: 24px 32px 32px;
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .stitch-description {
    font-size: 0.875rem;
    color: #6b7280;
    line-height: 1.5;
  }

  /* ---- Fields ---- */
  .stitch-field {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .stitch-label {
    font-size: 0.6875rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #6b7280;
    margin-inline-start: 4px;
  }

  .stitch-input {
    display: block;
    width: 100%;
    padding: 12px 16px;
    background: #e6e8e9;
    border: none;
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    transition: background-color 0.2s ease, box-shadow 0.2s ease;
  }

  .stitch-input::placeholder {
    color: #9ca3af;
  }

  .stitch-input:focus {
    outline: none;
    background: white;
    box-shadow: 0 0 0 2px rgba(var(--color-primary-rgb, 59, 130, 246), 0.2);
  }

  /* ---- Status row (2FA enabled) ---- */
  .stitch-status-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    padding: 12px 0;
    border-block-end: 1px solid rgba(0, 0, 0, 0.06);
  }

  .stitch-status-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .stitch-status-label {
    font-size: 0.875rem;
    font-weight: 500;
    color: var(--color-text);
  }

  .stitch-status-value {
    font-size: 0.75rem;
    font-weight: 600;
  }

  .stitch-status-enabled {
    color: #16a34a;
  }

  /* ---- QR & backup codes ---- */
  .stitch-qr {
    display: flex;
    justify-content: center;
    padding: 16px;
  }

  .stitch-qr-img {
    width: 200px;
    height: 200px;
    border-radius: 10px;
    border: 1px solid rgba(0, 0, 0, 0.08);
  }

  .stitch-secret {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .stitch-secret-code {
    font-family: var(--font-mono);
    font-size: 0.875rem;
    padding: 10px 14px;
    background: #e6e8e9;
    border-radius: 10px;
    word-break: break-all;
    user-select: all;
  }

  .stitch-backup {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .stitch-codes-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 8px;
  }

  .stitch-backup-code {
    font-family: var(--font-mono);
    font-size: 0.875rem;
    padding: 6px 10px;
    background: #e6e8e9;
    border-radius: 8px;
    text-align: center;
    user-select: all;
  }

  /* ---- Error / Success ---- */
  .stitch-error {
    padding: 12px 16px;
    background: #fef2f2;
    color: #dc2626;
    border-radius: 10px;
    font-size: 0.875rem;
  }

  .stitch-success {
    padding: 12px 16px;
    background: #f0fdf4;
    color: #16a34a;
    border-radius: 10px;
    font-size: 0.875rem;
  }

  /* ---- Buttons ---- */
  .stitch-actions {
    display: flex;
    justify-content: flex-end;
    gap: 12px;
    padding-block-start: 8px;
  }

  .stitch-btn-primary {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 10px 28px;
    background: var(--color-primary);
    color: white;
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    box-shadow: 0 4px 14px rgba(var(--color-primary-rgb, 59, 130, 246), 0.2);
    transition: background-color 0.15s ease, box-shadow 0.15s ease, transform 0.1s ease;
  }

  .stitch-btn-primary:hover:not(:disabled) {
    background: var(--color-primary-hover);
    box-shadow: 0 6px 20px rgba(var(--color-primary-rgb, 59, 130, 246), 0.3);
  }

  .stitch-btn-primary:active:not(:disabled) {
    transform: scale(0.98);
  }

  .stitch-btn-primary:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .stitch-btn-ghost {
    padding: 10px 24px;
    background: transparent;
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    color: #6b7280;
    cursor: pointer;
    transition: color 0.15s ease, background-color 0.15s ease;
  }

  .stitch-btn-ghost:hover {
    color: var(--color-text);
    background: rgba(0, 0, 0, 0.04);
  }

  .stitch-btn-outline {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 10px 24px;
    background: transparent;
    border: 1.5px solid var(--color-primary);
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--color-primary);
    cursor: pointer;
    transition: background-color 0.15s ease;
  }

  .stitch-btn-outline:hover:not(:disabled) {
    background: rgba(var(--color-primary-rgb, 59, 130, 246), 0.06);
  }

  .stitch-btn-outline:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .stitch-btn-danger {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 10px 24px;
    background: #dc2626;
    color: white;
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    transition: background-color 0.15s ease, transform 0.1s ease;
  }

  .stitch-btn-danger:hover:not(:disabled) {
    background: #b91c1c;
  }

  .stitch-btn-danger:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .stitch-btn-sm {
    padding: 6px 16px;
    font-size: 0.75rem;
  }

  /* ---- Responsive ---- */
  @media (max-width: 640px) {
    .stitch-settings-title {
      font-size: 1.5rem;
    }

    .stitch-form {
      padding: 20px;
    }

    .stitch-status-row {
      flex-direction: column;
      align-items: flex-start;
      gap: 12px;
    }
  }

  /* Security Keys */
  .keys-list { display: flex; flex-direction: column; gap: 8px; margin-block-end: 16px; }

  .key-item {
    display: flex; align-items: center; justify-content: space-between;
    padding: 12px 16px; background: var(--color-surface); border-radius: 10px;
  }

  .key-info { display: flex; align-items: center; gap: 12px; }
  .key-icon { font-size: 24px; color: var(--color-primary); }
  .key-name { display: block; font-size: 0.875rem; font-weight: 600; }
  .key-meta { display: block; font-size: 0.7rem; color: var(--color-text-tertiary); }

  .key-remove {
    background: none; border: none; color: var(--color-text-tertiary); cursor: pointer;
    padding: 4px; border-radius: 50%;
  }
  .key-remove:hover { color: var(--color-danger); background: rgba(239,68,68,0.1); }

  .key-add-form { display: flex; gap: 8px; }

  .key-name-input {
    flex: 1; padding: 10px 14px; border: 1px solid var(--color-border); border-radius: 10px;
    font-size: 0.875rem; background: var(--color-surface); color: var(--color-text);
  }
  .key-name-input:focus { outline: none; border-color: var(--color-primary); }

  .key-add-btn {
    display: flex; align-items: center; gap: 6px;
    padding: 10px 18px; background: var(--color-primary); color: white; border: none;
    border-radius: 10px; font-size: 0.875rem; font-weight: 600; cursor: pointer; white-space: nowrap;
  }
  .key-add-btn:disabled { opacity: 0.5; cursor: not-allowed; }
  .key-add-btn:hover:not(:disabled) { opacity: 0.9; }
</style>
