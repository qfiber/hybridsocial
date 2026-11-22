<script lang="ts">
  import { onMount } from 'svelte';
  import { api, ApiError } from '$lib/api/client.js';
  import { clearAuth, currentUser, setUser } from '$lib/stores/auth.js';
  import SettingsSection from '$lib/components/settings/SettingsSection.svelte';
  import SettingRow from '$lib/components/settings/SettingRow.svelte';
  import { switchLocale, availableLocales, locale, t } from '$lib/stores/i18n.js';
  import { translationTarget, setTranslationTarget } from '$lib/stores/translation.js';
  import { preferencesStore, updatePreferences } from '$lib/stores/preferences.js';
  import { addToast } from '$lib/stores/toast.js';
  import Modal from '$lib/components/ui/Modal.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import VerifiedBadge from '$lib/components/ui/VerifiedBadge.svelte';

  let selectedLocale = $state('en');
  let localeSaving = $state(false);

  // Preferred language to translate posts INTO. '' follows the interface
  // language. Stored per-device by the translation store (localStorage).
  let selectedTranslateTarget = $state('');

  function saveTranslateTarget() {
    setTranslationTarget(selectedTranslateTarget);
  }

  let showDeleteModal = $state(false);
  let deleteConfirmText = $state('');
  let deleting = $state(false);
  let error: string | null = $state(null);

  // Verification state
  interface VerificationStatus {
    status: 'none' | 'pending' | 'approved' | 'rejected';
    type?: string;
    verified_at: string | null;
    vouch_count?: number;
  }

  let verification = $state<VerificationStatus>({ status: 'none', verified_at: null });
  let verificationLoading = $state(true);
  let showVerificationForm = $state(false);
  let verificationType = $state<'manual' | 'peer_vouch'>('manual');
  let verificationSubmitting = $state(false);
  let verificationError = $state('');
  let verificationSuccess = $state('');

  // Email change: the new address only takes effect from its emailed link.
  let newEmail = $state('');
  let emailPassword = $state('');
  let emailSaving = $state(false);
  const emailErrors: Record<string, string> = {
    'auth.invalid_password': 'settings.email_error_password',
    'account.email_taken': 'settings.email_error_taken',
    'account.email_unchanged': 'settings.email_error_same',
    'account.email_invalid': 'settings.email_error_invalid',
  };

  async function requestEmailChange(e: SubmitEvent) {
    e.preventDefault();
    if (emailSaving || !$currentUser) return;
    emailSaving = true;
    try {
      const res = await api.post<{ pending_email: string }>('/api/v1/accounts/change_email', {
        email: newEmail.trim(),
        password: emailPassword,
      });
      setUser({ ...$currentUser, pending_email: res.pending_email });
      addToast($t('settings.email_sent', { email: res.pending_email }), 'success');
      newEmail = '';
      emailPassword = '';
    } catch (err) {
      const code = err instanceof ApiError ? err.body?.error : '';
      addToast($t(emailErrors[code ?? ''] ?? 'settings.email_error_generic'), 'error');
    } finally {
      emailSaving = false;
    }
  }

  async function cancelEmailChange() {
    if (!$currentUser) return;
    try {
      await api.delete('/api/v1/accounts/change_email');
      setUser({ ...$currentUser, pending_email: null });
    } catch {
      addToast($t('settings.email_error_generic'), 'error');
    }
  }

  // Saves on change; the interface switches straight away.
  async function saveLocale(e: Event) {
    const prev = selectedLocale;
    selectedLocale = (e.currentTarget as HTMLSelectElement).value;
    localeSaving = true;
    try {
      await api.patch('/api/v1/accounts/update_credentials', { locale: selectedLocale });
      await switchLocale(selectedLocale);
    } catch {
      selectedLocale = prev;
      addToast($t('settings.save_failed'), 'error');
    } finally { localeSaving = false; }
  }

  onMount(async () => {
    // Set current locale from store
    const unsub = locale.subscribe(v => { selectedLocale = v; });
    unsub();

    // Seed the translation-target select from its store.
    const unsubTt = translationTarget.subscribe(v => { selectedTranslateTarget = v; });
    unsubTt();

    try {
      verification = await api.get<VerificationStatus>('/api/v1/verification/status');
    } catch {
      verification = { status: 'none', verified_at: null };
    } finally {
      verificationLoading = false;
    }
  });

  async function submitVerification() {
    verificationSubmitting = true;
    verificationError = '';
    verificationSuccess = '';
    try {
      await api.post('/api/v1/verification/apply', {
        type: verificationType,
        metadata: {},
      });
      verification = { status: 'pending', type: verificationType, verified_at: null };
      showVerificationForm = false;
      verificationSuccess = $t('settings.verify_submitted');
      setTimeout(() => { verificationSuccess = ''; }, 5000);
    } catch (e) {
      const code = e instanceof ApiError ? (e.body as { error?: string } | undefined)?.error : undefined;
      verificationError =
        code === 'verification.already_pending'
          ? $t('verification.already_pending')
          : code === 'verification.already_verified'
            ? $t('verification.already_verified')
            : $t('verification.apply_failed');
    } finally {
      verificationSubmitting = false;
    }
  }

  let canDelete = $derived(deleteConfirmText === 'DELETE');

  async function handleDeleteAccount() {
    if (!canDelete) return;
    deleting = true;
    error = null;
    try {
      await api.delete('/api/v1/accounts/delete');
      clearAuth();
      window.location.href = '/';
    } catch (e) {
      error = e instanceof Error ? e.message : $t('settings.delete_failed');
      deleting = false;
    }
  }
