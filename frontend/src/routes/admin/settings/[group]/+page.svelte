<script lang="ts">
  // One settings group, rendered from the backend registry. Everything here
  // is generic: adding a setting to Config.Registry (plus its en.json label)
  // is all it takes for it to appear on the right page.
  import { page } from '$app/state';
  import { t } from '$lib/stores/i18n.js';
  import { t as ti } from '$lib/utils/i18n.js';
  import { addToast } from '$lib/stores/toast.js';
  import { ApiError } from '$lib/api/client.js';
  import { getSettingsSchema, updateAdminSettings, resetAdminSetting } from '$lib/api/admin.js';
  import type {
    SettingError,
    SettingSchemaEntry,
    SettingsSchemaGroup,
    SettingValue,
  } from '$lib/api/types.js';
  import { groupFromSlug, relatedPages } from '$lib/admin-settings.js';
  import AdminPage from '$lib/components/admin/AdminPage.svelte';
  import SettingsSection from '$lib/components/admin/SettingsSection.svelte';
  import SettingField from '$lib/components/admin/SettingField.svelte';
  import SaveBar from '$lib/components/admin/SaveBar.svelte';

  let groupId = $derived(groupFromSlug(page.params.group ?? ''));

  // Read-only server data: raw, so values copied out of it aren't proxies.
  let group = $state.raw<SettingsSchemaGroup | null>(null);
  let loading = $state(true);
  let loadFailed = $state(false);
  let saving = $state(false);

  // Form state: every non-secret setting's value, and what was typed into
  // secret fields (blank = keep the stored secret).
  let saved = $state<Record<string, SettingValue>>({});
  let form = $state<Record<string, SettingValue>>({});
  let errors = $state<Record<string, string>>({});

  let entries = $derived(group ? group.sections.flatMap((s) => s.settings) : []);
  let byKey = $derived(new Map(entries.map((e) => [e.key, e])));

  function same(a: SettingValue, b: SettingValue): boolean {
    return JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
  }

  function isChanged(entry: SettingSchemaEntry): boolean {
    if (entry.secret) return typeof form[entry.key] === 'string' && form[entry.key] !== '';
    return !same(form[entry.key], saved[entry.key]);
  }

  let changedKeys = $derived(entries.filter(isChanged).map((e) => e.key));
  let dirty = $derived(changedKeys.length > 0);

  function visible(entry: SettingSchemaEntry): boolean {
    if (!entry.visible_when) return true;
    return form[entry.visible_when.key] === entry.visible_when.value;
  }

  async function load(id: string) {
    loading = true;
    loadFailed = false;
    try {
      const schema = await getSettingsSchema();
      group = schema.groups.find((g) => g.id === id) ?? null;
      const values: Record<string, SettingValue> = {};
      for (const entry of group?.sections.flatMap((s) => s.settings) ?? []) {
        values[entry.key] = entry.secret ? '' : entry.value;
      }
      saved = values;
      form = structuredClone(values);
      errors = {};
    } catch {
      loadFailed = true;
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    if (groupId) load(groupId);
  });

  async function save() {
    if (!dirty) return;
    saving = true;
    errors = {};
    try {
      await updateAdminSettings(changedKeys.map((key) => ({ key, value: form[key] })));
      addToast(ti('admin_settings.saved'), 'success');
      await load(groupId!);
    } catch (e) {
      const list = (e instanceof ApiError
        ? (e.body as unknown as { errors?: SettingError[] }).errors
        : undefined) ?? [];
      if (list.length) {
        errors = Object.fromEntries(list.filter((x) => x.key).map((x) => [x.key!, x.error]));
        addToast(ti('admin_settings.save_invalid'), 'error');
      } else if (e instanceof ApiError && e.status === 403) {
        addToast(ti('admin_settings.forbidden'), 'error');
      } else {
        addToast(ti('admin_settings.save_error'), 'error');
      }
    } finally {
      saving = false;
    }
  }

  function discard() {
    form = structuredClone($state.snapshot(saved));
    errors = {};
  }

  async function reset(entry: SettingSchemaEntry) {
    try {
      await resetAdminSetting(entry.key);
      addToast(ti('admin_settings.reset_done'), 'success');
      // Keep unrelated unsaved edits: only this key is reloaded.
      const pending = $state.snapshot(form);
      await load(groupId!);
      for (const key of changedKeysFrom(pending)) {
        if (key !== entry.key) form[key] = pending[key];
      }
    } catch {
      addToast(ti('admin_settings.save_error'), 'error');
    }
  }

  function changedKeysFrom(pending: Record<string, SettingValue>): string[] {
    return Object.keys(pending).filter((key) => {
      const entry = byKey.get(key);
      if (!entry) return false;
      return entry.secret ? pending[key] !== '' : !same(pending[key], saved[key]);
    });
  }

  // A translated string, or '' when the key has no text.
  function optional(key: string): string {
    const out = $t(key);
    return out === key ? '' : out;
  }

  let related = $derived(groupId ? (relatedPages[groupId] ?? []) : []);
  let title = $derived(groupId ? $t(`admin_settings.group.${groupId}`) : '');
  let description = $derived(groupId ? $t(`admin_settings.group.${groupId}_desc`) : '');
