<script lang="ts">
  import { preferencesStore, updatePreferences } from '$lib/stores/preferences.js';
  import { themeStore, resolvedMode } from '$lib/stores/theme.js';
  import { instanceName } from '$lib/stores/instance.js';
  import { t } from '$lib/stores/i18n.js';
  import SettingsSection from '$lib/components/settings/SettingsSection.svelte';
  import SettingRow from '$lib/components/settings/SettingRow.svelte';
  import Toggle from '$lib/components/ui/Toggle.svelte';
  import type { UserPreferences } from '$lib/api/types.js';

  type Mode = 'auto' | 'light' | 'dark';

  // The instance (admin) default, used when the user hasn't picked a mode.
  let adminDefault = $derived((($themeStore?.mode as Mode) || 'auto') as Mode);

  // What to show as selected: the user's explicit choice, else the admin
  // default. Picking any option makes it an explicit choice.
  let selected = $derived(($preferencesStore.theme_mode ?? adminDefault) as Mode);

  const options: { value: Mode; label: string; desc: string; icon: string }[] = [
    {
      value: 'auto',
      label: 'settings.theme_auto',
      desc: 'settings.theme_auto_desc',
      icon: 'M12 3a9 9 0 1 0 9 9 9 9 0 0 0-9-9zm0 0v18',
    },
    {
      value: 'light',
      label: 'settings.theme_light',
      desc: 'settings.theme_light_desc',
      icon: 'M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z',
    },
    {
      value: 'dark',
      label: 'settings.theme_dark',
      desc: 'settings.theme_dark_desc',
      icon: 'M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z',
    },
  ];

  // Feed & media: saved on change, like the theme.
  let autoplay = $state($preferencesStore.auto_play_media);

  function setHomeTab(e: Event) {
    const value = (e.currentTarget as HTMLSelectElement).value as UserPreferences['feed_algorithm'];
    updatePreferences({ feed_algorithm: value });
  }

  function setReplyLayout(e: Event) {
    const value = (e.currentTarget as HTMLSelectElement).value as UserPreferences['reply_layout'];
    updatePreferences({ reply_layout: value });
  }

  function choose(mode: Mode) {
    // Persists to localStorage + (when signed in) the account preferences in
    // the database; theme.ts re-applies it immediately via its subscription.
    updatePreferences({ theme_mode: mode });
  }
</script>

<div class="appearance-page">
  <SettingsSection title={$t('settings.theme_title')} description={$t('settings.theme_desc', { instance: $instanceName })}>
  <div class="theme-options" role="radiogroup" aria-label={$t('settings.theme_title')}>
    {#each options as opt (opt.value)}
      <button
        type="button"
        role="radio"
        aria-checked={selected === opt.value}
        class="theme-option"
        class:selected={selected === opt.value}
        onclick={() => choose(opt.value)}
      >
        <span class="theme-option-icon" aria-hidden="true">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d={opt.icon} />
          </svg>
        </span>
        <span class="theme-option-text">
          <span class="theme-option-label">{$t(opt.label)}</span>
          <span class="theme-option-desc">{$t(opt.desc)}</span>
        </span>
        <span class="theme-option-check" aria-hidden="true">
          {#if selected === opt.value}
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12" /></svg>
          {/if}
        </span>
      </button>
    {/each}
  </div>

  <p class="appearance-note">
    {$t($resolvedMode === 'dark' ? 'settings.theme_showing_dark' : 'settings.theme_showing_light')}
    {#if $preferencesStore.theme_mode == null}
      {$t('settings.theme_following_default', { mode: $t(`settings.theme_${adminDefault}`) })}
    {/if}
  </p>
  </SettingsSection>

  <SettingsSection title={$t('settings.feed_media_title')} description={$t('settings.feed_media_desc')}>
    <SettingRow label={$t('settings.home_tab_label')} help={$t('settings.home_tab_help')} labelFor="home-tab">
      <select id="home-tab" class="input" value={$preferencesStore.feed_algorithm} onchange={setHomeTab}>
        <option value="chronological">{$t('home.tab_latest')}</option>
        <option value="algorithmic">{$t('home.tab_foryou')}</option>
        <option value="trending">{$t('home.tab_top')}</option>
      </select>
    </SettingRow>
    <SettingRow label={$t('settings.reply_layout_label')} help={$t('settings.reply_layout_help')} labelFor="reply-layout">
      <select id="reply-layout" class="input" value={$preferencesStore.reply_layout} onchange={setReplyLayout}>
        <option value="threaded">{$t('settings.reply_layout_threaded')}</option>
        <option value="flat">{$t('settings.reply_layout_flat')}</option>
      </select>
    </SettingRow>
    <SettingRow label={$t('settings.autoplay_label')} help={$t('settings.autoplay_help')} labelFor="autoplay-media">
      <Toggle id="autoplay-media" bind:checked={autoplay} onchange={(v) => updatePreferences({ auto_play_media: v })} />
    </SettingRow>
  </SettingsSection>
</div>

<style>
  .appearance-page {
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }


  .theme-options {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: var(--space-2);
    padding: var(--space-4) var(--space-5);
  }

  .theme-option {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    width: 100%;
    padding: var(--space-4);
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    cursor: pointer;
    text-align: start;
    transition: border-color 150ms ease, background 150ms ease;
  }

  .theme-option:hover {
    border-color: var(--color-primary);
  }

  .theme-option.selected {
    border-color: var(--color-primary);
    background: var(--color-primary-soft, rgba(var(--color-primary-rgb), 0.08));
  }

  .theme-option-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    flex-shrink: 0;
    border-radius: var(--radius-md);
    background: var(--color-surface-container);
    color: var(--color-primary);
  }

  .theme-option-text {
    display: flex;
    flex-direction: column;
    gap: 2px;
    flex: 1;
    min-width: 0;
  }

  .theme-option-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .theme-option-desc {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .theme-option-check {
    flex-shrink: 0;
    color: var(--color-primary);
  }

  .appearance-note {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin: 0;
    padding: var(--space-3) var(--space-5);
  }
</style>
