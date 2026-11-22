<script lang="ts">
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';
  import { changePassword, setupTwoFactor, verifyTwoFactor, disableTwoFactor, getCurrentUser } from '$lib/api/auth.js';
  import type { TwoFactorSetup } from '$lib/api/types.js';
  import { authStore, setUser } from '$lib/stores/auth.js';
  import { addToast } from '$lib/stores/toast.js';
  import { instanceName } from '$lib/stores/instance.js';
  import { t } from '$lib/stores/i18n.js';
  import { t as translate } from '$lib/utils/i18n.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';
  import Toggle from '$lib/components/ui/Toggle.svelte';
  import SettingsSection from '$lib/components/settings/SettingsSection.svelte';
  import SettingRow from '$lib/components/settings/SettingRow.svelte';
  import QRCode from 'qrcode';
  import SessionsSettings from '$lib/components/settings/SessionsSettings.svelte';

  import { api } from '$lib/api/client.js';
  import {
    getRecoveryCodeStatus,
    generateRecoveryCode,
    deleteRecoveryCode,
  } from '$lib/api/recovery.js';
  import {
    isWarningDisabled,
    setWarningDisabled,
    clearTrustedDomains,
    knownTrustedDomains,
  } from '$lib/utils/external-link-trust.js';

  // The built-in allowlist is static, so read it once at module load.
  const preTrusted = knownTrustedDomains();
  let showPreTrusted = $state(false);

  // --- External link warning ---
  let externalLinkWarningEnabled = $state(true);

  function onExternalLinkWarning(enabled: boolean) {
    setWarningDisabled(!enabled);
  }

  function clearTrustedSites() {
    clearTrustedDomains();
    addToast(translate('settings.security_links_cleared'), 'success');
  }

  // --- Recovery code ---
  let recoveryStatus = $state<{
    enabled: boolean;
    generated_at: string | null;
    last_used_at: string | null;
  } | null>(null);
  let recoveryPassword = $state('');
  let recoveryGenerating = $state(false);
  let recoveryClearing = $state(false);
  let recoveryNewCode = $state<string | null>(null);
  let recoveryError = $state('');

  async function loadRecoveryStatus() {
    try {
      recoveryStatus = await getRecoveryCodeStatus();
    } catch {
      recoveryStatus = { enabled: false, generated_at: null, last_used_at: null };
    }
  }

  async function handleGenerateRecovery() {
    if (!recoveryPassword) {
      recoveryError = translate('settings.security_recovery_password_required');
      return;
    }
    recoveryGenerating = true;
    recoveryError = '';
    try {
      const result = await generateRecoveryCode(recoveryPassword);
      recoveryNewCode = result.recovery_code;
      recoveryPassword = '';
      await loadRecoveryStatus();
    } catch (e: unknown) {
      const err = e as { body?: { error?: string; message?: string } };
      recoveryError =
        err?.body?.error === 'auth.invalid_password'
          ? translate('settings.security_wrong_password')
          : err?.body?.error === 'recovery.two_factor_required'
            ? err?.body?.message || translate('settings.security_recovery_2fa_required')
            : translate('settings.security_recovery_generate_failed');
    } finally {
      recoveryGenerating = false;
    }
  }

  async function handleClearRecovery() {
    if (!recoveryPassword) {
      recoveryError = translate('settings.security_recovery_password_required_clear');
      return;
    }
    recoveryClearing = true;
    recoveryError = '';
    try {
      await deleteRecoveryCode(recoveryPassword);
      recoveryPassword = '';
      recoveryNewCode = null;
      await loadRecoveryStatus();
    } catch (e: unknown) {
      const err = e as { body?: { error?: string } };
      recoveryError =
        err?.body?.error === 'auth.invalid_password'
          ? translate('settings.security_wrong_password')
          : translate('settings.security_recovery_clear_failed');
    } finally {
      recoveryClearing = false;
    }
  }

  function copyRecoveryCode() {
    if (recoveryNewCode) navigator.clipboard?.writeText(recoveryNewCode).catch(() => {});
    addToast(translate('settings.security_recovery_copied'), 'success');
  }

  function dismissNewCode() {
    recoveryNewCode = null;
  }

  // WebAuthn / Security Keys
  interface WebauthnCred { id: string; name: string; credential_id: string; sign_count: number; last_used_at: string | null; created_at: string; }
  let securityKeys = $state<WebauthnCred[]>([]);
  let keysLoading = $state(true);
  let keyName = $state('');
  let keyRegistering = $state(false);

  async function loadKeys() {
    try {
      securityKeys = await api.get<WebauthnCred[]>('/api/v1/auth/webauthn/credentials');
    } catch {
      addToast(translate('settings.security_keys_load_failed'), 'error');
    }
    finally { keysLoading = false; }
  }

  async function registerKey() {
    if (!navigator.credentials) {
      addToast(translate('settings.security_keys_unsupported'), 'error');
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

      // 4. Send to server. The fallback name is stored, so it stays untranslated.
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
      addToast(translate('settings.security_keys_registered'), 'success');
      await loadKeys();
    } catch (e) {
      addToast(e instanceof Error ? e.message : translate('settings.security_keys_register_failed'), 'error');
    } finally { keyRegistering = false; }
  }

  // Removing a security key removes an authentication factor, so confirm
  // it explicitly rather than deleting on a single click.
  let keyToDelete = $state<WebauthnCred | null>(null);
  let showDeleteKeyModal = $state(false);
  let keyDeleting = $state(false);

  function askDeleteKey(key: WebauthnCred) {
    keyToDelete = key;
    showDeleteKeyModal = true;
  }

  async function confirmDeleteKey() {
    if (!keyToDelete || keyDeleting) return;
    keyDeleting = true;
    const id = keyToDelete.id;
    try {
      await api.delete(`/api/v1/auth/webauthn/credentials/${id}`);
      securityKeys = securityKeys.filter(k => k.id !== id);
      addToast(translate('settings.security_keys_removed'), 'success');
      showDeleteKeyModal = false;
      keyToDelete = null;
    } catch {
      addToast(translate('settings.security_keys_remove_failed'), 'error');
    } finally {
      keyDeleting = false;
    }
  }

  // Password change
  let currentPassword = $state('');
  let newPassword = $state('');
  let confirmPassword = $state('');
  let passwordSaving = $state(false);
  let passwordSaved = $state(false);
  let passwordError: string | null = $state(null);

  // 2FA, loaded from user state
  let twoFactorEnabled = $state(false);

  onMount(async () => {
    const state = get(authStore);
    twoFactorEnabled = !!(state.user as any)?.two_factor_enabled;
    externalLinkWarningEnabled = !isWarningDisabled();
    loadKeys();
    loadRecoveryStatus();
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
      passwordError = translate('settings.security_password_mismatch');
      return;
    }

    if (newPassword.length < 16) {
      passwordError = translate('settings.security_password_too_short');
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
      passwordError = e instanceof Error ? e.message : translate('settings.security_password_failed');
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
      twoFAError = e instanceof Error ? e.message : translate('settings.security_2fa_setup_failed');
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
      twoFASuccess = translate('settings.security_2fa_enabled_message');
      setTimeout(() => { twoFASuccess = null; }, 3000);
      // Refresh user data so admin panel sees 2FA enabled
      try {
        const user = await getCurrentUser();
        setUser(user);
      } catch {};
    } catch (e) {
      twoFAError = e instanceof Error ? e.message : translate('settings.security_2fa_invalid_verification');
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
      twoFASuccess = translate('settings.security_2fa_disabled_message');
      setTimeout(() => { twoFASuccess = null; }, 3000);
    } catch (e) {
      twoFAError = e instanceof Error ? e.message : translate('settings.security_2fa_invalid_code');
    } finally {
      twoFALoading = false;
    }
  }

  const formatDate = (iso: string) => new Date(iso).toLocaleDateString();
