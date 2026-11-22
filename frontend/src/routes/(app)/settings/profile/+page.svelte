<script lang="ts">
  import { get } from 'svelte/store';
  import { onMount } from 'svelte';
  import { authStore, setUser, currentUser } from '$lib/stores/auth.js';
  import { updateAccount, updateAvatar, updateHeader } from '$lib/api/accounts.js';
  import { getCurrentUser } from '$lib/api/auth.js';
  import { t } from '$lib/stores/i18n.js';
  import { t as tr, tError } from '$lib/utils/i18n.js';
  import { addToast } from '$lib/stores/toast.js';
  import type { Identity } from '$lib/api/types.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import Toggle from '$lib/components/ui/Toggle.svelte';
  import SettingsSection from '$lib/components/settings/SettingsSection.svelte';
  import SettingRow from '$lib/components/settings/SettingRow.svelte';

  const DISPLAY_NAME_MAX = 50;
  const BIO_MAX = 500;

  let avatarUploading = $state(false);
  let headerUploading = $state(false);

  let displayName = $state('');
  let bio = $state('');
  let handle = $state('');
  let avatarUrl: string | null = $state(null);
  let headerUrl: string | null = $state(null);
  let showBadge = $state(true);
  let birthday = $state('');
  let location = $state('');
  // Free-form fields user can publish on their profile (Twitter/Mastodon
  // "links + facts" section). Per-tier cap from currentUser.limits;
  // free tier gets 0 (editor hidden), starter 2, creator 5, pro 10.
  let profileFields = $state<{ name: string; value: string }[]>([]);
  let profileFieldsMax = $derived(($currentUser?.limits as { profile_fields?: number } | undefined)?.profile_fields ?? 0);
  let saving = $state(false);
  let avatarInput: HTMLInputElement | undefined = $state();
  let headerInput: HTMLInputElement | undefined = $state();

  // Snapshot of the form as last loaded/saved; Save stays off until it differs.
  let savedSnapshot = $state('');
  let formSnapshot = $derived(JSON.stringify({ displayName, bio, showBadge, birthday, location, profileFields }));
  let dirty = $derived(formSnapshot !== savedSnapshot);

  function populate(u: Identity) {
    displayName = u.display_name || '';
    bio = u.bio || '';
    handle = u.handle;
    avatarUrl = u.avatar_url;
    headerUrl = u.header_url;
    showBadge = (u as any).show_badge !== false;
    birthday = u.birthday || '';
    location = u.location || '';
    profileFields = (u.profile_fields ?? []).map((f) => ({ name: f.name, value: f.value }));
    savedSnapshot = JSON.stringify({ displayName, bio, showBadge, birthday, location, profileFields });
  }

  onMount(async () => {
    // Show cached values instantly (no empty flash), then refresh from
    // the server so edits made on another device aren't overwritten with
    // a stale snapshot.
    const cached = get(authStore).user;
    if (cached) populate(cached);
    try {
      const fresh = await getCurrentUser();
      setUser(fresh);
      populate(fresh);
    } catch {
      // Keep cached values.
    }
  });

  function addProfileField() {
    if (profileFields.length >= profileFieldsMax) return;
    profileFields = [...profileFields, { name: '', value: '' }];
  }

  function removeProfileField(i: number) {
    profileFields = profileFields.filter((_, idx) => idx !== i);
  }

  async function handleSave() {
    if (saving || !dirty) return;
    saving = true;
    try {
      const cleanedFields = profileFields
        .map((f) => ({ name: f.name.trim(), value: f.value.trim() }))
        .filter((f) => f.name !== '' || f.value !== '')
        .slice(0, profileFieldsMax);

      const updated = await updateAccount({
        display_name: displayName,
        bio,
        show_badge: showBadge,
        // Empty strings → null so the row clears, not stores ''.
        birthday: birthday.trim() === '' ? null : birthday,
        location: location.trim() === '' ? null : location,
        profile_fields: cleanedFields,
      });
      setUser(updated);
      populate(updated);
      addToast(tr('settings.profile_saved'), 'success');
    } catch (e) {
      addToast(e instanceof Error ? e.message : tr('settings.profile_save_failed'), 'error');
    } finally {
      saving = false;
    }
  }

  async function handleAvatarChange(e: Event) {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file || avatarUploading) return;
    avatarUploading = true;
    try {
      const updated = await updateAvatar(file);
      avatarUrl = updated.avatar_url;
      setUser(updated);
      addToast(tr('settings.profile_avatar_updated'), 'success');
    } catch (err) {
      addToast(err instanceof Error ? tError(err.message) : tError('media.upload_failed'), 'error');
    } finally {
      avatarUploading = false;
      input.value = '';
    }
  }

  async function handleHeaderChange(e: Event) {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file || headerUploading) return;
    headerUploading = true;
    try {
      const updated = await updateHeader(file);
      headerUrl = updated.header_url;
      setUser(updated);
      addToast(tr('settings.profile_header_updated'), 'success');
    } catch (err) {
      addToast(err instanceof Error ? tError(err.message) : tError('media.upload_failed'), 'error');
    } finally {
      headerUploading = false;
      input.value = '';
    }
  }

  function handleDiscard() {
    const u = get(authStore).user;
    if (u) populate(u);
  }
