<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import { t } from '$lib/stores/i18n.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import SettingsSection from '$lib/components/settings/SettingsSection.svelte';

  interface ListedAccount {
    id: string;
    handle: string;
    acct?: string;
    display_name: string;
    avatar_url: string | null;
    muted_until?: string | null;
  }

  let blocked = $state<ListedAccount[]>([]);
  let muted = $state<ListedAccount[]>([]);
  let domains = $state<string[]>([]);
  let loading = $state({ blocked: true, muted: true, domains: true });
  let busy = $state<string | null>(null);
  let newDomain = $state('');

  onMount(() => {
    load('blocked', '/api/v1/accounts/blocks', (r: ListedAccount[]) => (blocked = r), 'settings.blocks_load_failed');
    load('muted', '/api/v1/accounts/mutes', (r: ListedAccount[]) => (muted = r), 'settings.mutes_load_failed');
    load('domains', '/api/v1/accounts/domain_blocks', (r: { domain: string }[]) => (domains = r.map((b) => b.domain)), 'settings.domains_load_failed');
  });

  async function load<T>(key: keyof typeof loading, url: string, set: (r: T[]) => void, failKey: string) {
    try {
      const res = await api.get<T[]>(url);
      set(Array.isArray(res) ? res : []);
    } catch {
      addToast($t(failKey), 'error');
    } finally {
      loading[key] = false;
    }
  }

  /** Run a list action, remove the row on success, toast either way. */
  async function act(id: string, call: () => Promise<unknown>, onDone: () => void, okKey: string, failKey: string, params = {}) {
    busy = id;
    try {
      await call();
      onDone();
      addToast($t(okKey, params), 'success');
    } catch {
      addToast($t(failKey, params), 'error');
    } finally {
      busy = null;
    }
  }

  const name = (a: ListedAccount) => a.display_name || a.handle;
  const acct = (a: ListedAccount) => a.acct || a.handle;

  function unblock(a: ListedAccount) {
    act(`b:${a.id}`, () => api.post(`/api/v1/accounts/${a.id}/unblock`), () => (blocked = blocked.filter((x) => x.id !== a.id)), 'settings.blocks_unblocked', 'settings.blocks_unblock_failed', { handle: acct(a) });
  }

  function unmute(a: ListedAccount) {
    act(`m:${a.id}`, () => api.post(`/api/v1/accounts/${a.id}/unmute`), () => (muted = muted.filter((x) => x.id !== a.id)), 'settings.mutes_unmuted', 'settings.mutes_unmute_failed', { handle: acct(a) });
  }

  function removeDomain(domain: string) {
    act(`d:${domain}`, () => api.delete('/api/v1/accounts/domain_blocks', { domain }), () => (domains = domains.filter((d) => d !== domain)), 'settings.domains_unblocked', 'settings.domains_unblock_failed', { domain });
  }

  function addDomain(e: SubmitEvent) {
    e.preventDefault();
    // Accept a pasted URL or @user@host too; keep just the host.
    const domain = newDomain.trim().toLowerCase().replace(/^https?:\/\//, '').replace(/^.*@/, '').replace(/\/.*$/, '');
    if (!domain || domains.includes(domain)) return void (newDomain = '');
    act('add', () => api.post('/api/v1/accounts/domain_blocks', { domain }), () => { domains = [...domains, domain]; newDomain = ''; }, 'settings.domains_blocked', 'settings.domains_block_failed', { domain });
  }

  function muteExpiry(iso: string | null | undefined): string {
    if (!iso) return $t('settings.mutes_indefinite');
    const date = new Date(iso);
    if (date.getTime() <= Date.now()) return $t('settings.mutes_expired');
    return $t('settings.mutes_until', { date: date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' }) });
  }
</script>

{#snippet accountRow(a: ListedAccount, meta: string, actionLabel: string, onAction: () => void, busyKey: string)}
  <div class="list-row">
    <a href="/@{acct(a)}" class="who">
      <Avatar src={a.avatar_url} name={name(a)} size="sm" />
      <span class="who-text">
        <span class="who-name">{name(a)}</span>
        <span class="who-handle" dir="ltr">@{acct(a)}{meta ? ` · ${meta}` : ''}</span>
      </span>
    </a>
    <button type="button" class="btn btn-secondary btn-sm" onclick={onAction} disabled={busy === busyKey}>
      {#if busy === busyKey}<Spinner size={14} />{/if}
      {actionLabel}
    </button>
  </div>
{/snippet}

<div class="blocks-page">
  <SettingsSection title={$t('settings.blocks_title')} description={$t('settings.blocks_desc')}>
    {#if loading.blocked}
      <div class="placeholder"><Spinner size={18} /></div>
    {:else if blocked.length === 0}
      <p class="placeholder">{$t('settings.blocks_empty')}</p>
    {:else}
      {#each blocked as a (a.id)}
        {@render accountRow(a, '', $t('settings.blocks_unblock'), () => unblock(a), `b:${a.id}`)}
      {/each}
    {/if}
  </SettingsSection>

  <SettingsSection title={$t('settings.mutes_title')} description={$t('settings.mutes_desc')}>
    {#if loading.muted}
      <div class="placeholder"><Spinner size={18} /></div>
    {:else if muted.length === 0}
      <p class="placeholder">{$t('settings.mutes_empty')}</p>
    {:else}
      {#each muted as a (a.id)}
        {@render accountRow(a, muteExpiry(a.muted_until), $t('settings.mutes_unmute'), () => unmute(a), `m:${a.id}`)}
      {/each}
    {/if}
  </SettingsSection>

  <SettingsSection title={$t('settings.domains_title')} description={$t('settings.domains_desc')}>
    <form class="add-row" onsubmit={addDomain}>
      <label class="visually-hidden" for="block-domain">{$t('settings.domains_add_label')}</label>
      <input id="block-domain" class="input" type="text" dir="ltr" autocomplete="off" placeholder="example.social" bind:value={newDomain} />
      <button type="submit" class="btn btn-primary btn-sm" disabled={!newDomain.trim() || busy === 'add'}>
        {#if busy === 'add'}<Spinner size={14} />{/if}
        {$t('settings.domains_add')}
      </button>
    </form>
    {#if loading.domains}
      <div class="placeholder"><Spinner size={18} /></div>
    {:else if domains.length === 0}
      <p class="placeholder">{$t('settings.domains_empty')}</p>
    {:else}
      {#each domains as d (d)}
        <div class="list-row">
          <span class="domain" dir="ltr">{d}</span>
          <button type="button" class="btn btn-secondary btn-sm" onclick={() => removeDomain(d)} disabled={busy === `d:${d}`}>
            {#if busy === `d:${d}`}<Spinner size={14} />{/if}
            {$t('settings.domains_unblock')}
          </button>
        </div>
      {/each}
    {/if}
  </SettingsSection>
</div>

<style>
  .blocks-page {
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .list-row,
  .add-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-5);
  }

  .add-row .input {
    flex: 1;
    min-width: 0;
  }

  .who {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    min-width: 0;
    color: var(--color-text);
    text-decoration: none;
  }

  .who:hover .who-name {
    text-decoration: underline;
  }

  .who-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .who-name {
    font-size: var(--text-sm);
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .who-handle {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    text-align: start;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .domain {
    font-size: var(--text-sm);
    font-weight: 600;
    word-break: break-all;
  }

  .placeholder {
    display: flex;
    justify-content: center;
    padding: var(--space-5);
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }
</style>
