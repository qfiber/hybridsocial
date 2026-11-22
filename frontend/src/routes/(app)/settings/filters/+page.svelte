<script lang="ts">
  import { onMount } from 'svelte';
  import { api, ApiError } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import { reloadFilters } from '$lib/stores/content-filters.js';
  import { t, locale } from '$lib/stores/i18n.js';
  import SettingsSection from '$lib/components/settings/SettingsSection.svelte';
  import SettingRow from '$lib/components/settings/SettingRow.svelte';
  import Toggle from '$lib/components/ui/Toggle.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface ContentFilter {
    id: string;
    phrase: string;
    context: string[];
    action: 'warn' | 'hide';
    whole_word: boolean;
    expires_at: string | null;
  }

  const ALL_CONTEXTS = ['home', 'public', 'notifications', 'thread'];
  // Matches validate_length(:phrase, max: 200) in user_content_filter.ex.
  const MAX_PHRASE = 200;
  // Expiry choices in minutes; 'never' sends null, 'keep' leaves an edited
  // filter's current expiry untouched.
  const EXPIRY_MINUTES: Record<string, number> = {
    '30m': 30,
    '1h': 60,
    '6h': 360,
    '1d': 1440,
    '1w': 10080,
    '1mo': 43200,
  };

  let filters = $state<ContentFilter[]>([]);
  let loading = $state(true);

  let editingId = $state<string | null>(null);
  let phrase = $state('');
  let action = $state<'warn' | 'hide'>('warn');
  let wholeWord = $state(false);
  let contexts = $state<string[]>([...ALL_CONTEXTS]);
  let expiry = $state('never');
  let saving = $state(false);
  let deletingId = $state<string | null>(null);

  let editing = $derived(filters.find((f) => f.id === editingId) ?? null);

  onMount(async () => {
    try {
      filters = await api.get<ContentFilter[]>('/api/v1/accounts/filters');
    } catch {
      addToast($t('settings.filters_load_failed'), 'error');
    } finally {
      loading = false;
    }
  });

  function resetForm() {
    editingId = null;
    phrase = '';
    action = 'warn';
    wholeWord = false;
    contexts = [...ALL_CONTEXTS];
    expiry = 'never';
  }

  function startEdit(f: ContentFilter) {
    editingId = f.id;
    phrase = f.phrase;
    action = f.action;
    wholeWord = f.whole_word;
    contexts = [...f.context];
    expiry = f.expires_at ? 'keep' : 'never';
    document.getElementById('filter-phrase')?.focus();
  }

  function toggleContext(ctx: string) {
    contexts = contexts.includes(ctx) ? contexts.filter((c) => c !== ctx) : [...contexts, ctx];
  }

  function errorCopy(err: unknown, fallbackKey: string): string {
    if (err instanceof ApiError) {
      if (err.body?.error === 'filter.not_found') return $t('settings.filters_error_not_found');
      if (err.body?.details?.phrase) return $t('settings.filters_error_phrase');
      if (err.body?.details?.context) return $t('settings.filters_error_context');
    }
    return $t(fallbackKey);
  }

  async function save() {
    const trimmed = phrase.trim();
    if (!trimmed) return addToast($t('settings.filters_error_phrase'), 'error');
    if (trimmed.length > MAX_PHRASE) return addToast($t('settings.filters_error_phrase'), 'error');
    if (contexts.length === 0) return addToast($t('settings.filters_error_context'), 'error');
    if (saving) return;

    const body: Record<string, unknown> = {
      phrase: trimmed,
      action,
      whole_word: wholeWord,
      context: contexts,
    };
    // The changeset casts expires_at, so an explicit null clears it on update.
    if (expiry === 'never') body.expires_at = null;
    else if (expiry !== 'keep') body.expires_at = new Date(Date.now() + EXPIRY_MINUTES[expiry] * 60_000).toISOString();

    saving = true;
    try {
      if (editingId) {
        const updated = await api.put<ContentFilter>(`/api/v1/accounts/filters/${editingId}`, body);
        filters = filters.map((f) => (f.id === updated.id ? updated : f));
        addToast($t('settings.filters_updated'), 'success');
      } else {
        const created = await api.post<ContentFilter>('/api/v1/accounts/filters', body);
        filters = [created, ...filters];
        addToast($t('settings.filters_added'), 'success');
      }
      resetForm();
      reloadFilters();
    } catch (err) {
      addToast(errorCopy(err, editingId ? 'settings.filters_update_failed' : 'settings.filters_add_failed'), 'error');
    } finally {
      saving = false;
    }
  }

  async function removeFilter(id: string) {
    if (deletingId) return;
    deletingId = id;
    try {
      await api.delete(`/api/v1/accounts/filters/${id}`);
      filters = filters.filter((f) => f.id !== id);
      if (editingId === id) resetForm();
      reloadFilters();
      addToast($t('settings.filters_removed'), 'success');
    } catch (err) {
      addToast(errorCopy(err, 'settings.filters_remove_failed'), 'error');
    } finally {
      deletingId = null;
    }
  }

  function expiryLabel(expiresAt: string | null): string {
    if (!expiresAt) return $t('settings.filters_expires_never');
    const ms = new Date(expiresAt).getTime() - Date.now();
    if (ms <= 0) return $t('settings.filters_expired');
    const minutes = Math.ceil(ms / 60_000);
    const rtf = new Intl.RelativeTimeFormat($locale, { numeric: 'always' });
    let time: string;
    if (minutes < 60) time = rtf.format(minutes, 'minute');
    else if (minutes < 1440) time = rtf.format(Math.round(minutes / 60), 'hour');
    else time = rtf.format(Math.round(minutes / 1440), 'day');
    return $t('settings.filters_expires_in', { time });
  }
