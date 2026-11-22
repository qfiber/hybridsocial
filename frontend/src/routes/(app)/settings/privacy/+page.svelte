<script lang="ts">
  // Every control saves on its own as soon as it changes; a failure reverts
  // the control and says so. No page-wide Save button.
  import { onMount } from 'svelte';
  import { currentUser, setUser } from '$lib/stores/auth.js';
  import { updateAccount, getAccount, type InvitePolicy } from '$lib/api/accounts.js';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import { preferencesStore, updatePreferences } from '$lib/stores/preferences.js';
  import { t } from '$lib/stores/i18n.js';
  import Toggle from '$lib/components/ui/Toggle.svelte';
  import SettingsSection from '$lib/components/settings/SettingsSection.svelte';
  import SettingRow from '$lib/components/settings/SettingRow.svelte';
  import { isAutoLoadRemoteMedia, setAutoLoadRemoteMedia } from '$lib/utils/media-preferences.js';

  type DmPolicy = 'everyone' | 'followers' | 'mutual_followers' | 'nobody';

  // Account-level settings, seeded from /auth/me and refreshed below.
  let isLocked = $state($currentUser?.is_locked ?? false);
  let discoverable = $state($currentUser?.discoverable ?? true);
  let allowUnfurl = $state($currentUser?.allow_unfurl ?? true);
  let hideFollowCounts = $state($currentUser?.hide_follow_counts ?? false);
  let allowGroupInvites = $state<InvitePolicy>($currentUser?.allow_group_invites ?? 'anyone');
  let allowPageInvites = $state<InvitePolicy>($currentUser?.allow_page_invites ?? 'anyone');
  let autoDeleteMonths = $state(String($currentUser?.auto_delete_after_months ?? ''));

  let dmPolicy = $state<DmPolicy>('everyone');
  let groupDms = $state(false);
  let dmLoaded = $state(false);

  let autoLoadRemote = $state(true);

  const autoDeleteOptions = Array.from({ length: 12 }, (_, i) => i + 1);
  const invitePolicies: InvitePolicy[] = ['anyone', 'only_follows', 'nobody'];

  onMount(async () => {
    autoLoadRemote = isAutoLoadRemoteMedia();

    const id = $currentUser?.id;
    if (id) {
      try {
        // The cached session can be stale; the account endpoint is current.
        const fresh = await getAccount(id);
        isLocked = fresh.is_locked ?? isLocked;
        discoverable = fresh.discoverable ?? discoverable;
        allowUnfurl = fresh.allow_unfurl ?? allowUnfurl;
        hideFollowCounts = fresh.hide_follow_counts ?? hideFollowCounts;
        if (fresh.auto_delete_after_months !== undefined) {
          autoDeleteMonths = String(fresh.auto_delete_after_months ?? '');
        }
      } catch {
        // Keep the session values.
      }
    }

    try {
      const prefs = await api.get<{ allow_dms_from: DmPolicy; allow_group_dms: boolean }>('/api/v1/dm_preferences');
      dmPolicy = prefs.allow_dms_from || 'everyone';
      groupDms = prefs.allow_group_dms ?? false;
      dmLoaded = true;
    } catch {
      // Don't show "Everyone" as if it were their choice.
      addToast($t('settings.privacy_dm_load_failed'), 'error');
    }
  });

  /** Save one account field; on failure put the old value back. */
  async function saveAccount<K extends keyof Parameters<typeof updateAccount>[0]>(
    field: K,
    value: Parameters<typeof updateAccount>[0][K],
    revert: () => void,
  ) {
    try {
      await updateAccount({ [field]: value });
      if ($currentUser) setUser({ ...$currentUser, [field]: value });
    } catch {
      revert();
      addToast($t('settings.save_failed'), 'error');
    }
  }

  async function saveDm(patch: { allow_dms_from?: DmPolicy; allow_group_dms?: boolean }, revert: () => void) {
    try {
      await api.patch('/api/v1/dm_preferences', patch);
    } catch {
      revert();
      addToast($t('settings.save_failed'), 'error');
    }
  }

  // Toggles bind locally; these react to a change made by the user.
  function onToggle(field: 'is_locked' | 'discoverable' | 'allow_unfurl' | 'hide_follow_counts', value: boolean) {
    saveAccount(field, value, () => {
      if (field === 'is_locked') isLocked = !value;
      else if (field === 'discoverable') discoverable = !value;
      else if (field === 'allow_unfurl') allowUnfurl = !value;
      else hideFollowCounts = !value;
    });
  }

  function onInvite(field: 'allow_group_invites' | 'allow_page_invites', e: Event) {
    const value = (e.currentTarget as HTMLSelectElement).value as InvitePolicy;
    const prev = field === 'allow_group_invites' ? allowGroupInvites : allowPageInvites;
    if (field === 'allow_group_invites') allowGroupInvites = value;
    else allowPageInvites = value;
    saveAccount(field, value, () => {
      if (field === 'allow_group_invites') allowGroupInvites = prev;
      else allowPageInvites = prev;
    });
  }

  function onAutoDelete(e: Event) {
    const prev = autoDeleteMonths;
    autoDeleteMonths = (e.currentTarget as HTMLSelectElement).value;
    saveAccount('auto_delete_after_months', autoDeleteMonths ? Number(autoDeleteMonths) : null, () => (autoDeleteMonths = prev));
  }

  function onDmPolicy(e: Event) {
    const prev = dmPolicy;
    dmPolicy = (e.currentTarget as HTMLSelectElement).value as DmPolicy;
    saveDm({ allow_dms_from: dmPolicy }, () => (dmPolicy = prev));
  }

  function onGroupDms(value: boolean) {
    saveDm({ allow_group_dms: value }, () => (groupDms = !value));
  }

  function onVisibility(e: Event) {
    updatePreferences({ default_visibility: (e.currentTarget as HTMLSelectElement).value as 'public' });
  }
