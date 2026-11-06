<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import AsyncState from '$lib/components/ui/AsyncState.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import { t } from '$lib/stores/i18n.js';
  import {
    getMessageSoundEnabled,
    getNotificationSoundEnabled,
    setMessageSoundEnabled,
    setNotificationSoundEnabled,
  } from '$lib/stores/sound.js';

  interface ChannelPrefs { email: boolean; push: boolean; in_app: boolean }

  const notifTypes = ['follow', 'mention', 'reaction', 'boost', 'poll', 'group_invite'] as const;

  const channels = [
    { key: 'in_app', label: 'In-app' },
    { key: 'email', label: 'Email' },
    { key: 'push', label: 'Push' },
  ] as const;

  const rows = [
    { type: 'follow', name: 'Follows', desc: 'Someone follows you or sends a follow request' },
    { type: 'mention', name: 'Mentions', desc: 'Someone mentions you in a post' },
    { type: 'reaction', name: 'Reactions', desc: 'Someone reacts to your post' },
    { type: 'boost', name: 'Boosts', desc: 'Someone boosts your post' },
    { type: 'poll', name: 'Polls', desc: 'A poll you voted in has ended' },
    { type: 'group_invite', name: 'Group invites', desc: 'Someone invites you to a group' },
  ];

  let prefs = $state<Record<string, ChannelPrefs>>({});
  let loading = $state(true);
  let loadError = $state(false);
  let saving = $state(false);

  // Kept on this device, so these apply at once rather than on Save.
  let notificationSound = $state(getNotificationSoundEnabled());
  let messageSound = $state(getMessageSoundEnabled());

  function pref(type: string): ChannelPrefs {
    return prefs[type] ?? { email: true, push: true, in_app: true };
  }

  function setChannel(type: string, channel: keyof ChannelPrefs, value: boolean) {
    prefs = { ...prefs, [type]: { ...pref(type), [channel]: value } };
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

  onMount(load);

  async function handleSave() {
    if (saving) return;
    saving = true;
    try {
      // Persist exactly what the user chose per channel — no hidden
      // re-enabling of email/push.
      for (const type of notifTypes) {
        const p = pref(type);
        await api.patch('/api/v1/notification_preferences', {
          type,
          email: p.email,
          push: p.push,
          in_app: p.in_app,
        });
      }
      addToast('Notification preferences saved', 'success');
    } catch {
      addToast('Could not save notification preferences', 'error');
    } finally {
      saving = false;
    }
  }
</script>

<div class="stitch-settings">
  <AsyncState
    {loading}
    error={loadError ? 'Could not load your notification preferences.' : ''}
    onretry={load}
  >
    <form class="notif-form" onsubmit={(e) => { e.preventDefault(); handleSave(); }}>
      <p class="notif-intro">Choose how you're notified for each event. Turn any channel on or off.</p>

      <div class="notif-table" role="group" aria-label="Notification preferences">
        <div class="notif-head" aria-hidden="true">
          <span class="notif-head-event">Event</span>
          <span class="notif-head-channels">
            {#each channels as ch (ch.key)}<span>{ch.label}</span>{/each}
          </span>
        </div>

        {#each rows as item (item.type)}
          <div class="notif-row">
            <div class="notif-event">
              <span class="notif-name">{item.name}</span>
              <span class="notif-desc">{item.desc}</span>
            </div>
            <div class="notif-channels">
              {#each channels as ch (ch.key)}
                <label class="notif-toggle">
                  <span class="notif-toggle-label">{ch.label}</span>
                  <input
                    type="checkbox"
                    class="notif-check"
                    checked={pref(item.type)[ch.key]}
                    onchange={(e) => setChannel(item.type, ch.key, (e.target as HTMLInputElement).checked)}
                    aria-label={`${ch.label} notifications for ${item.name}`}
                  />
                </label>
              {/each}
            </div>
          </div>
        {/each}
      </div>

      <div class="notif-sounds" role="group" aria-labelledby="notif-sounds-title">
        <h2 id="notif-sounds-title" class="notif-sounds-title">{$t('settings.sounds_title')}</h2>
        <p class="notif-desc">{$t('settings.sounds_hint')}</p>
        <label class="notif-sound-row">
          <span>{$t('settings.sound_notifications')}</span>
          <input
            type="checkbox"
            class="notif-check"
            bind:checked={notificationSound}
            onchange={() => setNotificationSoundEnabled(notificationSound)}
          />
        </label>
        <label class="notif-sound-row">
          <span>{$t('settings.sound_messages')}</span>
          <input
            type="checkbox"
            class="notif-check"
            bind:checked={messageSound}
            onchange={() => setMessageSoundEnabled(messageSound)}
          />
        </label>
      </div>

      <div class="notif-actions">
        <button class="stitch-btn-primary" type="submit" disabled={saving}>
          {#if saving}<Spinner size={16} color="#fff" />{/if}
          Save changes
        </button>
      </div>
    </form>
  </AsyncState>
</div>

<style>
  .stitch-settings {
    max-width: 720px;
  }

  .notif-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .notif-intro {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .notif-table {
    background: var(--color-surface-container-low);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow: hidden;
  }

  .notif-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-3) var(--space-4);
    border-block-end: 1px solid var(--color-border);
    font-size: var(--text-xs);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-tertiary);
  }

  .notif-head-channels {
    display: flex;
    gap: var(--space-4);
  }

  .notif-head-channels span {
    width: 44px;
    text-align: center;
  }

  .notif-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-4);
    padding: var(--space-3) var(--space-4);
    border-block-end: 1px solid var(--color-border);
  }

  .notif-row:last-child {
    border-block-end: none;
  }

  .notif-event {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .notif-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .notif-desc {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .notif-sounds {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin-block-start: var(--space-5);
  }

  .notif-sounds-title {
    margin: 0;
    font-size: var(--text-base);
    font-weight: 600;
    color: var(--color-text);
  }

  .notif-sound-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-4);
    min-height: 44px;
    color: var(--color-text);
    cursor: pointer;
  }

  .notif-channels {
    display: flex;
    gap: var(--space-4);
    flex-shrink: 0;
  }

  .notif-toggle {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    cursor: pointer;
  }

  /* The header row provides the channel labels on desktop; the per-cell
     label is a screen-reader / small-screen affordance. */
  .notif-toggle-label {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
  }

  .notif-check {
    width: 20px;
    height: 20px;
    accent-color: var(--color-primary);
    cursor: pointer;
  }

  .notif-actions {
    display: flex;
    justify-content: flex-end;
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
    transition: background-color 0.15s ease, transform 0.1s ease;
  }

  .stitch-btn-primary:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .stitch-btn-primary:active:not(:disabled) {
    transform: scale(0.98);
  }

  .stitch-btn-primary:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  @media (max-width: 560px) {
    /* Stack channels under each event with visible labels. */
    .notif-head {
      display: none;
    }

    .notif-row {
      flex-direction: column;
      align-items: stretch;
      gap: var(--space-2);
    }

    .notif-channels {
      justify-content: flex-start;
      gap: var(--space-4);
    }

    .notif-toggle {
      flex-direction: row-reverse;
      gap: 6px;
      width: auto;
    }

    .notif-toggle-label {
      position: static;
      width: auto;
      height: auto;
      clip: auto;
      margin: 0;
      font-size: var(--text-xs);
      color: var(--color-text-secondary);
    }
  }
</style>
