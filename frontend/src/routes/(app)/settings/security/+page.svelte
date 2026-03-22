<script lang="ts">
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';
  import { changePassword, setupTwoFactor, verifyTwoFactor, disableTwoFactor, getCurrentUser } from '$lib/api/auth.js';
  import type { TwoFactorSetup } from '$lib/api/types.js';
  import { authStore, setUser } from '$lib/stores/auth.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import QRCode from 'qrcode';

  // Password change
  let currentPassword = $state('');
  let newPassword = $state('');
  let confirmPassword = $state('');
  let passwordSaving = $state(false);
  let passwordSaved = $state(false);
  let passwordError: string | null = $state(null);

  // 2FA — load from user state
  let twoFactorEnabled = $state(false);

  onMount(() => {
    const state = get(authStore);
    twoFactorEnabled = !!(state.user as any)?.two_factor_enabled;
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

    if (newPassword.length < 8) {
      passwordError = 'Password must be at least 8 characters';
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

<div class="settings-sections">
  <!-- Change Password -->
  <div class="settings-section">
    <h2 class="section-title">Change Password</h2>
    <form class="settings-form" onsubmit={(e) => { e.preventDefault(); handlePasswordChange(); }}>
      <div class="form-group">
        <label class="form-label" for="current-password">Current password</label>
        <input
          id="current-password"
          type="password"
          class="input"
          bind:value={currentPassword}
          autocomplete="current-password"
          required
        />
      </div>

      <div class="form-group">
        <label class="form-label" for="new-password">New password</label>
        <input
          id="new-password"
          type="password"
          class="input"
          bind:value={newPassword}
          autocomplete="new-password"
          minlength="8"
          required
        />
      </div>

      <div class="form-group">
        <label class="form-label" for="confirm-password">Confirm new password</label>
        <input
          id="confirm-password"
          type="password"
          class="input"
          bind:value={confirmPassword}
          autocomplete="new-password"
          required
        />
      </div>

      {#if passwordError}
        <div class="form-error">{passwordError}</div>
      {/if}

      {#if passwordSaved}
        <div class="form-success">Password changed successfully</div>
      {/if}

      <div class="form-actions">
        <button class="btn btn-primary" type="submit" disabled={passwordSaving}>
          {#if passwordSaving}
            <Spinner size={16} color="var(--color-text-on-primary)" />
          {/if}
          Change password
        </button>
      </div>
    </form>
  </div>

  <!-- Two-Factor Authentication -->
  <div class="settings-section">
    <h2 class="section-title">Two-Factor Authentication</h2>
    <div class="settings-form">
      {#if twoFASuccess}
        <div class="form-success">{twoFASuccess}</div>
      {/if}

      {#if twoFAError}
        <div class="form-error">{twoFAError}</div>
      {/if}

      {#if !twoFactorEnabled && !showSetup}
        <p class="form-description">
          Add an extra layer of security to your account by enabling two-factor authentication.
        </p>
        <div class="form-actions">
          <button class="btn btn-outline" type="button" onclick={handleSetup2FA} disabled={twoFALoading}>
            {#if twoFALoading}
              <Spinner size={16} />
            {/if}
            Enable 2FA
          </button>
        </div>
      {:else if showSetup && twoFactorSetup}
        <p class="form-description">
          Scan the QR code below with your authenticator app (like Google Authenticator or Authy), then enter the verification code.
        </p>

        <div class="qr-section">
          <img src={qrDataUrl} alt="2FA QR Code" class="qr-code" />
        </div>

        <div class="secret-section">
          <span class="form-label">Manual entry key:</span>
          <code class="secret-code">{twoFactorSetup.secret}</code>
        </div>

        {#if twoFactorSetup.backup_codes?.length > 0}
          <div class="backup-codes">
            <span class="form-label">Backup codes (save these somewhere safe):</span>
            <div class="codes-grid">
              {#each twoFactorSetup.backup_codes as code}
                <code class="backup-code">{code}</code>
              {/each}
            </div>
          </div>
        {/if}

        <form onsubmit={(e) => { e.preventDefault(); handleVerify2FA(); }}>
          <div class="form-group">
            <label class="form-label" for="verify-code">Verification code</label>
            <input
              id="verify-code"
              type="text"
              class="input"
              bind:value={verifyCode}
              placeholder="Enter 6-digit code"
              maxlength="6"
              autocomplete="one-time-code"
              required
            />
          </div>
          <div class="form-actions form-actions-gap">
            <button class="btn btn-ghost" type="button" onclick={() => { showSetup = false; twoFactorSetup = null; }}>
              Cancel
            </button>
            <button class="btn btn-primary" type="submit" disabled={twoFALoading}>
              {#if twoFALoading}
                <Spinner size={16} color="var(--color-text-on-primary)" />
              {/if}
              Verify & Enable
            </button>
          </div>
        </form>
      {:else if twoFactorEnabled && !showDisable}
        <p class="form-description">
          Two-factor authentication is currently enabled on your account.
        </p>
        <div class="form-actions">
          <button class="btn btn-danger" type="button" onclick={() => { showDisable = true; }}>
            Disable 2FA
          </button>
        </div>
      {:else if showDisable}
        <form onsubmit={(e) => { e.preventDefault(); handleDisable2FA(); }}>
          <div class="form-group">
            <label class="form-label" for="disable-code">Enter your 2FA code to disable</label>
            <input
              id="disable-code"
              type="text"
              class="input"
              bind:value={disableCode}
              placeholder="Enter 6-digit code"
              maxlength="6"
              autocomplete="one-time-code"
              required
            />
          </div>
          <div class="form-actions form-actions-gap">
            <button class="btn btn-ghost" type="button" onclick={() => { showDisable = false; }}>
              Cancel
            </button>
            <button class="btn btn-danger" type="submit" disabled={twoFALoading}>
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

  <!-- Active Sessions -->
  <div class="settings-section">
    <h2 class="section-title">Active Sessions</h2>
    <div class="settings-form">
      <p class="form-description">
        Session management is coming soon. You will be able to view and revoke active sessions here.
      </p>
    </div>
  </div>
</div>

<style>
  .settings-sections {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .settings-section {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow: hidden;
  }

  .section-title {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--color-text);
    padding: var(--space-4) var(--space-6);
    border-block-end: 1px solid var(--color-border);
  }

  .settings-form {
    padding: var(--space-6);
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .form-description {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: var(--line-height);
  }

  .form-group {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .form-label {
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
  }

  .form-error {
    padding: var(--space-3);
    background: var(--color-danger-soft);
    color: var(--color-danger);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  .form-success {
    padding: var(--space-3);
    background: var(--color-success-soft);
    color: var(--color-success);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  .form-actions {
    display: flex;
    justify-content: flex-end;
  }

  .form-actions-gap {
    gap: var(--space-2);
    margin-block-start: var(--space-4);
  }

  .qr-section {
    display: flex;
    justify-content: center;
    padding: var(--space-4);
  }

  .qr-code {
    width: 200px;
    height: 200px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
  }

  .secret-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .secret-code {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    padding: var(--space-2) var(--space-3);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    word-break: break-all;
    user-select: all;
  }

  .backup-codes {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .codes-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: var(--space-2);
  }

  .backup-code {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    padding: var(--space-1) var(--space-2);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    text-align: center;
    user-select: all;
  }
</style>
