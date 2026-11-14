<script lang="ts">
  import { onMount } from 'svelte';
  import { getAdminSettings } from '$lib/api/admin.js';
  import { listDeletedGroups, restoreGroup } from '$lib/api/groups.js';
  import { listDeletedPages, restorePage } from '$lib/api/pages.js';
  import type { Group } from '$lib/api/types.js';
  import { addToast } from '$lib/stores/toast.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import StatusPill from '$lib/components/admin/StatusPill.svelte';
  import { t } from '$lib/stores/i18n.js';
  import { t as ti } from '$lib/utils/i18n.js';

  // ── Auto-purge safety settings ──────────────────────────────────────
  // The 60-day permanent-deletion worker is opt-in: it only hard-deletes
  // when `takedown_purge_enabled` is truthy (default off). Until an admin
  // turns it on, appealed/un-appealed takedowns are kept indefinitely and
  // only the pre-deletion reminder fires.
  let settingsLoading = $state(true);
  let purgeEnabled = $state(false);
  let retentionDays = $state(60);
  let reminderLeadDays = $state(7);

  function readBool(v: unknown): boolean {
    return v === true || v === 'true' || v === '1';
  }
  function readInt(v: unknown, fallback: number): number {
    const n = typeof v === 'number' ? v : parseInt(String(v ?? ''), 10);
    return Number.isFinite(n) && n >= 0 ? n : fallback;
  }

  async function loadSettings() {
    settingsLoading = true;
    try {
      const rows = await getAdminSettings();
      const byKey = new Map(rows.map((r) => [r.key, r.value as unknown]));
      if (byKey.has('takedown_purge_enabled')) purgeEnabled = readBool(byKey.get('takedown_purge_enabled'));
      if (byKey.has('takedown_retention_days')) retentionDays = readInt(byKey.get('takedown_retention_days'), 60);
      if (byKey.has('takedown_reminder_lead_days')) reminderLeadDays = readInt(byKey.get('takedown_reminder_lead_days'), 7);
    } catch {
      addToast(ti('admin_takedowns.toast_load_settings_error'), 'error');
    } finally {
      settingsLoading = false;
    }
  }



  // ── Deleted content — restore ───────────────────────────────────────
  let groupsLoading = $state(true);
  let pagesLoading = $state(true);
  let deletedGroups = $state<Group[]>([]);
  let deletedPages = $state<Array<{ id: string; display_name?: string; handle?: string }>>([]);
  let restoringId = $state<string | null>(null);

  async function loadDeleted() {
    groupsLoading = true;
    pagesLoading = true;
    try {
      deletedGroups = await listDeletedGroups();
    } catch {
      addToast(ti('admin_takedowns.toast_load_groups_error'), 'error');
    } finally {
      groupsLoading = false;
    }
    try {
      deletedPages = await listDeletedPages();
    } catch {
      addToast(ti('admin_takedowns.toast_load_pages_error'), 'error');
    } finally {
      pagesLoading = false;
    }
  }

  async function handleRestoreGroup(g: Group) {
    if (restoringId) return;
    restoringId = g.id;
    try {
      await restoreGroup(g.id);
      deletedGroups = deletedGroups.filter((x) => x.id !== g.id);
      addToast(ti('admin_takedowns.toast_group_restored'), 'success');
    } catch {
      addToast(ti('admin_takedowns.toast_group_restore_error'), 'error');
    } finally {
      restoringId = null;
    }
  }

  async function handleRestorePage(p: { id: string }) {
    if (restoringId) return;
    restoringId = p.id;
    try {
      await restorePage(p.id);
      deletedPages = deletedPages.filter((x) => x.id !== p.id);
      addToast(ti('admin_takedowns.toast_page_restored'), 'success');
    } catch {
      addToast(ti('admin_takedowns.toast_page_restore_error'), 'error');
    } finally {
      restoringId = null;
    }
  }

  function pageName(p: { display_name?: string; handle?: string }): string {
    return p.display_name || p.handle || ti('admin_takedowns.untitled_page');
  }

  onMount(() => {
    loadSettings();
    loadDeleted();
  });
</script>