</script>

<div class="privacy-page">
  <SettingsSection title={$t('settings.privacy_profile_title')} description={$t('settings.privacy_profile_desc')}>
    <SettingRow label={$t('settings.privacy_locked')} help={$t('settings.privacy_locked_help')} labelFor="p-locked">
      <Toggle id="p-locked" bind:checked={isLocked} onchange={(v) => onToggle('is_locked', v)} />
    </SettingRow>
    <SettingRow label={$t('settings.privacy_discoverable')} help={$t('settings.privacy_discoverable_help')} labelFor="p-discoverable">
      <Toggle id="p-discoverable" bind:checked={discoverable} onchange={(v) => onToggle('discoverable', v)} />
    </SettingRow>
    <SettingRow label={$t('settings.privacy_unfurl')} help={$t('settings.privacy_unfurl_help')} labelFor="p-unfurl">
      <Toggle id="p-unfurl" bind:checked={allowUnfurl} onchange={(v) => onToggle('allow_unfurl', v)} />
    </SettingRow>
    <SettingRow label={$t('settings.privacy_hide_counts')} help={$t('settings.privacy_hide_counts_help')} labelFor="p-counts">
      <Toggle id="p-counts" bind:checked={hideFollowCounts} onchange={(v) => onToggle('hide_follow_counts', v)} />
    </SettingRow>
  </SettingsSection>

  <SettingsSection title={$t('settings.privacy_posts_title')} description={$t('settings.privacy_posts_desc')}>
    <SettingRow label={$t('settings.privacy_default_visibility')} help={$t('settings.privacy_default_visibility_help')} labelFor="p-visibility">
      <select id="p-visibility" class="input" value={$preferencesStore.default_visibility} onchange={onVisibility}>
        <option value="public">{$t('settings.visibility_public')}</option>
        <option value="followers">{$t('settings.visibility_followers')}</option>
        <option value="direct">{$t('settings.visibility_direct')}</option>
      </select>
    </SettingRow>
    <SettingRow label={$t('settings.privacy_auto_delete')} help={$t('settings.privacy_auto_delete_help')} labelFor="p-autodelete">
      <select id="p-autodelete" class="input" value={autoDeleteMonths} onchange={onAutoDelete}>
        <option value="">{$t('settings.privacy_auto_delete_off')}</option>
        {#each autoDeleteOptions as m (m)}
          <option value={String(m)}>{$t(m === 1 ? 'settings.privacy_auto_delete_after_one' : 'settings.privacy_auto_delete_after_other', { n: m })}</option>
        {/each}
      </select>
    </SettingRow>
  </SettingsSection>

  <SettingsSection title={$t('settings.privacy_messages_title')} description={$t('settings.privacy_messages_desc')}>
    <SettingRow label={$t('settings.privacy_dm_policy')} labelFor="p-dm">
      <select id="p-dm" class="input" value={dmPolicy} onchange={onDmPolicy} disabled={!dmLoaded}>
        <option value="everyone">{$t('settings.dm_everyone')}</option>
        <option value="followers">{$t('settings.dm_followers')}</option>
        <option value="mutual_followers">{$t('settings.dm_mutuals')}</option>
        <option value="nobody">{$t('settings.dm_nobody')}</option>
      </select>
    </SettingRow>
    <SettingRow label={$t('settings.privacy_group_dms')} help={$t('settings.privacy_group_dms_help')} labelFor="p-groupdm">
      <Toggle id="p-groupdm" bind:checked={groupDms} disabled={!dmLoaded} onchange={onGroupDms} />
    </SettingRow>
    <div class="encryption-note">
      <span class="material-symbols-outlined" aria-hidden="true">lock</span>
      <p>{$t('settings.privacy_dm_encryption')}</p>
    </div>
  </SettingsSection>

  <SettingsSection title={$t('settings.privacy_invites_title')} description={$t('settings.privacy_invites_desc')}>
    <SettingRow label={$t('settings.privacy_group_invites')} labelFor="p-ginv">
      <select id="p-ginv" class="input" value={allowGroupInvites} onchange={(e) => onInvite('allow_group_invites', e)}>
        {#each invitePolicies as p (p)}<option value={p}>{$t(`settings.invite_${p}`)}</option>{/each}
      </select>
    </SettingRow>
    <SettingRow label={$t('settings.privacy_page_invites')} labelFor="p-pinv">
      <select id="p-pinv" class="input" value={allowPageInvites} onchange={(e) => onInvite('allow_page_invites', e)}>
        {#each invitePolicies as p (p)}<option value={p}>{$t(`settings.invite_${p}`)}</option>{/each}
      </select>
    </SettingRow>
  </SettingsSection>

  <SettingsSection title={$t('settings.privacy_media_title')}>
    <SettingRow label={$t('settings.privacy_remote_media')} help={$t('settings.privacy_remote_media_help')} labelFor="p-remote">
      <Toggle id="p-remote" bind:checked={autoLoadRemote} onchange={setAutoLoadRemoteMedia} />
    </SettingRow>
  </SettingsSection>
</div>

<style>
  .privacy-page {
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .encryption-note {
    display: flex;
    gap: var(--space-3);
    align-items: flex-start;
    padding: var(--space-4) var(--space-5);
    background: var(--color-surface-container-low);
    font-size: var(--text-xs);
    line-height: 1.5;
    color: var(--color-text-secondary);
  }

  .encryption-note .material-symbols-outlined {
    font-size: 18px;
    color: var(--color-text-tertiary);
  }
</style>