</script>

{#if !groupId}
  <AdminPage title={$t('admin_settings.not_found')}>
    <p class="muted">{$t('admin_settings.not_found_desc')}</p>
  </AdminPage>
{:else}
  <AdminPage {title} {description} width="narrow">
    {#if related.length}
      <div class="related">
        {#each related as link (link.href)}
          <a class="related-card" href={link.href}>
            <span class="related-text">
              <span class="related-title">{$t(link.titleKey)}</span>
              <span class="related-desc">{$t(link.descriptionKey)}</span>
            </span>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" class="related-arrow"><path d="M9 18l6-6-6-6" /></svg>
          </a>
        {/each}
      </div>
    {/if}

    {#if loading && !group}
      <p class="muted">{$t('admin_shell.loading')}</p>
    {:else if loadFailed || !group}
      <p class="muted">{$t('admin_settings.load_error')}</p>
    {:else}
      {#if !group.can_manage}
        <p class="notice" role="note">{$t('admin_settings.read_only', { permission: group.permission })}</p>
      {/if}

      {#each group.sections as section (section.id)}
        {@const basic = section.settings.filter((e) => !e.advanced && visible(e))}
        {@const advanced = section.settings.filter((e) => e.advanced && visible(e))}
        {#if basic.length || advanced.length}
          <SettingsSection
            title={$t(`admin_settings.section.${section.id}`)}
            description={optional(`admin_settings.section.${section.id}_desc`)}
          >
            {#each basic as entry (entry.key)}
              <SettingField
                {entry}
                bind:value={form[entry.key]}
                disabled={!group.can_manage || saving}
                error={errors[entry.key] ?? null}
                onreset={() => reset(entry)}
              />
            {/each}
            {#if advanced.length}
              <details class="advanced" open={advanced.some((e) => errors[e.key] || isChanged(e))}>
                <summary>{$t('admin_settings.advanced', { count: advanced.length })}</summary>
                {#each advanced as entry (entry.key)}
                  <SettingField
                    {entry}
                    bind:value={form[entry.key]}
                    disabled={!group.can_manage || saving}
                    error={errors[entry.key] ?? null}
                    onreset={() => reset(entry)}
                  />
                {/each}
              </details>
            {/if}
          </SettingsSection>
        {/if}
      {/each}

      <SaveBar {dirty} {saving} onsave={save} ondiscard={discard} />
    {/if}
  </AdminPage>
{/if}

<style>
  .muted {
    margin: 0;
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }

  .notice {
    margin: 0;
    padding: var(--space-3) var(--space-4);
    border-radius: var(--radius-lg);
    background: var(--color-info-soft);
    color: var(--color-on-info-soft);
    font-size: var(--text-sm);
  }

  .related {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
    gap: var(--space-3);
  }

  .related-card {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    background: var(--color-surface-raised);
    color: var(--color-text);
    text-decoration: none;
    transition: border-color var(--transition-fast);
  }

  .related-card:hover {
    border-color: var(--color-primary);
    text-decoration: none;
  }

  .related-text {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-width: 0;
  }

  .related-title {
    font-size: var(--text-sm);
    font-weight: 600;
  }

  .related-desc {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .related-arrow {
    flex-shrink: 0;
    color: var(--color-text-tertiary);
  }

  :global([dir='rtl']) .related-arrow {
    transform: scaleX(-1);
  }

  .advanced summary {
    padding: var(--space-3) var(--space-5);
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text-secondary);
    cursor: pointer;
  }

  .advanced summary:hover {
    color: var(--color-text);
  }

  .advanced[open] summary {
    border-block-end: 1px solid var(--color-border);
  }

  .advanced > :global(.setting-row + .setting-row) {
    border-block-start: 1px solid var(--color-border);
  }
</style>
