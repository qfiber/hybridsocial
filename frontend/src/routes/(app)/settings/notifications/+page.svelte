<script lang="ts">
  // Each switch saves its notification type straight away (one PATCH per
  // type, all three channels), and reverts if the save fails.
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import AsyncState from '$lib/components/ui/AsyncState.svelte';
  import Toggle from '$lib/components/ui/Toggle.svelte';
  import SettingsSection from '$lib/components/settings/SettingsSection.svelte';
  import SettingRow from '$lib/components/settings/SettingRow.svelte';
  import { t } from '$lib/stores/i18n.js';
  import PushOptIn from '$lib/components/notification/PushOptIn.svelte';
  import { preferencesStore, updatePreferences } from '$lib/stores/preferences.js';
  import type { UserPreferences } from '$lib/api/types.js';
  import {
    getMessageSoundEnabled,
    getNotificationSoundEnabled,
    setMessageSoundEnabled,
    setNotificationSoundEnabled,
  } from '$lib/stores/sound.js';

  interface ChannelPrefs { email: boolean; push: boolean; in_app: boolean }
  type Channel = keyof ChannelPrefs;

  // Types a member can receive (Preference @valid_types minus staff-only
  // report/admin, which are #319).
  const groups = [
    { titleKey: 'settings.notif_group_people', types: ['follow', 'follow_request', 'mention', 'reply', 'quote'] },
    { titleKey: 'settings.notif_group_engagement', types: ['reaction', 'boost', 'poll_ended'] },
    { titleKey: 'settings.notif_group_communities', types: ['group_invite', 'group_application', 'page_invite'] },
  ];
  const channels: Channel[] = ['in_app', 'email', 'push'];

  // Staff email alerts (#319). The server includes these only for staff, so
  // their presence is the gate; they are email-only.
  const staffTypes = ['admin_new_report', 'admin_new_appeal', 'admin_pending_account', 'moderation_queue', 'admin_backup_failed'];
  let shownStaffTypes = $derived(staffTypes.filter((type) => type in prefs));

  let prefs = $state<Record<string, ChannelPrefs>>({});
  let loading = $state(true);
  let loadError = $state(false);

  // Device-only, applied at once.
  let notificationSound = $state(getNotificationSoundEnabled());
  let messageSound = $state(getMessageSoundEnabled());

  // Server default for a type with no stored row (notifications.ex).
  function pref(type: string): ChannelPrefs {
    return prefs[type] ?? { email: false, push: true, in_app: true };
  }

  async function load() {
    loading = true;
    loadError = false;
    try {
      prefs = await api.get<Record<string, ChannelPrefs>>('/api/v1/notification_preferences');
    } catch {
      loadError = true;
    } finally {
      loading = false;
    }
  }

  // Digest email (#318): offered only while the instance switch is on.
  let digestEnabled = $state(false);

  async function loadDigestAvailability() {
    try {
      const info = await api.get<{ notification_digest_enabled?: boolean }>('/api/v1/instance/info');
      digestEnabled = !!info.notification_digest_enabled;
    } catch {
      digestEnabled = false;
    }
  }

  function setDigest(e: Event) {
    const value = (e.currentTarget as HTMLSelectElement).value as UserPreferences['notification_digest'];
    updatePreferences({ notification_digest: value });
  }

  onMount(() => {
    load();
    loadDigestAvailability();
  });

  async function setChannel(type: string, channel: Channel, value: boolean) {
    const before = pref(type);
    const next = { ...before, [channel]: value };
    prefs = { ...prefs, [type]: next };
    try {
      await api.patch('/api/v1/notification_preferences', { type, ...next });
    } catch {
      prefs = { ...prefs, [type]: before };
      addToast($t('settings.notif_save_failed'), 'error');
    }
  }
</script>

<div class="notif-page">
  <SettingsSection title={$t('settings.notif_device_title')} description={$t('settings.notif_device_desc')}>
    <div class="notif-device"><PushOptIn /></div>
  </SettingsSection>

  <AsyncState {loading} error={loadError ? $t('settings.notif_load_failed') : ''} onretry={load}>
    <div class="notif-groups">
      <p class="notif-intro">{$t('settings.notif_intro')}</p>
      {#each groups as group (group.titleKey)}
        <SettingsSection title={$t(group.titleKey)}>
          {#each group.types as type (type)}
            {@const name = $t(`settings.notif_${type}`)}
            <SettingRow label={name} help={$t(`settings.notif_${type}_desc`)}>
              <div class="channel-switches" role="group" aria-label={name}>
                {#each channels as ch (ch)}
                  <div class="channel">
                    <label class="channel-name" for={`n-${type}-${ch}`}>{$t(`settings.notif_channel_${ch}`)}</label>
                    <Toggle
                      checked={pref(type)[ch]}
                      onchange={(v) => setChannel(type, ch, v)}
                      id={`n-${type}-${ch}`}
                    />
                  </div>
                {/each}
              </div>
            </SettingRow>
          {/each}
        </SettingsSection>
      {/each}
    </div>
  </AsyncState>

  {#if digestEnabled}
    <SettingsSection title={$t('settings.notif_digest_title')} description={$t('settings.notif_digest_desc')}>
      <SettingRow label={$t('settings.notif_digest_label')} help={$t('settings.notif_digest_help')} labelFor="n-digest">
        <select id="n-digest" class="input" value={$preferencesStore.notification_digest ?? 'off'} onchange={setDigest}>
          <option value="off">{$t('settings.notif_digest_off')}</option>
          <option value="daily">{$t('settings.notif_digest_daily')}</option>
          <option value="weekly">{$t('settings.notif_digest_weekly')}</option>
        </select>
      </SettingRow>
    </SettingsSection>
  {/if}

  {#if shownStaffTypes.length}
    <SettingsSection title={$t('settings.notif_staff_title')} description={$t('settings.notif_staff_desc')}>
      {#each shownStaffTypes as type (type)}
        <SettingRow label={$t(`settings.notif_${type}`)} help={$t(`settings.notif_${type}_desc`)} labelFor={`n-${type}-email`}>
          <Toggle id={`n-${type}-email`} checked={pref(type).email} onchange={(v) => setChannel(type, 'email', v)} />
        </SettingRow>
      {/each}
    </SettingsSection>
  {/if}

  <SettingsSection title={$t('settings.sounds_title')} description={$t('settings.sounds_hint')}>
    <SettingRow label={$t('settings.sound_notifications')} labelFor="n-sound">
      <Toggle id="n-sound" bind:checked={notificationSound} onchange={setNotificationSoundEnabled} />
    </SettingRow>
    <SettingRow label={$t('settings.sound_messages')} labelFor="n-sound-dm">
      <Toggle id="n-sound-dm" bind:checked={messageSound} onchange={setMessageSoundEnabled} />
    </SettingRow>
  </SettingsSection>
</div>

<style>
  .notif-page,
  .notif-groups {
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .notif-device {
    padding: var(--space-4) var(--space-5);
  }

  .notif-intro {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .channel-switches {
    display: flex;
    gap: var(--space-4);
  }

  .channel {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    min-width: 52px;
  }

  .channel-name {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-tertiary);
  }

  /* Narrow: the switches sit under the label (SettingRow stacks); keep them
     on the start side in a compact row. */
  @media (max-width: 560px) {
    .channel-switches {
      justify-content: flex-start;
    }
  }
</style>
