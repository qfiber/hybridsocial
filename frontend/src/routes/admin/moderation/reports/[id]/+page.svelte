<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { t } from '$lib/stores/i18n.js';
  import { currentUser } from '$lib/stores/auth.js';
  import { getReport, resolveReport, dismissReport, assignReport } from '$lib/api/admin.js';
  import type { AdminReportDetail } from '$lib/api/types.js';

  let reportId = $derived($page.params.id ?? '');
  let report = $state<AdminReportDetail | null>(null);
  let loading = $state(true);
  let notFound = $state(false);
  let acting = $state(false);
  let actionNote = $state('');

  let isOpen = $derived(report?.status === 'pending' || report?.status === 'investigating');
  let assignedToMe = $derived(!!report?.assigned_to && report.assigned_to === $currentUser?.id);
  let post = $derived(report?.target_post ?? null);
  let isPostReport = $derived(report?.target_type === 'post');

  onMount(() => {
    load();
  });

  function errorCode(err: unknown): string | undefined {
    return (err as { body?: { error?: string } })?.body?.error;
  }

  async function load() {
    loading = true;
    notFound = false;
    try {
      report = (await getReport(reportId)).data;
    } catch (err: unknown) {
      if (errorCode(err) === 'report.not_found') notFound = true;
      else addToast($t('admin.reports.load_failed'), 'error');
    } finally {
      loading = false;
    }
  }

  // Every action reloads the full detail so the activity trail and
  // related counts reflect what the server actually recorded.
  async function act(fn: () => Promise<unknown>, successKey: string) {
    if (!report) return;
    acting = true;
    try {
      await fn();
      addToast($t(successKey), 'success');
      actionNote = '';
      await load();
    } catch (err: unknown) {
      if (errorCode(err) === 'report.already_closed') {
        addToast($t('admin.reports.already_closed'), 'error');
        await load();
      } else {
        addToast($t('admin.reports.action_failed'), 'error');
      }
    } finally {
      acting = false;
    }
  }

  const handleAssign = () => act(() => assignReport(reportId), 'admin.reports.assigned_toast');
  const handleResolve = () =>
    act(() => resolveReport(reportId, actionNote.trim() || undefined), 'admin.reports.resolved_toast');
  const handleDismiss = () => act(() => dismissReport(reportId), 'admin.reports.dismissed_toast');

  function formatDate(iso: string | null | undefined): string {
    if (!iso) return '—';
    return new Date(iso).toLocaleString(undefined, {
      year: 'numeric', month: 'short', day: 'numeric',
      hour: '2-digit', minute: '2-digit'
    });
  }

  function statusLabel(status: string): string {
    return $t(`admin.reports.status_${status}`);
  }

  function categoryLabel(category: string): string {
    return category.replace(/_/g, ' ');
  }

  // Known audit actions get readable copy; anything else falls back to
  // the raw action name so a new action type never renders blank.
  const ACTION_KEYS: Record<string, string> = {
    'report.assigned': 'admin.reports.activity_assigned',
    'report.resolved': 'admin.reports.activity_resolved',
    'report.dismissed': 'admin.reports.activity_dismissed',
    'report.escalated': 'admin.reports.activity_escalated'
  };

  function activityLabel(action: string): string {
    return ACTION_KEYS[action] ? $t(ACTION_KEYS[action]) : action;
  }

  function mediaSrc(m: { storage_path: string | null; remote_url: string | null }): string {
    return m.storage_path || m.remote_url || '';
  }
</script>

<svelte:head>
  <title>{$t('admin.reports.detail_title')} {reportId.slice(0, 8)} — Admin</title>
</svelte:head>