</script>

<div class="settings-sections">
  <SettingsSection title={$t('settings.email_title')} description={$t('settings.email_desc')}>
    <SettingRow label={$t('settings.email_current')}>
      <span class="email-current" dir="ltr">{$currentUser?.email ?? ''}</span>
    </SettingRow>
    {#if $currentUser?.pending_email}
      <SettingRow label={$t('settings.email_pending_label')} help={$t('settings.email_pending_help', { email: $currentUser.pending_email })}>
        <button type="button" class="btn btn-secondary btn-sm" onclick={cancelEmailChange}>{$t('settings.email_cancel')}</button>
      </SettingRow>
    {/if}
    <form class="email-form" onsubmit={requestEmailChange}>
      <SettingRow label={$t('settings.email_new')} labelFor="new-email" layout="stacked">
        <input id="new-email" class="input" type="email" autocomplete="email" dir="ltr" required bind:value={newEmail} />
      </SettingRow>
      <SettingRow label={$t('settings.email_password')} help={$t('settings.email_password_help')} labelFor="email-password" layout="stacked">
        <input id="email-password" class="input" type="password" autocomplete="current-password" required bind:value={emailPassword} />
      </SettingRow>
      <div class="email-actions">
        <button type="submit" class="btn btn-primary btn-sm" disabled={emailSaving || !newEmail.trim() || !emailPassword}>
          {emailSaving ? $t('settings.email_sending') : $t('settings.email_submit')}
        </button>
      </div>
    </form>
  </SettingsSection>

  <SettingsSection title={$t('settings.language_title')} description={$t('settings.language_desc')}>
    <SettingRow label={$t('settings.language_interface')} labelFor="a-locale">
      <select id="a-locale" class="input" value={selectedLocale} onchange={saveLocale} disabled={localeSaving}>
        {#each $availableLocales as loc (loc.code)}
          <option value={loc.code}>{loc.nativeName} ({loc.name})</option>
        {/each}
      </select>
    </SettingRow>
    <SettingRow label={$t('settings.translation_title')} help={$t('settings.translation_desc')} labelFor="a-translate">
      <select id="a-translate" class="input" bind:value={selectedTranslateTarget} onchange={saveTranslateTarget}>
        <option value="">{$t('settings.translation_follow_ui')}</option>
        {#each $availableLocales as loc (loc.code)}
          <option value={loc.code}>{loc.nativeName} ({loc.name})</option>
        {/each}
      </select>
    </SettingRow>
    <SettingRow label={$t('settings.posting_language_title')} help={$t('settings.posting_language_desc')} labelFor="a-posting">
      <select
        id="a-posting"
        class="input"
        value={$preferencesStore.default_language ?? ''}
        onchange={(e) => updatePreferences({ default_language: e.currentTarget.value || null })}
      >
        <option value="">{$t('settings.posting_language_none')}</option>
        {#each $availableLocales as loc (loc.code)}
          <option value={loc.code}>{loc.nativeName} ({loc.name})</option>
        {/each}
      </select>
    </SettingRow>
  </SettingsSection>

  <SettingsSection title={$t('settings.verify_title')} description={$t('settings.verify_desc')}>
    {#if verificationLoading}
      <div class="section-pad verification-loading"><Spinner size={16} /> {$t('settings.verify_checking')}</div>
    {:else if verification.status === 'approved'}
      <SettingRow
        label={$t('settings.verify_verified')}
        help={verification.verified_at ? $t('settings.verify_since', { date: new Date(verification.verified_at).toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' }) }) : ''}
      >
        <VerifiedBadge size="md" />
      </SettingRow>
    {:else if verification.status === 'pending'}
      <SettingRow
        label={verification.type === 'peer_vouch' ? $t('verification.vouch_pending_label') : $t('settings.verify_pending')}
        help={verification.type === 'peer_vouch' ? $t('verification.vouch_pending_detail', { count: verification.vouch_count || 0 }) : $t('settings.verify_pending_help')}
      >
        <span class="pending-dot" aria-hidden="true"></span>
      </SettingRow>
    {:else if !showVerificationForm}
      {#if verificationSuccess}<div class="section-pad form-success">{verificationSuccess}</div>{/if}
      <SettingRow label={$t('settings.verify_apply_label')} help={$t('settings.verify_apply_help')}>
        <button class="btn btn-secondary btn-sm" type="button" onclick={() => (showVerificationForm = true)}>{$t('settings.verify_apply')}</button>
      </SettingRow>
    {:else}
      <SettingRow label={$t('settings.verify_type')} labelFor="verification-type">
        <select id="verification-type" class="input" bind:value={verificationType}>
          <option value="manual">{$t('settings.verify_type_manual')}</option>
          <option value="peer_vouch">{$t('settings.verify_type_vouch')}</option>
        </select>
      </SettingRow>
      <div class="section-pad verification-instructions">
        {#if verificationType === 'peer_vouch'}
          <p>{$t('verification.vouch_intro')}</p>
          <ol>
            <li>{$t('settings.verify_vouch_step_submit')}</li>
            <li>{$t('settings.verify_vouch_step_share')}</li>
            <li>{$t('verification.vouch_step_review')}</li>
          </ol>
        {:else}
          <p>{$t('settings.verify_manual_help')}</p>
        {/if}
        {#if verificationError}<div class="form-error">{verificationError}</div>{/if}
        <div class="section-actions">
          <button class="btn btn-ghost btn-sm" type="button" onclick={() => { showVerificationForm = false; verificationError = ''; }}>{$t('common.cancel')}</button>
          <button class="btn btn-primary btn-sm" type="button" onclick={submitVerification} disabled={verificationSubmitting}>
            {#if verificationSubmitting}<Spinner size={14} />{/if}
            {$t('settings.verify_submit')}
          </button>
        </div>
      </div>
    {/if}
  </SettingsSection>

  <div class="danger-zone">
    <SettingsSection title={$t('settings.delete_title')}>
      <SettingRow label={$t('settings.delete_label')} help={$t('settings.delete_help')}>
        <button class="btn btn-danger btn-sm" type="button" onclick={() => (showDeleteModal = true)}>{$t('settings.delete_button')}</button>
      </SettingRow>
      {#if error}<div class="section-pad form-error">{error}</div>{/if}
    </SettingsSection>
  </div>
</div>

<Modal bind:open={showDeleteModal} title={$t('settings.delete_title')}>
  <div class="delete-modal-content">
    <div class="delete-warning">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--color-danger)" stroke-width="2" aria-hidden="true">
        <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
        <line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>
      </svg>
      <p>{$t('settings.delete_warning')}</p>
    </div>

    <div class="form-group">
      <label class="form-label" for="delete-confirm">{$t('settings.delete_confirm_label')}</label>
      <input id="delete-confirm" type="text" class="input" dir="ltr" bind:value={deleteConfirmText} placeholder="DELETE" autocomplete="off" />
    </div>

    <div class="delete-modal-actions">
      <button class="btn btn-ghost" type="button" onclick={() => { showDeleteModal = false; deleteConfirmText = ''; }}>{$t('common.cancel')}</button>
      <button class="btn btn-danger" type="button" onclick={handleDeleteAccount} disabled={!canDelete || deleting}>
        {#if deleting}<Spinner size={16} color="#fff" />{/if}
        {$t('settings.delete_confirm_button')}
      </button>
    </div>
  </div>
</Modal>

<style>
  .settings-sections {
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .section-pad {
    padding: var(--space-4) var(--space-5);
  }

  .section-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    margin-block-start: var(--space-3);
  }

  .verification-loading {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .verification-instructions {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.5;
  }

  .verification-instructions ol {
    list-style: decimal;
    margin: var(--space-2) 0 0;
    padding-inline-start: var(--space-5);
  }

  .pending-dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--color-warning);
  }

  /* The irreversible action stands apart from the rest. */
  .danger-zone :global(.settings-section) {
    border-color: color-mix(in srgb, var(--color-danger) 35%, var(--color-border));
  }

  .danger-zone :global(.settings-section-title) {
    color: var(--color-danger);
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

  .delete-modal-content {
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .delete-warning {
    display: flex;
    gap: var(--space-3);
    padding: var(--space-4);
    background: var(--color-danger-soft);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: var(--line-height);
  }

  .delete-warning svg {
    flex-shrink: 0;
    margin-block-start: 2px;
  }

  .delete-modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
  }

  .email-current {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    word-break: break-all;
  }

  .email-form {
    display: flex;
    flex-direction: column;
  }

  .email-form > :global(.setting-row + .setting-row) {
    border-block-start: 1px solid var(--color-border);
  }

  .email-actions {
    display: flex;
    justify-content: flex-end;
    padding: 0 var(--space-5) var(--space-4);
  }
</style>