</script>

<div class="filters-page">
  <SettingsSection
    title={editing ? $t('settings.filters_edit_title') : $t('settings.filters_new_title')}
    description={$t('settings.filters_form_desc')}
  >
    <SettingRow label={$t('settings.filters_phrase_label')} labelFor="filter-phrase" layout="stacked">
      <input
        id="filter-phrase"
        type="text"
        class="input"
        maxlength={MAX_PHRASE}
        bind:value={phrase}
        placeholder={$t('settings.filters_phrase_placeholder')}
      />
    </SettingRow>
    <SettingRow label={$t('settings.filters_action_label')} help={$t('settings.filters_action_help')} labelFor="filter-action">
      <select id="filter-action" class="input" bind:value={action}>
        <option value="warn">{$t('settings.filters_action_warn')}</option>
        <option value="hide">{$t('settings.filters_action_hide')}</option>
      </select>
    </SettingRow>
    <SettingRow label={$t('settings.filters_context_label')} help={$t('settings.filters_context_help')}>
      <div class="chips" role="group" aria-label={$t('settings.filters_context_label')}>
        {#each ALL_CONTEXTS as ctx (ctx)}
          <button
            type="button"
            class="chip"
            class:active={contexts.includes(ctx)}
            aria-pressed={contexts.includes(ctx)}
            onclick={() => toggleContext(ctx)}
          >
            {$t(`settings.filters_context_${ctx}`)}
          </button>
        {/each}
      </div>
    </SettingRow>
    <SettingRow label={$t('settings.filters_whole_word_label')} help={$t('settings.filters_whole_word_help')} labelFor="filter-whole-word">
      <Toggle id="filter-whole-word" bind:checked={wholeWord} />
    </SettingRow>
    <SettingRow label={$t('settings.filters_expiry_label')} labelFor="filter-expiry">
      <select id="filter-expiry" class="input" bind:value={expiry}>
        {#if editing?.expires_at}
          <option value="keep">{$t('settings.filters_expiry_keep', { current: expiryLabel(editing.expires_at) })}</option>
        {/if}
        <option value="never">{$t('settings.filters_expiry_never')}</option>
        <option value="30m">{$t('settings.filters_expiry_30m')}</option>
        <option value="1h">{$t('settings.filters_expiry_1h')}</option>
        <option value="6h">{$t('settings.filters_expiry_6h')}</option>
        <option value="1d">{$t('settings.filters_expiry_1d')}</option>
        <option value="1w">{$t('settings.filters_expiry_1w')}</option>
        <option value="1mo">{$t('settings.filters_expiry_1mo')}</option>
      </select>
    </SettingRow>
    <div class="form-actions">
      {#if editing}
        <button type="button" class="btn btn-ghost btn-sm" onclick={resetForm} disabled={saving}>
          {$t('settings.filters_cancel')}
        </button>
      {/if}
      <button type="button" class="btn btn-primary btn-sm" onclick={save} disabled={!phrase.trim() || saving}>
        {#if saving}
          {$t('settings.filters_saving')}
        {:else if editing}
          {$t('settings.filters_save')}
        {:else}
          {$t('settings.filters_add')}
        {/if}
      </button>
    </div>
  </SettingsSection>

  <SettingsSection title={$t('settings.filters_list_title')} description={$t('settings.filters_list_desc')}>
    {#if loading}
      <div class="placeholder"><Spinner /></div>
    {:else if filters.length === 0}
      <p class="placeholder">{$t('settings.filters_empty')}</p>
    {:else}
      {#each filters as filter (filter.id)}
        <SettingRow label={filter.phrase}>
          {#snippet meta()}
            <span class="badge" class:badge-warn={filter.action === 'warn'} class:badge-hide={filter.action === 'hide'}>
              {$t(`settings.filters_action_${filter.action}`)}
            </span>
            {#each filter.context as ctx (ctx)}
              <span class="tag">{$t(`settings.filters_context_${ctx}`)}</span>
            {/each}
            {#if filter.whole_word}
              <span class="tag">{$t('settings.filters_whole_word_tag')}</span>
            {/if}
            <span class="tag">{expiryLabel(filter.expires_at)}</span>
          {/snippet}
          <button type="button" class="btn btn-secondary btn-sm" onclick={() => startEdit(filter)}>
            {$t('settings.filters_edit')}
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-sm danger"
            onclick={() => removeFilter(filter.id)}
            disabled={deletingId === filter.id}
          >
            {$t('settings.filters_delete')}
          </button>
        </SettingRow>
      {/each}
    {/if}
  </SettingsSection>
</div>

<style>
  .filters-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2);
  }

  .chip {
    padding: 4px var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full);
    background: transparent;
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
    cursor: pointer;
  }

  .chip.active {
    background: var(--color-primary);
    border-color: var(--color-primary);
    color: var(--color-on-primary, white);
  }

  .form-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    padding: var(--space-4) var(--space-5);
  }

  .placeholder {
    margin: 0;
    padding: var(--space-6) var(--space-5);
    text-align: center;
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  .badge,
  .tag {
    font-size: var(--text-xs);
    padding: 1px 6px;
    border-radius: var(--radius-sm);
  }

  .badge {
    font-weight: 700;
  }

  .badge-warn {
    background: var(--color-warning-soft);
    color: var(--color-on-warning-soft);
  }

  .badge-hide {
    background: var(--color-danger-soft);
    color: var(--color-danger);
  }

  .tag {
    color: var(--color-text-tertiary);
    background: var(--color-surface);
  }

  .danger {
    color: var(--color-danger);
  }
</style>
