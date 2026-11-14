<script lang="ts">
  // Every setting that differs from its default, across all groups: a
  // one-page record of how this instance is configured.
  import { onMount } from 'svelte';
  import { t } from '$lib/stores/i18n.js';
  import { t as ti } from '$lib/utils/i18n.js';
  import { addToast } from '$lib/stores/toast.js';
  import { getSettingsSchema, resetAdminSetting } from '$lib/api/admin.js';
  import type { SettingSchemaEntry, SettingsSchemaGroup, SettingValue } from '$lib/api/types.js';
  import { settingsHref, type SettingsGroupId } from '$lib/admin-settings.js';
  import AdminPage from '$lib/components/admin/AdminPage.svelte';
  import SettingsSection from '$lib/components/admin/SettingsSection.svelte';
  import StatusPill from '$lib/components/admin/StatusPill.svelte';

  let groups = $state.raw<SettingsSchemaGroup[]>([]);
  let loading = $state(true);
  let failed = $state(false);
  let resetting = $state<string | null>(null);

  let changed = $derived(
    groups
      .map((g) => ({ group: g, entries: g.sections.flatMap((s) => s.settings).filter((e) => e.stored) }))
      .filter((x) => x.entries.length > 0),
  );
  let total = $derived(changed.reduce((n, x) => n + x.entries.length, 0));

  async function load() {
    try {
      groups = (await getSettingsSchema()).groups;
      failed = false;
    } catch {
      failed = true;
    } finally {
      loading = false;
    }
  }

  async function reset(entry: SettingSchemaEntry) {
    resetting = entry.key;
    try {
      await resetAdminSetting(entry.key);
      addToast(ti('admin_settings.reset_done'), 'success');
      await load();
    } catch {
      addToast(ti('admin_settings.save_error'), 'error');
    } finally {
      resetting = null;
    }
  }

  function tr(key: string, fallback: string): string {
    const out = $t(key);
    return out === key ? fallback : out;
  }

  function show(entry: SettingSchemaEntry, v: SettingValue): string {
    if (v === null || v === '' || (Array.isArray(v) && !v.length)) return tr('admin_settings.empty', 'empty');
    if (typeof v === 'boolean') return v ? $t('admin_settings.on') : $t('admin_settings.off');
    if (Array.isArray(v)) return v.join(', ');
    if (entry.type === 'enum') return tr(`admin_settings.option.${entry.key}.${v}`, String(v));
    const unit = entry.unit ? tr(`admin_settings.unit.${entry.unit}`, entry.unit) : '';
    return unit ? `${v} ${unit}` : String(v);
  }

  onMount(load);
</script>

<AdminPage title={$t('admin_changed.title')} description={$t('admin_changed.description')} width="narrow">
  {#if loading}
    <p class="muted">{$t('admin_shell.loading')}</p>
  {:else if failed}
    <p class="muted">{$t('admin_settings.load_error')}</p>
  {:else if total === 0}
    <p class="muted">{$t('admin_changed.none')}</p>
  {:else}
    <p class="muted">{$t('admin_changed.count', { count: total })}</p>
    {#each changed as { group, entries } (group.id)}
      <SettingsSection title={$t(`admin_settings.group.${group.id}`)}>
        {#each entries as entry (entry.key)}
          <div class="changed-row">
            <div class="changed-text">
              <a class="changed-label" href="{settingsHref(group.id as SettingsGroupId)}#setting-{entry.key}">
                {tr(`admin_settings.${entry.key}`, entry.key)}
              </a>
              <code class="changed-key">{entry.key}</code>
            </div>
            <div class="changed-values">
              {#if entry.secret}
                <StatusPill tone="success" label={$t('admin_settings.secret_set')} />
              {:else}
                <span class="changed-value">{show(entry, entry.value)}</span>
                <span class="changed-default">{$t('admin_settings.default_is', { value: show(entry, entry.default) })}</span>
              {/if}
            </div>
            {#if group.can_manage}
              <button
                type="button"
                class="btn btn-sm btn-ghost"
                onclick={() => reset(entry)}
                disabled={resetting === entry.key}
              >
                {entry.secret ? $t('admin_settings.secret_remove') : $t('admin_settings.reset')}
              </button>
            {/if}
          </div>
        {/each}
      </SettingsSection>
    {/each}
  {/if}
</AdminPage>

<style>
  .muted {
    margin: 0;
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .changed-row {
    display: flex;
    align-items: center;
    gap: var(--space-4);
    padding: var(--space-3) var(--space-5);
  }

  .changed-text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }

  .changed-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
    text-decoration: none;
  }

  .changed-label:hover {
    color: var(--color-primary);
  }

  .changed-key {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .changed-values {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    text-align: end;
    min-width: 0;
  }

  .changed-value {
    font-size: var(--text-sm);
    font-weight: 600;
    word-break: break-word;
  }

  .changed-default {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  @media (max-width: 560px) {
    .changed-row {
      flex-wrap: wrap;
    }

    .changed-values {
      align-items: flex-start;
      text-align: start;
    }
  }
</style>
