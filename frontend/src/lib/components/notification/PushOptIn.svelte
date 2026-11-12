<script lang="ts">
  import { onMount } from 'svelte';
  import Button from '$lib/components/ui/Button.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { t } from '$lib/stores/i18n.js';
  import {
    enablePush,
    isPushSubscribed,
    pushState,
    unsubscribeFromPush,
    type PushState,
  } from '$lib/utils/push.js';

  // Turning on push notifications for this device, always from a click (the
  // browser prompt is never shown unasked — see utils/push.ts).
  // - `settings`: the full control in Settings → Notifications (status, on/off,
  //   and why it's unavailable when it is);
  // - `banner`: a one-line, dismissible suggestion on the Notifications page,
  //   shown only while the browser hasn't been asked yet.
  let { variant = 'settings' }: { variant?: 'settings' | 'banner' } = $props();

  const DISMISS_KEY = 'hs-push-banner-dismissed';

  let pushStatus = $state<PushState>('unsupported');
  let subscribed = $state(false);
  let busy = $state(false);
  let dismissed = $state(true);
  let ready = $state(false);

  onMount(async () => {
    pushStatus = pushState();
    subscribed = await isPushSubscribed();
    try {
      dismissed = localStorage.getItem(DISMISS_KEY) === '1';
    } catch {
      dismissed = false;
    }
    ready = true;
  });

  async function turnOn() {
    if (busy) return;
    busy = true;
    try {
      pushStatus = await enablePush();
      subscribed = pushStatus === 'granted' && (await isPushSubscribed());
      if (subscribed) addToast($t('push.enabled_toast'), 'success');
      else if (pushStatus === 'default') addToast($t('push.failed'), 'error');
    } finally {
      busy = false;
    }
  }

  async function turnOff() {
    if (busy) return;
    busy = true;
    try {
      await unsubscribeFromPush();
      subscribed = await isPushSubscribed();
      if (!subscribed) addToast($t('push.disabled_toast'), 'success');
    } finally {
      busy = false;
    }
  }

  function dismiss() {
    dismissed = true;
    try {
      localStorage.setItem(DISMISS_KEY, '1');
    } catch {
      /* storage unavailable — it just shows again next visit */
    }
  }

  let showBanner = $derived(ready && !dismissed && pushStatus === 'default');
</script>

{#if variant === 'banner'}
  {#if showBanner}
    <div class="push-banner" role="region" aria-label={$t('push.device_title')}>
      <span class="material-symbols-outlined push-banner-icon" aria-hidden="true">notifications_active</span>
      <p class="push-banner-text">{$t('push.banner_text')}</p>
      <div class="push-banner-actions">
        <Button size="sm" loading={busy} onclick={turnOn}>{$t('push.enable')}</Button>
        <Button size="sm" variant="ghost" onclick={dismiss}>{$t('push.not_now')}</Button>
      </div>
    </div>
  {/if}
{:else if ready}
  <div class="push-settings" role="group" aria-labelledby="push-settings-title">
    <h2 id="push-settings-title" class="push-settings-title">{$t('push.device_title')}</h2>
    <p class="push-settings-hint">{$t('push.device_hint')}</p>

    {#if pushStatus === 'unsupported'}
      <p class="push-settings-note">{$t('push.unsupported')}</p>
    {:else if pushStatus === 'ios-install'}
      <p class="push-settings-note">{$t('push.ios_install')}</p>
    {:else if pushStatus === 'denied'}
      <p class="push-settings-note">{$t('push.denied')}</p>
    {:else}
      <div class="push-settings-row">
        <span class="push-settings-status" class:on={subscribed}>
          {subscribed ? $t('push.status_on') : $t('push.status_off')}
        </span>
        {#if subscribed}
          <Button size="sm" variant="outline" loading={busy} onclick={turnOff}>{$t('push.disable')}</Button>
        {:else}
          <Button size="sm" loading={busy} onclick={turnOn}>{$t('push.enable')}</Button>
        {/if}
      </div>
    {/if}
  </div>
{/if}

<style>
  .push-banner {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    background: var(--color-surface-raised);
    margin-block-end: var(--space-4);
  }

  .push-banner-icon {
    color: var(--color-primary);
    font-size: 22px;
  }

  .push-banner-text {
    flex: 1 1 220px;
    margin: 0;
    font-size: var(--text-sm);
    color: var(--color-text);
  }

  .push-banner-actions {
    display: flex;
    gap: var(--space-2);
  }

  .push-settings {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .push-settings-title {
    margin: 0;
    font-size: var(--text-base);
    font-weight: 600;
    color: var(--color-text);
  }

  .push-settings-hint,
  .push-settings-note {
    margin: 0;
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .push-settings-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-4);
    min-height: 44px;
  }

  .push-settings-status {
    color: var(--color-text-secondary);
  }

  .push-settings-status.on {
    color: var(--color-text);
    font-weight: 600;
  }
</style>