<div class="tk-page">
  <header class="tk-header">
    <h1 class="tk-title">{$t('admin_takedowns.title')}</h1>
    <p class="tk-lead">{$t('admin_takedowns.lead')}</p>
  </header>

  <!-- Auto-deletion settings live in Settings; this is a read-only summary. -->
  <section class="tk-card">
    <h2 class="tk-card-title">{$t('admin_takedowns.auto_delete_title')}</h2>
    {#if settingsLoading}
      <div class="tk-center"><Spinner /></div>
    {:else}
      <dl class="tk-summary">
        <div>
          <dt>{$t('admin_takedowns.toggle_label')}</dt>
          <dd><StatusPill tone={purgeEnabled ? 'warning' : 'neutral'} label={purgeEnabled ? $t('admin_settings.on') : $t('admin_settings.off')} /></dd>
        </div>
        <div>
          <dt>{$t('admin_takedowns.retention_label')}</dt>
          <dd>{$t('admin_takedowns.days', { count: retentionDays })}</dd>
        </div>
        <div>
          <dt>{$t('admin_takedowns.reminder_label')}</dt>
          <dd>{$t('admin_takedowns.days', { count: reminderLeadDays })}</dd>
        </div>
      </dl>
      <p class="tk-settings-links">
        {$t('admin_takedowns.settings_moved')}
        <a href="/admin/settings/moderation">{$t('admin_settings.group.moderation')}</a> ·
        <a href="/admin/settings/retention">{$t('admin_settings.group.retention')}</a>
      </p>
    {/if}
  </section>

  <!-- Deleted groups -->
  <section class="tk-card">
    <h2 class="tk-card-title">{$t('admin_takedowns.deleted_groups')}</h2>
    {#if groupsLoading}
      <div class="tk-center"><Spinner /></div>
    {:else if deletedGroups.length === 0}
      <p class="tk-empty">{$t('admin_takedowns.no_deleted_groups')}</p>
    {:else}
      <ul class="tk-list">
        {#each deletedGroups as g (g.id)}
          <li class="tk-item">
            <span class="tk-item-name">{g.name}</span>
            <button
              type="button"
              class="btn btn-sm btn-primary"
              onclick={() => handleRestoreGroup(g)}
              disabled={restoringId === g.id}
            >
              {restoringId === g.id ? $t('admin_takedowns.restoring') : $t('admin_takedowns.restore')}
            </button>
          </li>
        {/each}
      </ul>
    {/if}
  </section>

  <!-- Deleted pages -->
  <section class="tk-card">
    <h2 class="tk-card-title">{$t('admin_takedowns.deleted_pages')}</h2>
    {#if pagesLoading}
      <div class="tk-center"><Spinner /></div>
    {:else if deletedPages.length === 0}
      <p class="tk-empty">{$t('admin_takedowns.no_deleted_pages')}</p>
    {:else}
      <ul class="tk-list">
        {#each deletedPages as p (p.id)}
          <li class="tk-item">
            <span class="tk-item-name">{pageName(p)}</span>
            <button
              type="button"
              class="btn btn-sm btn-primary"
              onclick={() => handleRestorePage(p)}
              disabled={restoringId === p.id}
            >
              {restoringId === p.id ? $t('admin_takedowns.restoring') : $t('admin_takedowns.restore')}
            </button>
          </li>
        {/each}
      </ul>
    {/if}
  </section>

  <p class="tk-footnote">
    {$t('admin_takedowns.footnote_pre')} <a href="/admin/user-management/appeals">{$t('admin_takedowns.footnote_link')}</a> {$t('admin_takedowns.footnote_post')}
  </p>
</div>

<style>
  .tk-page {
    display: flex;
    flex-direction: column;
    gap: var(--space-4, 16px);
    max-width: 720px;
  }

  .tk-title {
    font-size: var(--text-xl, 1.25rem);
    font-weight: 700;
    margin: 0 0 var(--space-1, 4px);
  }

  .tk-lead {
    margin: 0;
    color: var(--color-text-secondary);
    font-size: var(--text-sm, 0.875rem);
    line-height: 1.5;
  }

  .tk-card {
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md, 8px);
    background: var(--color-surface);
    padding: var(--space-4, 16px);
    display: flex;
    flex-direction: column;
    gap: var(--space-3, 12px);
  }

  .tk-card-title {
    font-size: var(--text-md, 1rem);
    font-weight: 600;
    margin: 0;
  }

  .tk-center {
    display: flex;
    justify-content: center;
    padding: var(--space-4, 16px);
  }

  .tk-empty {
    margin: 0;
    color: var(--color-text-tertiary);
    font-size: var(--text-sm, 0.875rem);
  }

  .tk-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-2, 8px);
  }

  .tk-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3, 12px);
    padding: var(--space-2, 8px) var(--space-3, 12px);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md, 8px);
    background: var(--color-surface-alt, transparent);
  }

  .tk-item-name {
    font-weight: 500;
    word-break: break-word;
  }

  .tk-footnote {
    margin: 0;
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text-secondary);
  }

  .tk-footnote a {
    color: var(--color-primary);
  }

  .tk-summary {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: var(--space-3);
    margin: 0;
  }

  .tk-summary dt {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .tk-summary dd {
    margin: 2px 0 0;
    font-weight: 600;
  }

  .tk-settings-links {
    margin: var(--space-3) 0 0;
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }
</style>
