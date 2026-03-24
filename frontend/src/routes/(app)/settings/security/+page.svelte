<script lang="ts">
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';
  import { changePassword, setupTwoFactor, verifyTwoFactor, disableTwoFactor, getCurrentUser } from '$lib/api/auth.js';
  import type { TwoFactorSetup } from '$lib/api/types.js';
  import { authStore, setUser } from '$lib/stores/auth.js';
  import { addToast } from '$lib/stores/toast.js';
  import { getSessions, revokeSession, revokeOtherSessions } from '$lib/api/sessions.js';
  import type { Session } from '$lib/api/sessions.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import QRCode from 'qrcode';

  // Password change
  let currentPassword = $state('');
  let newPassword = $state('');
  let confirmPassword = $state('');
  let passwordSaving = $state(false);
  let passwordSaved = $state(false);
  let passwordError: string | null = $state(null);

  // Sessions
  let sessions: Session[] = $state([]);
  let sessionsLoading = $state(true);
  let revokingAll = $state(false);

  // 2FA — load from user state
  let twoFactorEnabled = $state(false);

  onMount(async () => {
    const state = get(authStore);
    twoFactorEnabled = !!(state.user as any)?.two_factor_enabled;

    try {
      sessions = await getSessions();
    } catch {
      // Non-critical
    } finally {
      sessionsLoading = false;
    }
  });

  async function handleRevokeSession(id: string) {
    try {
      await revokeSession(id);
      sessions = sessions.filter(s => s.id !== id);
      addToast('Session revoked', 'success');
    } catch {
      addToast('Failed to revoke session', 'error');
    }
  }

  async function handleRevokeOthers() {
    revokingAll = true;
    try {
      const result = await revokeOtherSessions();
      sessions = sessions.filter(s => s.current);
      addToast(`Revoked ${result.count} other session${result.count === 1 ? '' : 's'}`, 'success');
    } catch {
      addToast('Failed to revoke sessions', 'error');
    } finally {
      revokingAll = false;
    }
  }

  function timeAgo(iso: string | null): string {
    if (!iso) return 'Never';
    const diff = Date.now() - new Date(iso).getTime();
    const minutes = Math.floor(diff / 60000);
    if (minutes < 1) return 'Just now';
    if (minutes < 60) return `${minutes}m ago`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
  }
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

  <!-- Active Sessions -->
  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/>
        </svg>
      </span>
      <h2 class="stitch-section-title">Active Sessions</h2>
    </div>

    <div class="stitch-section-content">
      <div class="stitch-form">
        <p class="stitch-description">
          These are the devices currently logged into your account. Revoke any session you don't recognise.
        </p>

        {#if sessionsLoading}
          <div class="stitch-sessions-loading"><Spinner size={20} /> Loading sessions...</div>
        {:else if sessions.length === 0}
          <p class="stitch-description">No active sessions found.</p>
        {:else}
          <div class="stitch-sessions-list">
            {#each sessions as session (session.id)}
              <div class="stitch-session" class:stitch-session-current={session.current}>
                <div class="stitch-session-icon">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    {#if session.device_name?.includes('Android') || session.device_name?.includes('iOS')}
                      <rect x="5" y="2" width="14" height="20" rx="2" ry="2"/><line x1="12" y1="18" x2="12.01" y2="18"/>
                    {:else}
                      <rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/>
                    {/if}
                  </svg>
                </div>
                <div class="stitch-session-info">
                  <div class="stitch-session-name">
                    {session.device_name}
                    {#if session.current}
                      <span class="stitch-session-badge">This device</span>
                    {/if}
                  </div>
                  <div class="stitch-session-meta">
                    {#if session.location}
                      <span>{session.location}</span>
                      <span class="stitch-session-dot">&middot;</span>
                    {/if}
                    {#if session.ip_address}
                      <span>{session.ip_address}</span>
                      <span class="stitch-session-dot">&middot;</span>
                    {/if}
                    <span>Active {timeAgo(session.last_active_at)}</span>
                  </div>
                </div>
                {#if !session.current}
                  <button
                    class="stitch-session-revoke"
                    onclick={() => handleRevokeSession(session.id)}
                  >
                    Revoke
                  </button>
                {/if}
              </div>
            {/each}
          </div>

          {#if sessions.length > 1}
            <div class="stitch-actions">
              <button
                class="stitch-btn-danger stitch-btn-sm"
                onclick={handleRevokeOthers}
                disabled={revokingAll}
              >
                {#if revokingAll}
                  <Spinner size={14} color="#fff" />
                {/if}
                Revoke all other sessions
              </button>
            </div>
          {/if}
        {/if}
      </div>
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

  /* ---- Sessions ---- */
  .stitch-sessions-loading {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 0.875rem;
    color: #6b7280;
  }

  .stitch-sessions-list {
    display: flex;
    flex-direction: column;
    gap: 1px;
    background: rgba(0, 0, 0, 0.06);
    border-radius: 12px;
    overflow: hidden;
  }

  .stitch-session {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 16px;
    background: #e6e8e9;
  }

  .stitch-session-current {
    background: rgba(var(--color-primary-rgb, 59, 130, 246), 0.08);
  }

  .stitch-session-icon {
    color: #6b7280;
    flex-shrink: 0;
  }

  .stitch-session-current .stitch-session-icon {
    color: var(--color-primary);
  }

  .stitch-session-info {
    flex: 1;
    min-width: 0;
  }

  .stitch-session-name {
    font-size: 0.875rem;
    font-weight: 500;
    color: var(--color-text);
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .stitch-session-badge {
    font-size: 0.625rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.03em;
    color: var(--color-primary);
    background: white;
    padding: 1px 8px;
    border-radius: 9999px;
  }

  .stitch-session-meta {
    font-size: 0.75rem;
    color: #9ca3af;
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .stitch-session-dot {
    font-size: 0.75rem;
  }

  .stitch-session-revoke {
    flex-shrink: 0;
    padding: 4px 12px;
    background: transparent;
    border: none;
    border-radius: 9999px;
    color: #dc2626;
    font-size: 0.75rem;
    font-weight: 600;
    cursor: pointer;
    transition: background-color 0.15s ease;
  }

  .stitch-session-revoke:hover {
    background: #fef2f2;
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
</style>