</script>

{#snippet cameraIcon()}
  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
    <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/>
  </svg>
{/snippet}

<form class="profile-page" onsubmit={(e) => { e.preventDefault(); handleSave(); }}>
  <SettingsSection title={$t('settings.profile_pictures_title')} description={$t('settings.profile_pictures_desc')}>
    <div class="pictures">
      <button
        type="button"
        class="header-btn"
        class:busy={headerUploading}
        onclick={() => headerInput?.click()}
        disabled={headerUploading}
        aria-label={$t('settings.profile_change_header')}
      >
        <img src={headerUrl || '/images/default-cover.svg'} alt="" class="header-img" />
        <span class="overlay">
          {#if headerUploading}<Spinner size={22} color="#fff" />{:else}{@render cameraIcon()}{/if}
        </span>
      </button>
      <input bind:this={headerInput} type="file" accept="image/*" class="visually-hidden" onchange={handleHeaderChange} />

      <div class="pictures-bar">
        <button
          type="button"
          class="avatar-btn"
          class:busy={avatarUploading}
          onclick={() => avatarInput?.click()}
          disabled={avatarUploading}
          aria-label={$t('settings.profile_change_avatar')}
        >
          <Avatar src={avatarUrl} name={displayName || handle} size="xl" />
          <span class="overlay">
            {#if avatarUploading}<Spinner size={20} color="#fff" />{:else}{@render cameraIcon()}{/if}
          </span>
        </button>
        <input bind:this={avatarInput} type="file" accept="image/*" class="visually-hidden" onchange={handleAvatarChange} />
        {#if handle}
          <a class="btn btn-secondary btn-sm" href="/@{handle}">{$t('settings.view_profile')}</a>
        {/if}
      </div>
    </div>
  </SettingsSection>

  <SettingsSection title={$t('settings.profile_basics_title')} description={$t('settings.profile_basics_desc')}>
    <SettingRow label={$t('settings.profile_display_name')} labelFor="display-name" layout="stacked">
      <div class="field">
        <input
          id="display-name"
          type="text"
          class="input"
          bind:value={displayName}
          placeholder={$t('settings.profile_display_name_placeholder')}
          maxlength={DISPLAY_NAME_MAX}
        />
        <span class="counter" dir="ltr">{displayName.length}/{DISPLAY_NAME_MAX}</span>
      </div>
    </SettingRow>
    <SettingRow label={$t('settings.profile_bio')} labelFor="bio" layout="stacked">
      <div class="field">
        <textarea
          id="bio"
          class="input textarea"
          bind:value={bio}
          placeholder={$t('settings.profile_bio_placeholder')}
          maxlength={BIO_MAX}
          rows="4"
        ></textarea>
        <span class="counter" dir="ltr">{bio.length}/{BIO_MAX}</span>
      </div>
    </SettingRow>
    <SettingRow label={$t('settings.profile_handle')} help={$t('settings.profile_handle_help')} labelFor="handle" layout="stacked">
      <input id="handle" type="text" class="input" dir="ltr" value={handle} disabled />
    </SettingRow>
  </SettingsSection>

  <SettingsSection title={$t('settings.profile_details_title')} description={$t('settings.profile_details_desc')}>
    <SettingRow label={$t('settings.profile_location')} labelFor="location" layout="stacked">
      <input
        id="location"
        type="text"
        class="input"
        bind:value={location}
        placeholder={$t('settings.profile_location_placeholder')}
        maxlength="100"
      />
    </SettingRow>
    <SettingRow label={$t('settings.profile_birthday')} help={$t('settings.profile_birthday_help')} labelFor="birthday" layout="stacked">
      <input id="birthday" type="date" class="input" bind:value={birthday} />
    </SettingRow>
  </SettingsSection>

  <SettingsSection title={$t('settings.profile_fields_title')} description={$t('settings.profile_fields_desc')}>
    {#if profileFieldsMax > 0}
      <div class="fields">
        <p class="fields-used">{$t('settings.profile_fields_used', { used: profileFields.length, max: profileFieldsMax })}</p>
        {#each profileFields as field, i (i)}
          <div class="fields-row">
            <input
              type="text"
              class="input fields-name"
              placeholder={$t('settings.profile_fields_label_placeholder')}
              aria-label={$t('settings.profile_fields_label_placeholder')}
              maxlength="60"
              bind:value={field.name}
            />
            <input
              type="text"
              class="input fields-value"
              placeholder={$t('settings.profile_fields_value_placeholder')}
              aria-label={$t('settings.profile_fields_value_placeholder')}
              maxlength="280"
              bind:value={field.value}
            />
            <button
              type="button"
              class="btn btn-ghost btn-sm fields-remove"
              onclick={() => removeProfileField(i)}
              aria-label={$t('settings.profile_fields_remove')}
              title={$t('settings.profile_fields_remove')}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" /></svg>
            </button>
          </div>
        {/each}
        {#if profileFields.length < profileFieldsMax}
          <button type="button" class="btn btn-secondary btn-sm fields-add" onclick={addProfileField}>
            + {$t('settings.profile_fields_add')}
          </button>
        {/if}
      </div>
    {:else}
      <p class="fields-upgrade">{$t('settings.profile_fields_upgrade')}</p>
    {/if}
  </SettingsSection>

  <SettingsSection title={$t('settings.profile_badge_title')}>
    <SettingRow label={$t('settings.profile_badge_label')} help={$t('settings.profile_badge_help')} labelFor="show-badge">
      <Toggle id="show-badge" bind:checked={showBadge} />
    </SettingRow>
  </SettingsSection>

  <div class="actions" class:dirty>
    <span class="actions-status" aria-live="polite">
      {dirty ? $t('settings.profile_unsaved') : $t('settings.profile_all_saved')}
    </span>
    <div class="actions-buttons">
      <button class="btn btn-ghost" type="button" onclick={handleDiscard} disabled={!dirty || saving}>
        {$t('settings.profile_discard')}
      </button>
      <button class="btn btn-primary" type="submit" disabled={!dirty || saving}>
        {#if saving}<Spinner size={16} color="#fff" />{/if}
        {$t('settings.profile_save')}
      </button>
    </div>
  </div>
</form>

<style>
  .profile-page {
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  /* ---- Pictures: header with the avatar overlapping its lower edge ---- */
  .header-btn {
    position: relative;
    display: block;
    width: 100%;
    height: 160px;
    padding: 0;
    border: none;
    overflow: hidden;
    cursor: pointer;
    background: var(--color-surface-container-high);
  }

  .header-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .overlay {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--scrim-medium);
    color: white;
    opacity: 0;
    transition: opacity 0.2s ease;
  }

  .avatar-btn .overlay {
    border-radius: 50%;
  }

  .header-btn:hover .overlay,
  .header-btn:focus-visible .overlay,
  .avatar-btn:hover .overlay,
  .avatar-btn:focus-visible .overlay,
  .busy .overlay {
    opacity: 1;
  }

  .busy {
    cursor: default;
  }

  .pictures-bar {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    gap: var(--space-3);
    padding: 0 var(--space-5) var(--space-4);
    margin-block-start: -48px;
  }

  .avatar-btn {
    position: relative;
    display: block;
    padding: 0;
    border: none;
    border-radius: 50%;
    background: none;
    cursor: pointer;
  }

  .avatar-btn :global(.avatar) {
    width: 96px !important;
    height: 96px !important;
    border: 4px solid var(--color-surface-raised);
    border-radius: 50%;
    box-shadow: var(--shadow-md);
  }

  /* ---- Text fields ---- */
  .field {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .textarea {
    resize: vertical;
    font-family: inherit;
  }

  .counter {
    align-self: flex-end;
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  /* ---- Profile fields ---- */
  .fields {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding: var(--space-4) var(--space-5);
  }

  .fields-used,
  .fields-upgrade {
    margin: 0;
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .fields-upgrade {
    padding: var(--space-4) var(--space-5);
  }

  .fields-row {
    display: flex;
    gap: var(--space-2);
    align-items: center;
  }

  .fields-name {
    flex: 0 0 32%;
    min-width: 0;
  }

  .fields-value {
    flex: 1;
    min-width: 0;
  }

  .fields-remove {
    flex-shrink: 0;
  }

  .fields-add {
    align-self: flex-start;
  }

  /* ---- Save bar: sticks to the bottom while the form scrolls ---- */
  .actions {
    position: sticky;
    inset-block-end: var(--space-3);
    z-index: 2;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
  }

  .actions.dirty {
    border-color: var(--color-primary);
    box-shadow: var(--shadow-md);
  }

  .actions-status {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .actions-buttons {
    display: flex;
    gap: var(--space-2);
  }

  @media (max-width: 560px) {
    .header-btn {
      height: 120px;
    }

    .pictures-bar {
      margin-block-start: -40px;
    }

    .avatar-btn :global(.avatar) {
      width: 80px !important;
      height: 80px !important;
    }

    .actions {
      flex-direction: column;
      align-items: stretch;
    }

    .actions-buttons > * {
      flex: 1;
      justify-content: center;
    }
  }
</style>
