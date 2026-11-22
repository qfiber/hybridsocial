<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { unfollowTag } from '$lib/api/accounts.js';
  import { addToast } from '$lib/stores/toast.js';
  import { reloadFilters } from '$lib/stores/content-filters.js';
  import { t } from '$lib/stores/i18n.js';
  import SettingsSection from '$lib/components/settings/SettingsSection.svelte';
  import SettingRow from '$lib/components/settings/SettingRow.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface ContentFilter {
    phrase: string;
    action: string;
    whole_word: boolean;
  }

  let followed = $state<string[]>([]);
  let muted = $state<string[]>([]);
  let loading = $state(true);
  let followInput = $state('');
  let muteInput = $state('');
  let busy = $state<string | null>(null);

  onMount(async () => {
    try {
      const [tags, filters] = await Promise.all([
        api.get<{ name: string }[]>('/api/v1/accounts/followed_tags'),
        api.get<ContentFilter[]>('/api/v1/accounts/filters'),
      ]);
      followed = tags.map((tag) => tag.name);
      // A tag mute is stored as a whole-word "#name" hide filter (Social.mute_hashtag/2).
      muted = filters
        .filter((f) => f.action === 'hide' && f.whole_word && f.phrase.startsWith('#'))
        .map((f) => f.phrase.slice(1));
    } catch {
      addToast($t('settings.tags_load_failed'), 'error');
    } finally {
      loading = false;
    }
  });

  /** "#News " -> "news"; null when it isn't a usable hashtag. */
  function normalize(raw: string): string | null {
    const name = raw.trim().replace(/^#+/, '').toLowerCase();
    return /^[\p{L}\p{N}_]+$/u.test(name) ? name : null;
  }

  async function run(key: string, fn: () => Promise<unknown>, okKey: string, failKey: string) {
    if (busy) return false;
    busy = key;
    try {
      await fn();
      addToast($t(okKey), 'success');
      return true;
    } catch {
      addToast($t(failKey), 'error');
      return false;
    } finally {
      busy = null;
    }
  }

  async function follow() {
    const name = normalize(followInput);
    if (!name) return addToast($t('settings.tags_invalid'), 'error');
    if (followed.includes(name)) return void (followInput = '');
    const ok = await run('follow', () => api.post('/api/v1/accounts/followed_tags', { name }), 'settings.tags_followed', 'settings.tags_follow_failed');
    if (ok) {
      followed = [...followed, name].sort();
      followInput = '';
    }
  }

  async function unfollow(name: string) {
    const ok = await run(`f:${name}`, () => unfollowTag(name), 'settings.tags_unfollowed', 'settings.tags_unfollow_failed');
    if (ok) followed = followed.filter((n) => n !== name);
  }

  async function mute() {
    const name = normalize(muteInput);
    if (!name) return addToast($t('settings.tags_invalid'), 'error');
    if (muted.includes(name)) return void (muteInput = '');
    const ok = await run('mute', () => api.post(`/api/v1/accounts/muted_tags/${encodeURIComponent(name)}`), 'settings.tags_muted', 'settings.tags_mute_failed');
    if (ok) {
      muted = [name, ...muted];
      muteInput = '';
      reloadFilters();
    }
  }

  async function unmute(name: string) {
    const ok = await run(`m:${name}`, () => api.delete(`/api/v1/accounts/muted_tags/${encodeURIComponent(name)}`), 'settings.tags_unmuted', 'settings.tags_unmute_failed');
    if (ok) {
      muted = muted.filter((n) => n !== name);
      reloadFilters();
    }
  }
</script>

<div class="tags-page">
  <SettingsSection title={$t('settings.tags_followed_title')} description={$t('settings.tags_followed_desc')}>
    <SettingRow label={$t('settings.tags_follow_label')} labelFor="tag-follow" layout="stacked">
      <form class="add-form" onsubmit={(e) => { e.preventDefault(); follow(); }}>
        <input id="tag-follow" type="text" class="input" bind:value={followInput} placeholder={$t('settings.tags_placeholder')} />
        <button type="submit" class="btn btn-primary btn-sm" disabled={!followInput.trim() || busy === 'follow'}>
          {$t('settings.tags_follow')}
        </button>
      </form>
    </SettingRow>
    {#if loading}
      <div class="placeholder"><Spinner /></div>
    {:else if followed.length === 0}
      <p class="placeholder">{$t('settings.tags_followed_empty')}</p>
    {:else}
      {#each followed as name (name)}
        <SettingRow label={`#${name}`}>
          <button type="button" class="btn btn-secondary btn-sm" onclick={() => unfollow(name)} disabled={busy === `f:${name}`}>
            {$t('settings.tags_unfollow')}
          </button>
        </SettingRow>
      {/each}
    {/if}
  </SettingsSection>

  <SettingsSection title={$t('settings.tags_muted_title')} description={$t('settings.tags_muted_desc')}>
    <SettingRow label={$t('settings.tags_mute_label')} labelFor="tag-mute" layout="stacked">
      <form class="add-form" onsubmit={(e) => { e.preventDefault(); mute(); }}>
        <input id="tag-mute" type="text" class="input" bind:value={muteInput} placeholder={$t('settings.tags_placeholder')} />
        <button type="submit" class="btn btn-primary btn-sm" disabled={!muteInput.trim() || busy === 'mute'}>
          {$t('settings.tags_mute')}
        </button>
      </form>
    </SettingRow>
    {#if loading}
      <div class="placeholder"><Spinner /></div>
    {:else if muted.length === 0}
      <p class="placeholder">{$t('settings.tags_muted_empty')}</p>
    {:else}
      {#each muted as name (name)}
        <SettingRow label={`#${name}`}>
          <button type="button" class="btn btn-secondary btn-sm" onclick={() => unmute(name)} disabled={busy === `m:${name}`}>
            {$t('settings.tags_unmute')}
          </button>
        </SettingRow>
      {/each}
    {/if}
  </SettingsSection>
</div>

<style>
  .tags-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .add-form {
    display: flex;
    gap: var(--space-2);
  }

  .add-form .input {
    flex: 1;
    min-width: 0;
  }

  .placeholder {
    margin: 0;
    padding: var(--space-6) var(--space-5);
    text-align: center;
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }
</style>