</script>

<div class="security-page">
  <SettingsSection title={$t('settings.security_password_title')} description={$t('settings.security_password_desc')}>
    <form class="security-form" onsubmit={(e) => { e.preventDefault(); handlePasswordChange(); }}>
      <SettingRow label={$t('settings.security_password_current')} labelFor="current-password" layout="stacked">
        <input id="current-password" type="password" class="input" bind:value={currentPassword} autocomplete="current-password" required />
      </SettingRow>
      <SettingRow label={$t('settings.security_password_new')} labelFor="new-password" layout="stacked">
        <input
          id="new-password"
          type="password"
          class="input"
          bind:value={newPassword}
          autocomplete="new-password"
          minlength="16"
          placeholder={$t('settings.security_password_new_placeholder')}
          required
        />
      </SettingRow>
      <SettingRow label={$t('settings.security_password_confirm')} labelFor="confirm-password" layout="stacked">
        <input id="confirm-password" type="password" class="input" bind:value={confirmPassword} autocomplete="new-password" required />
      </SettingRow>

      {#if passwordError}
        <div class="security-note error">{passwordError}</div>
      {/if}
      {#if passwordSaved}
        <div class="security-note success">{$t('settings.security_password_changed')}</div>
      {/if}

      <div class="security-actions">
        <button class="btn btn-primary btn-sm" type="submit" disabled={passwordSaving}>
          {#if passwordSaving}<Spinner size={16} color="#fff" />{/if}
          {$t('settings.security_password_submit')}
        </button>
      </div>
    </form>
  </SettingsSection>

  <SettingsSection title={$t('settings.security_2fa_title')} description={$t('settings.security_2fa_desc')}>
    {#if twoFASuccess || twoFAError}
      <div class="security-block">
        {#if twoFASuccess}<div class="security-note success">{twoFASuccess}</div>{/if}
        {#if twoFAError}<div class="security-note error">{twoFAError}</div>{/if}
      </div>
    {/if}

    {#if !twoFactorEnabled && !showSetup}
      <SettingRow label={$t('settings.security_2fa_app')} help={$t('settings.security_2fa_intro')}>
        <button class="btn btn-outline btn-sm" type="button" onclick={handleSetup2FA} disabled={twoFALoading}>
          {#if twoFALoading}<Spinner size={16} />{/if}
          {$t('settings.security_2fa_enable')}
        </button>
      </SettingRow>
    {:else if showSetup && twoFactorSetup}
      <div class="security-block">
        <p class="security-muted">{$t('settings.security_2fa_setup_help')}</p>
        <div class="security-qr">
          <img src={qrDataUrl} alt={$t('settings.security_2fa_qr_alt')} class="security-qr-img" />
        </div>
        <div class="security-field">
          <span class="security-field-label">{$t('settings.security_2fa_manual_key')}</span>
          <code class="security-code" dir="ltr">{twoFactorSetup.secret}</code>
        </div>
        {#if twoFactorSetup.backup_codes?.length > 0}
          <div class="security-field">
            <span class="security-field-label">{$t('settings.security_2fa_backup_codes')}</span>
            <div class="security-codes-grid" dir="ltr">
              {#each twoFactorSetup.backup_codes as code}
                <code class="security-code">{code}</code>
              {/each}
            </div>
          </div>
        {/if}
      </div>
      <form class="security-form" onsubmit={(e) => { e.preventDefault(); handleVerify2FA(); }}>
        <SettingRow label={$t('settings.security_2fa_verify_code')} labelFor="verify-code" layout="stacked">
          <input
            id="verify-code"
            type="text"
            class="input"
            bind:value={verifyCode}
            placeholder={$t('settings.security_2fa_code_placeholder')}
            maxlength="6"
            autocomplete="one-time-code"
            required
          />
        </SettingRow>
        <div class="security-actions">
          <button class="btn btn-ghost btn-sm" type="button" onclick={() => { showSetup = false; twoFactorSetup = null; }}>
            {$t('common.cancel')}
          </button>
          <button class="btn btn-primary btn-sm" type="submit" disabled={twoFALoading}>
            {#if twoFALoading}<Spinner size={16} color="#fff" />{/if}
            {$t('settings.security_2fa_verify_submit')}
          </button>
        </div>
      </form>
    {:else if twoFactorEnabled && !showDisable}
      <SettingRow label={$t('settings.security_2fa_app')}>
        {#snippet meta()}<span class="security-status-on">{$t('settings.security_2fa_enabled')}</span>{/snippet}
        <button class="btn btn-danger btn-sm" type="button" onclick={() => { showDisable = true; }}>
          {$t('settings.security_2fa_disable')}
        </button>
      </SettingRow>
      {#if recoveryStatus && !recoveryStatus.enabled}
        <div class="security-block">
          <div class="security-callout" role="note">
            <span class="material-symbols-outlined" aria-hidden="true">key</span>
            <div>
              <strong>{$t('settings.security_2fa_recovery_nudge_title')}</strong>
              {$t('settings.security_2fa_recovery_nudge')}
              <a href="#recovery-code">{$t('settings.security_2fa_recovery_nudge_link')}</a>
            </div>
          </div>
        </div>
      {/if}
    {:else if showDisable}
      <form class="security-form" onsubmit={(e) => { e.preventDefault(); handleDisable2FA(); }}>
        <SettingRow label={$t('settings.security_2fa_disable_code')} labelFor="disable-code" layout="stacked">
          <input
            id="disable-code"
            type="text"
            class="input"
            bind:value={disableCode}
            placeholder={$t('settings.security_2fa_code_placeholder')}
            maxlength="6"
            autocomplete="one-time-code"
            required
          />
        </SettingRow>
        <div class="security-actions">
          <button class="btn btn-ghost btn-sm" type="button" onclick={() => { showDisable = false; }}>
            {$t('common.cancel')}
          </button>
          <button class="btn btn-danger btn-sm" type="submit" disabled={twoFALoading}>
            {#if twoFALoading}<Spinner size={16} color="#fff" />{/if}
            {$t('settings.security_2fa_disable')}
          </button>
        </div>
      </form>
    {/if}
  </SettingsSection>

  <SettingsSection title={$t('settings.security_keys_title')} description={$t('settings.security_keys_desc')}>
    {#if keysLoading}
      <div class="security-block security-loading"><Spinner /></div>
    {:else}
      {#each securityKeys as key (key.id)}
        <div class="security-item">
          <span class="material-symbols-outlined security-item-icon" aria-hidden="true">key</span>
          <div class="security-item-info">
            <span class="security-item-name">{key.name}</span>
            <span class="security-item-meta">
              {$t('settings.security_keys_added', { date: formatDate(key.created_at) })}
              {#if key.last_used_at}
                &middot; {$t('settings.security_last_used', { date: formatDate(key.last_used_at) })}
              {/if}
              &middot; {$t('settings.security_keys_uses', { count: key.sign_count })}
            </span>
          </div>
          <button type="button" class="security-item-remove" onclick={() => askDeleteKey(key)} aria-label={$t('settings.security_keys_remove_label', { name: key.name })}>
            <span class="material-symbols-outlined" aria-hidden="true">delete</span>
          </button>
        </div>
      {/each}

      <SettingRow label={$t('settings.security_keys_name_label')} labelFor="key-name" layout="stacked">
        <div class="security-inline">
          <input id="key-name" type="text" class="input" bind:value={keyName} placeholder={$t('settings.security_keys_name_placeholder')} />
          <button type="button" class="btn btn-primary btn-sm" onclick={registerKey} disabled={keyRegistering}>
            <span class="material-symbols-outlined security-btn-icon" aria-hidden="true">add</span>
            {keyRegistering ? $t('settings.security_keys_waiting') : $t('settings.security_keys_add')}
          </button>
        </div>
      </SettingRow>
    {/if}
  </SettingsSection>

  <div id="recovery-code">
    <SettingsSection title={$t('settings.security_recovery_title')} description={$t('settings.security_recovery_desc')}>
      {#if recoveryNewCode}
        <div class="security-block">
          <div class="recovery-reveal">
            <div class="recovery-reveal-title">{$t('settings.security_recovery_save_title')}</div>
            <p class="recovery-reveal-sub">{$t('settings.security_recovery_save_help')}</p>
            <div class="recovery-code-display" dir="ltr"><code>{recoveryNewCode}</code></div>
            <div class="security-button-row">
              <button type="button" class="btn btn-outline btn-sm" onclick={copyRecoveryCode}>{$t('settings.security_recovery_copy')}</button>
              <button type="button" class="btn btn-outline btn-sm" onclick={() => window.print()}>{$t('settings.security_recovery_print')}</button>
              <button type="button" class="btn btn-primary btn-sm" onclick={dismissNewCode}>{$t('settings.security_recovery_saved')}</button>
            </div>
          </div>
        </div>
      {:else if !twoFactorEnabled}
        <div class="security-block">
          <strong class="security-strong">{$t('settings.security_recovery_needs_2fa')}</strong>
          <p class="security-muted">{$t('settings.security_recovery_needs_2fa_help')}</p>
        </div>
      {:else}
        <div class="security-block">
          {#if recoveryStatus?.enabled}
            <strong class="security-strong">{$t('settings.security_recovery_set')}</strong>
            {#if recoveryStatus.generated_at}
              <span class="security-item-meta">{$t('settings.security_recovery_regenerated', { date: formatDate(recoveryStatus.generated_at) })}</span>
            {/if}
            {#if recoveryStatus.last_used_at}
              <span class="security-item-meta">{$t('settings.security_last_used', { date: formatDate(recoveryStatus.last_used_at) })}</span>
            {/if}
          {:else}
            <div class="security-callout" role="note">
              <span class="material-symbols-outlined" aria-hidden="true">warning</span>
              <div>
                <strong>{$t('settings.security_recovery_none_title')}</strong>
                {$t('settings.security_recovery_none')}
              </div>
            </div>
          {/if}
        </div>

        <div class="security-form">
          <SettingRow label={$t('settings.security_password_current')} labelFor="rc-password" layout="stacked">
            <input
              id="rc-password"
              type="password"
              class="input"
              bind:value={recoveryPassword}
              autocomplete="current-password"
              placeholder={$t('settings.security_recovery_password_placeholder')}
            />
          </SettingRow>

          {#if recoveryError}
            <div class="security-note error" role="alert">{recoveryError}</div>
          {/if}

          <div class="security-actions">
            {#if recoveryStatus?.enabled}
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                disabled={recoveryClearing || !recoveryPassword}
                onclick={handleClearRecovery}
              >
                {recoveryClearing ? $t('settings.security_recovery_clearing') : $t('settings.security_recovery_remove')}
              </button>
            {/if}
            <button
              type="button"
              class="btn btn-primary btn-sm"
              disabled={recoveryGenerating || !recoveryPassword}
              onclick={handleGenerateRecovery}
            >
              {recoveryGenerating
                ? $t('settings.security_recovery_generating')
                : recoveryStatus?.enabled
                  ? $t('settings.security_recovery_generate_new')
                  : $t('settings.security_recovery_generate')}
            </button>
          </div>
        </div>
      {/if}
    </SettingsSection>
  </div>

  <SessionsSettings />

  <SettingsSection title={$t('settings.security_links_title')} description={$t('settings.security_links_desc', { instance: $instanceName })}>
    <SettingRow
      label={$t('settings.security_links_warn')}
      help={externalLinkWarningEnabled ? $t('settings.security_links_on') : $t('settings.security_links_off')}
      labelFor="s-extlink"
    >
      <Toggle id="s-extlink" bind:checked={externalLinkWarningEnabled} onchange={onExternalLinkWarning} />
    </SettingRow>

    {#if externalLinkWarningEnabled}
      <SettingRow label={$t('settings.security_links_trusted')} help={$t('settings.security_links_trusted_help')}>
        <button type="button" class="btn btn-ghost btn-sm" onclick={clearTrustedSites}>
          {$t('settings.security_links_clear')}
        </button>
      </SettingRow>

      <SettingRow label={$t('settings.security_links_pretrusted')} help={$t('settings.security_links_pretrusted_help', { n: preTrusted.length })}>
        <button type="button" class="btn btn-ghost btn-sm" aria-expanded={showPreTrusted} onclick={() => (showPreTrusted = !showPreTrusted)}>
          {showPreTrusted ? $t('settings.security_links_hide') : $t('settings.security_links_show')}
        </button>
      </SettingRow>

      {#if showPreTrusted}
        <div class="security-block">
          <ul class="pre-trusted-list" dir="ltr">
            {#each preTrusted as domain (domain)}
              <li><code>{domain}</code></li>
            {/each}
          </ul>
        </div>
      {/if}
    {/if}
  </SettingsSection>
</div>

<Modal bind:open={showDeleteKeyModal} title={$t('settings.security_keys_remove_title')} onclose={() => { keyToDelete = null; }}>
  {#if keyToDelete}
    <p class="confirm-message">{$t('settings.security_keys_remove_message', { name: keyToDelete.name })}</p>
    <div class="confirm-actions">
      <button type="button" class="btn btn-ghost btn-sm" onclick={() => (showDeleteKeyModal = false)}>{$t('common.cancel')}</button>
      <button type="button" class="btn btn-danger btn-sm" onclick={confirmDeleteKey} disabled={keyDeleting}>
        {#if keyDeleting}<Spinner size={14} color="#fff" />{/if}
        {$t('settings.security_keys_remove')}
      </button>
    </div>
  {/if}
</Modal>

<style>
  .security-page {
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  /* Clear the sticky settings header when the 2FA nudge anchors here. */
  #recovery-code {
    scroll-margin-block-start: var(--space-8);
  }

  .security-form {
    display: flex;
    flex-direction: column;
  }

  .security-form > :global(.setting-row + .setting-row) {
    border-block-start: 1px solid var(--color-border);
  }

  .security-block {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    padding: var(--space-4) var(--space-5);
  }

  .security-actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: var(--space-2);
    padding: 0 var(--space-5) var(--space-4);
  }

  .security-button-row {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2);
  }

  .security-inline {
    display: flex;
    gap: var(--space-2);
  }

  .security-inline .input {
    flex: 1;
    min-width: 0;
  }

  .security-btn-icon {
    font-size: 18px;
  }

  .security-muted {
    margin: 0;
    font-size: var(--text-sm);
    line-height: 1.5;
    color: var(--color-text-secondary);
  }

  .security-strong {
    font-size: var(--text-sm);
    color: var(--color-text);
  }

  .security-loading {
    align-items: center;
  }

  .security-note {
    margin: 0 var(--space-5) var(--space-3);
    padding: var(--space-3) var(--space-4);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  .security-block .security-note {
    margin: 0;
  }

  .security-note.error {
    background: var(--color-danger-soft);
    color: var(--color-danger);
  }

  .security-note.success {
    background: var(--color-success-soft);
    color: var(--color-success);
  }

  .security-status-on {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-success);
  }

  /* Actionable warning: 2FA is on but no recovery code is set. */
  .security-callout {
    display: flex;
    gap: var(--space-2);
    align-items: flex-start;
    padding: var(--space-3);
    border-radius: var(--radius-md);
    background: var(--color-warning-soft);
    border: 1px solid var(--color-warning);
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: 1.5;
  }

  .security-callout .material-symbols-outlined {
    font-size: 20px;
    color: var(--color-warning);
    flex-shrink: 0;
  }

  .security-callout a {
    color: var(--color-primary);
    font-weight: 600;
  }

  /* ---- 2FA setup ---- */
  .security-qr {
    display: flex;
    justify-content: center;
  }

  .security-qr-img {
    width: 200px;
    height: 200px;
    border-radius: var(--radius-md);
    border: 1px solid var(--color-border);
  }

  .security-field {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .security-field-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .security-code {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    padding: var(--space-2) var(--space-3);
    background: var(--color-surface-container-high);
    border-radius: var(--radius-md);
    word-break: break-all;
    user-select: all;
    text-align: center;
  }

  .security-codes-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: var(--space-2);
  }

  /* ---- Security keys ---- */
  .security-item {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-5);
  }

  .security-item-icon {
    font-size: 24px;
    color: var(--color-primary);
    flex-shrink: 0;
  }

  .security-item-info {
    flex: 1;
    min-width: 0;
  }

  .security-item-name {
    display: block;
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .security-item-meta {
    display: block;
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .security-item-remove {
    display: inline-flex;
    background: none;
    border: none;
    color: var(--color-text-tertiary);
    cursor: pointer;
    padding: var(--space-1);
    border-radius: var(--radius-full);
  }

  .security-item-remove .material-symbols-outlined {
    font-size: 18px;
  }

  .security-item-remove:hover {
    color: var(--color-danger);
    background: var(--color-danger-soft);
  }

  /* ---- Recovery code ---- */
  .recovery-reveal {
    background: var(--color-warning-soft);
    border: 1px solid var(--color-warning);
    border-radius: var(--radius-lg);
    padding: var(--space-4);
  }

  .recovery-reveal-title {
    font-weight: 700;
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .recovery-reveal-sub {
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: 1.5;
    margin: 0 0 var(--space-3);
  }

  .recovery-code-display {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    padding: var(--space-4);
    text-align: center;
    margin-block-end: var(--space-3);
  }

  .recovery-code-display code {
    font-family: var(--font-mono);
    font-size: var(--text-xl);
    font-weight: 700;
    letter-spacing: 0.08em;
    color: var(--color-text);
    word-break: break-all;
  }

  /* ---- External links ---- */
  .pre-trusted-list {
    list-style: none;
    padding: var(--space-3);
    margin: 0;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
    gap: var(--space-1);
    max-height: 200px;
    overflow-y: auto;
  }

  .pre-trusted-list code {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .confirm-message {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.5;
    margin-block-end: var(--space-4);
  }

  .confirm-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
  }
</style>