<div class="report-detail-page">
  <a class="back-link" href="/admin/moderation">← {$t('admin.reports.back')}</a>

  {#if loading && !report}
    <div class="skeleton" style="height: 240px"></div>
  {:else if notFound}
    <div class="card not-found">
      <h1 class="not-found-title">{$t('admin.reports.not_found_title')}</h1>
      <p class="muted">{$t('admin.reports.not_found_body')}</p>
    </div>
  {:else if report}
    <header class="page-header">
      <h1 class="page-title">
        <span class="report-category">{categoryLabel(report.category)}</span>
        {$t(isPostReport ? 'admin.reports.kind_post' : 'admin.reports.kind_account')}
      </h1>
      <div class="header-badges">
        <span class="status-badge status-{report.status}">{statusLabel(report.status)}</span>
        {#if report.tier === 'group'}
          <span class="badge badge-neutral">{$t('admin.reports.tier_group')}</span>
        {/if}
        {#if report.federated}
          <span class="badge badge-info">{$t('admin.reports.federated')}</span>
        {/if}
        <span class="muted header-date">{formatDate(report.created_at)}</span>
      </div>
    </header>

    <div class="layout">
      <div class="main-col">
        <!-- Why it was reported -->
        <section class="card section">
          <h2 class="section-title">{$t('admin.reports.reason')}</h2>
          <p class="reason-category">
            {$t('admin.reports.category')}: <strong>{categoryLabel(report.category)}</strong>
          </p>
          {#if report.description}
            <blockquote class="reason-note">{report.description}</blockquote>
          {:else}
            <p class="muted">{$t('admin.reports.no_note')}</p>
          {/if}
        </section>

        <!-- What was reported -->
        <section class="card section">
          <h2 class="section-title">{$t('admin.reports.reported_content')}</h2>
          {#if isPostReport}
            {#if post}
              <article class="post-preview" class:post-deleted={!!post.deleted_at}>
                <div class="post-preview-head">
                  {#if post.author}
                    <a href="/@{post.author.handle}" class="author-name">
                      {post.author.display_name || post.author.handle}
                    </a>
                    <span class="muted">@{post.author.handle}</span>
                  {/if}
                  <span class="muted">· {formatDate(post.created_at)}</span>
                  <span class="badge badge-neutral">{post.visibility}</span>
                  {#if post.sensitive}<span class="badge badge-warning">{$t('admin.reports.sensitive')}</span>{/if}
                  {#if post.edited_at}<span class="badge badge-neutral">{$t('admin.reports.edited')}</span>{/if}
                  {#if post.deleted_at}<span class="badge badge-danger">{$t('admin.reports.post_deleted')}</span>{/if}
                </div>
                {#if post.spoiler_text}
                  <p class="spoiler">{$t('admin.reports.cw')}: {post.spoiler_text}</p>
                {/if}
                {#if post.content_html}
                  <!-- content_html is rendered and sanitized server-side. -->
                  <div class="post-body">{@html post.content_html}</div>
                {:else if post.content}
                  <div class="post-body post-body-plain">{post.content}</div>
                {:else}
                  <p class="muted">{$t('admin.reports.no_text')}</p>
                {/if}
                {#if post.media.length > 0}
                  <div class="media-grid">
                    {#each post.media as m (m.id)}
                      {#if m.content_type.startsWith('image/')}
                        <img src={mediaSrc(m)} alt={m.alt_text || ''} class="media-thumb" />
                      {:else if m.content_type.startsWith('video/')}
                        <video src={mediaSrc(m)} controls muted class="media-thumb"></video>
                      {:else}
                        <div class="media-unknown">{m.content_type}</div>
                      {/if}
                    {/each}
                  </div>
                {/if}
                {#if post.edited_at && !post.deleted_at}
                  <p class="hint">{$t('admin.reports.edited_hint')}</p>
                {/if}
              </article>
              <div class="link-row">
                <a class="btn btn-sm btn-outline" href="/admin/posts/{post.id}">
                  {$t('admin.reports.open_admin_post')}
                </a>
                {#if !post.deleted_at}
                  <a class="btn btn-sm btn-ghost" href="/post/{post.id}" target="_blank" rel="noopener noreferrer">
                    {$t('admin.reports.open_public_post')}
                  </a>
                {/if}
              </div>
            {:else}
              <p class="muted">
                {$t('admin.reports.post_missing')} <code>{report.target_id}</code>
              </p>
            {/if}
          {:else}
            <p class="muted">{$t('admin.reports.account_report_hint')}</p>
          {/if}
        </section>

        <!-- Activity -->
        <section class="card section">
          <h2 class="section-title">{$t('admin.reports.activity')}</h2>
          <ol class="timeline">
            <li class="timeline-row">
              <span class="timeline-action">{$t('admin.reports.activity_filed')}</span>
              {#if report.reporter}
                <a href="/@{report.reporter.acct || report.reporter.handle}">@{report.reporter.acct || report.reporter.handle}</a>
              {/if}
              <span class="muted">· {formatDate(report.created_at)}</span>
            </li>
            {#if report.escalated_at}
              <li class="timeline-row">
                <span class="timeline-action">{$t('admin.reports.activity_escalated')}</span>
                {#if report.escalated_by}
                  <a href="/@{report.escalated_by.handle}">@{report.escalated_by.handle}</a>
                {/if}
                <span class="muted">· {formatDate(report.escalated_at)}</span>
              </li>
            {/if}
            {#each report.audit_log as entry (entry.id)}
              <li class="timeline-row">
                <span class="timeline-action">{activityLabel(entry.action)}</span>
                {#if entry.actor}
                  <a href="/@{entry.actor.handle}">@{entry.actor.handle}</a>
                {:else}
                  <span class="muted">{$t('admin.reports.system')}</span>
                {/if}
                <span class="muted">· {formatDate(entry.created_at)}</span>
                {#if entry.details && typeof entry.details.action_taken === 'string' && entry.details.action_taken !== 'resolved'}
                  <p class="timeline-note">{entry.details.action_taken}</p>
                {/if}
              </li>
            {/each}
          </ol>
        </section>

        <!-- Other reports against this account -->
        <section class="card section">
          <header class="section-header">
            <h2 class="section-title">{$t('admin.reports.related')}</h2>
            <span class="section-count">{report.related_reports.length}</span>
          </header>
          {#if report.related_reports.length === 0}
            <p class="muted">{$t('admin.reports.related_none')}</p>
          {:else}
            <ul class="related-list">
              {#each report.related_reports as r (r.id)}
                <li>
                  <a class="related-row" href="/admin/moderation/reports/{r.id}">
                    <span class="report-category">{categoryLabel(r.category)}</span>
                    <span class="status-badge status-{r.status}">{statusLabel(r.status)}</span>
                    <span class="muted">
                      {$t(r.target_type === 'post' ? 'admin.reports.kind_post' : 'admin.reports.kind_account')}
                      · {formatDate(r.created_at)}
                    </span>
                  </a>
                </li>
              {/each}
            </ul>
          {/if}
        </section>
      </div>

      <aside class="side-col">
        <!-- Decision -->
        <section class="card side-card">
          <h2 class="side-title">{$t(isOpen ? 'admin.reports.actions' : 'admin.reports.outcome')}</h2>
          {#if isOpen}
            {#if report.assigned_moderator}
              <p class="side-text">
                {$t('admin.reports.assigned_to')}
                <a href="/@{report.assigned_moderator.handle}">@{report.assigned_moderator.handle}</a>
              </p>
            {/if}
            {#if !assignedToMe}
              <button class="btn btn-outline btn-full" type="button" disabled={acting} onclick={handleAssign}>
                {$t('admin.reports.assign_me')}
              </button>
            {/if}
            <label class="field-label" for="action-note">{$t('admin.reports.action_note')}</label>
            <input
              id="action-note"
              class="input"
              maxlength="255"
              placeholder={$t('admin.reports.action_note_placeholder')}
              bind:value={actionNote}
            />
            <button class="btn btn-primary btn-full" type="button" disabled={acting} onclick={handleResolve}>
              {$t('admin.reports.resolve')}
            </button>
            <button class="btn btn-ghost btn-full" type="button" disabled={acting} onclick={handleDismiss}>
              {$t('admin.reports.dismiss')}
            </button>
            <p class="hint">{$t('admin.reports.enforcement_hint')}</p>
          {:else}
            <dl class="meta-list">
              <dt>{$t('admin.reports.status')}</dt>
              <dd><span class="status-badge status-{report.status}">{statusLabel(report.status)}</span></dd>
              {#if report.action_taken}
                <dt>{$t('admin.reports.action_taken')}</dt>
                <dd>{report.action_taken}</dd>
              {/if}
              <dt>{$t('admin.reports.closed_at')}</dt>
              <dd>{formatDate(report.resolved_at)}</dd>
              {#if report.assigned_moderator}
                <dt>{$t('admin.reports.handled_by')}</dt>
                <dd><a href="/@{report.assigned_moderator.handle}">@{report.assigned_moderator.handle}</a></dd>
              {/if}
            </dl>
          {/if}
        </section>

        <!-- Reported account -->
        <section class="card side-card">
          <h2 class="side-title">{$t('admin.reports.reported_account')}</h2>
          {#if report.target_account}
            {@const acct = report.target_account}
            <a class="person" href="/@{acct.acct || acct.handle}">
              {#if acct.avatar_url}
                <img class="person-avatar" src={acct.avatar_url} alt="" />
              {/if}
              <span class="person-names">
                <span class="person-name">{acct.display_name || acct.handle}</span>
                <span class="muted">@{acct.acct || acct.handle}</span>
              </span>
            </a>
            <div class="person-badges">
              {#if acct.is_suspended}<span class="badge badge-danger">{$t('admin.reports.suspended')}</span>{/if}
              {#if acct.is_silenced}<span class="badge badge-warning">{$t('admin.reports.silenced')}</span>{/if}
            </div>
            <p class="side-text">
              {$t('admin.reports.open_against')}
              <strong class:stat-hot={report.reported_open_reports > 1}>{report.reported_open_reports}</strong>
            </p>
            <a class="side-link" href="/admin/user-management/users/{acct.id}">{$t('admin.reports.manage_user')} →</a>
          {:else}
            <p class="muted">{$t('admin.reports.account_gone')}</p>
          {/if}
        </section>

        <!-- Reporter -->
        <section class="card side-card">
          <h2 class="side-title">{$t('admin.reports.reporter')}</h2>
          {#if report.reporter}
            {@const rep = report.reporter}
            <a class="person" href="/@{rep.acct || rep.handle}">
              {#if rep.avatar_url}
                <img class="person-avatar" src={rep.avatar_url} alt="" />
              {/if}
              <span class="person-names">
                <span class="person-name">{rep.display_name || rep.handle}</span>
                <span class="muted">@{rep.acct || rep.handle}</span>
              </span>
            </a>
            <a class="side-link" href="/admin/user-management/users/{rep.id}">{$t('admin.reports.manage_user')} →</a>
          {:else}
            <p class="muted">{$t('admin.reports.account_gone')}</p>
          {/if}
        </section>

        <!-- Metadata -->
        <section class="card side-card">
          <h2 class="side-title">{$t('admin.reports.details')}</h2>
          <dl class="meta-list">
            <dt>{$t('admin.reports.report_id')}</dt>
            <dd class="mono">{report.id}</dd>
            <dt>{$t('admin.reports.filed')}</dt>
            <dd>{formatDate(report.created_at)}</dd>
            <dt>{$t('admin.reports.queue')}</dt>
            <dd>{$t(report.tier === 'group' ? 'admin.reports.tier_group' : 'admin.reports.tier_instance')}</dd>
            {#if report.group}
              <dt>{$t('admin.reports.group')}</dt>
              <dd>{report.group.name}</dd>
            {/if}
            {#if report.escalated_at}
              <dt>{$t('admin.reports.escalated')}</dt>
              <dd>{formatDate(report.escalated_at)}</dd>
            {/if}
          </dl>
        </section>
      </aside>
    </div>
  {/if}
</div>

<style>
  .report-detail-page {
    max-width: 1200px;
  }

  .back-link {
    display: inline-block;
    margin-block-end: var(--space-4);
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
    text-decoration: none;
  }

  .back-link:hover {
    color: var(--color-primary);
  }

  .not-found {
    padding: var(--space-8);
    text-align: center;
  }

  .not-found-title {
    font-size: var(--text-xl);
    font-weight: 700;
    margin-block-end: var(--space-2);
  }

  .page-header {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    margin-block-end: var(--space-4);
  }

  .page-title {
    display: flex;
    align-items: baseline;
    gap: var(--space-2);
    font-size: var(--text-xl);
    font-weight: 700;
  }

  .header-badges {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-2);
  }

  .header-date {
    font-size: var(--text-sm);
  }

  .layout {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 320px;
    gap: var(--space-4);
    align-items: flex-start;
  }

  .main-col,
  .side-col {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
    min-width: 0;
  }

  .side-col {
    gap: var(--space-3);
    position: sticky;
    inset-block-start: var(--space-4);
  }

  .section {
    padding: var(--space-5);
  }

  .section-header {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    margin-block-end: var(--space-3);
  }

  .section-title {
    font-size: var(--text-base);
    font-weight: 700;
    margin-block-end: var(--space-3);
  }

  .section-header .section-title {
    margin-block-end: 0;
  }

  .section-count {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
    background: var(--color-surface);
    padding: 2px 8px;
    border-radius: var(--radius-full);
  }

  .report-category {
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-size: var(--text-xs);
    color: var(--color-danger);
  }

  .page-title .report-category {
    font-size: var(--text-sm);
  }

  .status-badge,
  .badge {
    font-size: 0.7rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    padding: 2px 8px;
    border-radius: var(--radius-full);
    white-space: nowrap;
  }

  .status-pending,
  .badge-warning {
    background: var(--color-warning-soft);
    color: var(--color-on-warning-soft);
  }

  .status-investigating,
  .badge-info {
    background: var(--color-info-soft);
    color: var(--color-on-info-soft);
  }

  .status-resolved {
    background: var(--color-success-soft);
    color: var(--color-on-success-soft);
  }

  .status-dismissed,
  .badge-neutral {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }

  .badge-danger {
    background: var(--color-danger-soft);
    color: var(--color-on-danger-soft);
  }

  .reason-category {
    font-size: var(--text-sm);
    margin-block-end: var(--space-2);
    text-transform: capitalize;
  }

  .reason-note {
    margin: 0;
    padding: var(--space-3);
    background: var(--color-surface);
    border-inline-start: 3px solid var(--color-danger);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    white-space: pre-wrap;
    word-break: break-word;
  }

  .post-preview {
    padding: var(--space-4);
    background: var(--color-surface);
    border-radius: var(--radius-md);
  }

  .post-deleted {
    opacity: 0.65;
  }

  .post-preview-head {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    gap: var(--space-2);
    font-size: var(--text-sm);
    margin-block-end: var(--space-3);
  }

  .author-name {
    font-weight: 700;
    color: var(--color-text);
    text-decoration: none;
  }

  .spoiler {
    font-size: var(--text-sm);
    padding: var(--space-2) var(--space-3);
    background: var(--color-warning-soft);
    color: var(--color-on-warning-soft);
    border-radius: var(--radius-md);
    margin-block-end: var(--space-3);
  }

  .post-body {
    font-size: var(--text-base);
    line-height: 1.6;
    word-break: break-word;
  }

  .post-body-plain {
    white-space: pre-wrap;
  }

  .media-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
    gap: var(--space-2);
    margin-block-start: var(--space-3);
  }

  .media-thumb {
    width: 100%;
    max-height: 240px;
    object-fit: cover;
    border-radius: var(--radius-md);
    background: var(--color-surface);
  }

  .media-unknown {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 120px;
    border-radius: var(--radius-md);
    color: var(--color-text-secondary);
    font-size: var(--text-xs);
    font-family: var(--font-mono);
  }

  .link-row {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2);
    margin-block-start: var(--space-3);
  }

  .timeline,
  .related-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .timeline-row {
    padding-block: var(--space-2);
    padding-inline-start: var(--space-3);
    border-inline-start: 2px solid var(--color-border);
    font-size: var(--text-sm);
  }

  .timeline-action {
    font-weight: 600;
    margin-inline-end: var(--space-1);
  }

  .timeline-note {
    margin-block-start: var(--space-1);
    color: var(--color-text-secondary);
  }

  .related-row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3);
    background: var(--color-surface);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    color: inherit;
    text-decoration: none;
  }

  .related-row:hover {
    background: var(--color-surface-hover, var(--color-surface));
    color: var(--color-primary);
  }

  .side-card {
    padding: var(--space-4);
  }

  .side-title {
    font-size: var(--text-sm);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-secondary);
    margin-block-end: var(--space-3);
  }

  .side-text {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block: var(--space-2);
  }

  .side-link {
    display: inline-block;
    margin-block-start: var(--space-2);
    font-size: var(--text-sm);
    color: var(--color-primary);
    text-decoration: none;
  }

  .field-label {
    display: block;
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
    margin-block: var(--space-2) var(--space-1);
  }

  .side-card .input {
    width: 100%;
    margin-block-end: var(--space-2);
  }

  .btn-full {
    display: block;
    width: 100%;
    margin-block-end: var(--space-2);
  }

  .hint {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-start: var(--space-2);
  }

  .person {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    color: inherit;
    text-decoration: none;
    min-width: 0;
  }

  .person-avatar {
    width: 40px;
    height: 40px;
    border-radius: var(--radius-full);
    object-fit: cover;
    flex-shrink: 0;
  }

  .person-names {
    display: flex;
    flex-direction: column;
    min-width: 0;
    font-size: var(--text-sm);
  }

  .person-name {
    font-weight: 700;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .person-badges {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-1);
    margin-block-start: var(--space-2);
  }

  .stat-hot {
    color: var(--color-danger);
  }

  .meta-list {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: var(--space-2) var(--space-3);
    margin: 0;
    font-size: var(--text-xs);
  }

  .meta-list dt {
    color: var(--color-text-secondary);
    font-weight: 600;
  }

  .meta-list dd {
    margin: 0;
    min-width: 0;
    word-break: break-word;
  }

  .mono {
    font-family: var(--font-mono);
  }

  .muted {
    color: var(--color-text-tertiary);
  }

  @media (max-width: 1000px) {
    .layout {
      grid-template-columns: 1fr;
    }

    .side-col {
      position: static;
    }
  }
</style>
