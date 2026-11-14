<script lang="ts">
  // Ctrl/Cmd+K search over every admin page and every registry setting.
  // Pages come from the nav catalog; settings from the schema endpoint,
  // fetched once on first open. Picking a setting deep-links to its row.
  import { goto } from '$app/navigation';
  import { t } from '$lib/stores/i18n.js';
  import { hasPermission, hasAnyPermission } from '$lib/stores/auth.js';
  import { adminSections, type AdminItem } from '$lib/admin-nav.js';
  import { settingsHref, type SettingsGroupId } from '$lib/admin-settings.js';
  import { getSettingsSchema } from '$lib/api/admin.js';
  import Modal from '$lib/components/ui/Modal.svelte';

  let { open = $bindable(false) }: { open?: boolean } = $props();

  interface Result {
    kind: 'page' | 'setting';
    label: string;
    context: string;
    href: string;
    /** Lowercased text the query is matched against. */
    haystack: string;
  }

  let query = $state('');
  let selected = $state(0);
  let settings = $state.raw<Result[]>([]);
  let settingsLoaded = false;

  function visible(item: AdminItem): boolean {
    if (item.permission) return hasPermission(item.permission);
    if (item.anyPermission) return hasAnyPermission(...item.anyPermission);
    return true;
  }

  // Hidden items (dedicated editors) are searchable too: they're real pages.
  let pages = $derived<Result[]>(
    adminSections.flatMap((s) =>
      s.items.filter(visible).map((i) => ({
        kind: 'page' as const,
        label: i.label,
        context: s.title,
        href: i.href,
        haystack: `${i.label} ${i.description} ${s.title}`.toLowerCase(),
      })),
    ),
  );

  function tr(key: string, fallback = ''): string {
    const out = $t(key);
    return out === key ? fallback : out;
  }

  async function loadSettings() {
    if (settingsLoaded) return;
    settingsLoaded = true;
    try {
      const { groups } = await getSettingsSchema();
      settings = groups.flatMap((g) => {
        const groupName = tr(`admin_settings.group.${g.id}`, g.id);
        return g.sections.flatMap((s) =>
          s.settings.map((e) => {
            const label = tr(`admin_settings.${e.key}`, e.key);
            const help = tr(`admin_settings.${e.key}_help`);
            return {
              kind: 'setting' as const,
              label,
              context: groupName,
              href: `${settingsHref(g.id as SettingsGroupId)}#setting-${e.key}`,
              haystack: `${label} ${help} ${e.key} ${groupName}`.toLowerCase(),
            };
          }),
        );
      });
    } catch {
      settingsLoaded = false; // retry on next open
    }
  }

  $effect(() => {
    if (!open) return;
    query = '';
    selected = 0;
    loadSettings();
  });

  // Every word must appear somewhere; label matches rank first.
  let results = $derived.by(() => {
    const words = query.toLowerCase().trim().split(/\s+/).filter(Boolean);
    const all = [...pages, ...settings];
    if (!words.length) return pages.slice(0, 12);
    return all
      .filter((r) => words.every((w) => r.haystack.includes(w)))
      .map((r) => ({ r, score: words.every((w) => r.label.toLowerCase().includes(w)) ? 0 : 1 }))
      .sort((a, b) => a.score - b.score || (a.r.kind === 'page' ? -1 : 1))
      .slice(0, 30)
      .map((x) => x.r);
  });

  $effect(() => {
    void query;
    selected = 0;
  });

  function pick(r: Result | undefined) {
    if (!r) return;
    open = false;
    goto(r.href);
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      selected = Math.min(selected + 1, results.length - 1);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      selected = Math.max(selected - 1, 0);
    } else if (e.key === 'Enter') {
      e.preventDefault();
      pick(results[selected]);
    }
  }

  $effect(() => {
    document.getElementById(`palette-option-${selected}`)?.scrollIntoView({ block: 'nearest' });
  });
</script>

<Modal bind:open title={$t('admin_palette.title')} size="md">
  <input
    data-autofocus
    bind:value={query}
    onkeydown={onKeydown}
    class="input palette-input"
    type="search"
    placeholder={$t('admin_palette.placeholder')}
    role="combobox"
    aria-expanded="true"
    aria-controls="palette-results"
    aria-activedescendant={results.length ? `palette-option-${selected}` : undefined}
    autocomplete="off"
  />

  {#if results.length}
    <ul class="palette-results" id="palette-results" role="listbox" aria-label={$t('admin_palette.title')}>
      {#each results as r, i (r.href)}
        <li
          id="palette-option-{i}"
          role="option"
          aria-selected={i === selected}
          class="palette-option"
          class:selected={i === selected}
          onclick={() => pick(r)}
          onmousemove={() => (selected = i)}
          onkeydown={() => {}}
        >
          <span class="palette-kind">{r.kind === 'page' ? $t('admin_palette.page') : $t('admin_palette.setting')}</span>
          <span class="palette-label">{r.label}</span>
          <span class="palette-context">{r.context}</span>
        </li>
      {/each}
    </ul>
  {:else}
    <p class="palette-empty">{$t('admin_palette.empty')}</p>
  {/if}

  <p class="palette-hint">{$t('admin_palette.hint')}</p>
</Modal>

<style>
  .palette-input {
    width: 100%;
  }

  .palette-results {
    list-style: none;
    margin: var(--space-3) 0 0;
    padding: 0;
    max-height: min(420px, 55vh);
    overflow-y: auto;
  }

  .palette-option {
    display: flex;
    align-items: baseline;
    gap: var(--space-3);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    cursor: pointer;
  }

  .palette-option.selected {
    background: var(--color-primary-soft);
  }

  .palette-kind {
    flex-shrink: 0;
    width: 4.5rem;
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-tertiary);
  }

  .palette-label {
    flex: 1;
    min-width: 0;
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .palette-context {
    flex-shrink: 0;
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .palette-empty,
  .palette-hint {
    margin: var(--space-3) 0 0;
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  @media (pointer: coarse) {
    .palette-option {
      min-height: 44px;
      align-items: center;
    }
  }
</style>
