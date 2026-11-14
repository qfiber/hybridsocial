<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { browser } from '$app/environment';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import DataTable from '$lib/components/admin/DataTable.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { t } from '$lib/stores/i18n.js';
  import { ApiError } from '$lib/api/client.js';
  import {
    getReports, resolveReport, dismissReport,
    getVerifications, approveVerification, rejectVerification,
  } from '$lib/api/admin.js';
  import ModerationQueuePanel from '$lib/components/admin/ModerationQueuePanel.svelte';
  import type { AdminReport } from '$lib/api/types.js';
  import type { VerificationRequest } from '$lib/api/admin.js';
  const tabs = [
    { id: 'reports', label: 'Reports' },
    { id: 'verifications', label: 'Verifications' },
    { id: 'queue', label: 'Queue' },
  ];

  const validTabs = tabs.map((tab) => tab.id);
  const BLOCKLIST_TABS = ['filters', 'ipblocks', 'email-domains', 'media-hashes', 'hashtags'];

  let activeTab = $state('reports');

  // Verification requests state
  let verifications: VerificationRequest[] = $state([]);
  let verificationsLoading = $state(false);
  let verificationsLoaded = $state(false);
  let verificationStatusFilter = $state('pending');
  // Which request (if any) is mid-rejection, plus the reason being typed.
  let rejectingId = $state<string | null>(null);
  let rejectReason = $state('');

  // Reports state. The status filter is applied by the server: loading
  // one unfiltered page and filtering it here only ever showed the newest
  // 20 reports, so anything older silently never appeared.
  const REPORTS_PAGE_SIZE = 50;
  const OPEN_STATUSES = ['pending', 'investigating'];
  let reports: AdminReport[] = $state([]);
  let reportsLoading = $state(true);
  let reportsLoadingMore = $state(false);
  let reportsHasMore = $state(false);
  let reportStatusFilter = $state('open');

  function matchesReportFilter(status: string, filter: string): boolean {
    if (filter === 'all') return true;
    if (filter === 'open') return OPEN_STATUSES.includes(status);
    return status === filter;
  }

  // Server-filtered, but re-checked locally so a report resolved from
  // this page drops out of the Open/Pending view straight away.
  let filteredReports = $derived(
    reports.filter((r) => matchesReportFilter(r.status, reportStatusFilter))
  );

  let reportRows = $derived(
    filteredReports.map((r) => ({ ...r } as Record<string, unknown>))
  );

  const reportColumns = [
    { key: 'category', label: 'Category', sortable: true },
    { key: 'target', label: 'Target' },
    { key: 'reporter', label: 'Reporter' },
    { key: 'content', label: 'What was reported' },
    { key: 'status', label: 'Status', sortable: true },
    { key: 'created_at', label: 'Date', sortable: true },
    { key: 'actions', label: 'Actions', width: '200px' }
  ];

  function stripTags(html: string | null | undefined): string {
    if (!html) return '';
    return html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
  }

  function truncate(s: string, n: number): string {
    return s.length > n ? s.slice(0, n).trim() + '…' : s;
  }

  onMount(async () => {
    // Legacy URL support: AdminPostActions used to link here with
    // `?post=<id>` which never did anything. Redirect to the real
    // per-post admin view so old bookmarks and cached pages still
    // land somewhere useful.
    if (browser) {
      const params = new URL(window.location.href).searchParams;
      const postId = params.get('post');
      if (postId) {
        goto(`/admin/posts/${encodeURIComponent(postId)}`, { replaceState: true });
        return;
      }
      // Deep-link support so the dashboard's "Verifications" card (and
      // any other) can open straight to a specific tab.
      const tab = params.get('tab');
      // The blocklist tabs moved to their own page; keep old links working.
      if (tab && BLOCKLIST_TABS.includes(tab)) {
        goto(`/admin/moderation/blocklists?tab=${tab}`, { replaceState: true });
        return;
      }
      if (tab && validTabs.includes(tab)) {
        activeTab = tab;
      }
    }

    await loadReports();
  });

  async function fetchReportsPage(offset: number): Promise<AdminReport[]> {
    const params: Record<string, string> = {
      limit: String(REPORTS_PAGE_SIZE),
      offset: String(offset)
    };
    if (reportStatusFilter !== 'all') params.status = reportStatusFilter;
    const result = await getReports(params);
    return result.data ?? [];
  }

  async function loadReports() {
    reportsLoading = true;
    try {
      const page = await fetchReportsPage(0);
      reports = page;
      reportsHasMore = page.length === REPORTS_PAGE_SIZE;
    } catch {
      addToast($t('admin.reports.load_failed'), 'error');
    } finally {
      reportsLoading = false;
    }
  }

  async function loadMoreReports() {
    if (reportsLoadingMore) return;
    reportsLoadingMore = true;
    try {
      const page = await fetchReportsPage(reports.length);
      const seen = new Set(reports.map((r) => r.id));
      reports = [...reports, ...page.filter((r) => !seen.has(r.id))];
      reportsHasMore = page.length === REPORTS_PAGE_SIZE;
    } catch {
      addToast($t('admin.reports.load_failed'), 'error');
    } finally {
      reportsLoadingMore = false;
    }
  }

  async function loadVerifications() {
    verificationsLoading = true;
    try {
      // Fetch the full history (all statuses) so the in-page filter can
      // switch between pending / approved / rejected without refetching.
      verifications = await getVerifications({ limit: '200' });
    } catch {
      addToast('Failed to load verification requests', 'error');
    } finally {
      verificationsLoading = false;
      verificationsLoaded = true;
    }
  }

  let filteredVerifications = $derived(
    verificationStatusFilter === 'all'
      ? verifications
      : verifications.filter((v) => v.status === verificationStatusFilter)
  );

  async function handleApproveVerification(id: string) {
    try {
      await approveVerification(id);
      verifications = verifications.map((v) =>
        v.id === id ? { ...v, status: 'approved', rejection_reason: null } : v
      );
      if (rejectingId === id) rejectingId = null;
      addToast('Verification approved', 'success');
    } catch (err) {
      addToast(
        err instanceof ApiError && err.status === 409
          ? $t('admin.verification_not_pending')
          : 'Failed to approve verification',
        'error',
      );
    }
  }

  function startReject(id: string) {
    rejectingId = id;
    rejectReason = '';
  }

  function cancelReject() {
    rejectingId = null;
    rejectReason = '';
  }

  async function confirmReject(id: string) {
    try {
      const reason = rejectReason.trim();
      const updated = await rejectVerification(id, reason || undefined);
      verifications = verifications.map((v) =>
        v.id === id ? { ...v, status: 'rejected', rejection_reason: updated.rejection_reason } : v
      );
      rejectingId = null;
      rejectReason = '';
      addToast('Verification rejected', 'success');
    } catch (err) {
      addToast(
        err instanceof ApiError && err.status === 409
          ? $t('admin.verification_not_pending')
          : 'Failed to reject verification',
        'error',
      );
    }
  }

  $effect(() => {
    if (activeTab === 'verifications' && !verificationsLoaded && !verificationsLoading) {
      loadVerifications();
    }
  });

  async function handleResolve(report: AdminReport) {
    try {
      await resolveReport(report.id);
      // Replace immutably so Svelte reliably re-derives filteredReports.
      reports = reports.map((r) =>
        r.id === report.id ? { ...r, status: 'resolved' as const } : r
      );
      addToast(
        reportStatusFilter === 'pending'
          ? 'Report resolved — moved to the Resolved filter'
          : 'Report resolved',
        'success'
      );
    } catch {
      addToast('Failed to resolve report', 'error');
    }
  }

  async function handleDismiss(report: AdminReport) {
    try {
      await dismissReport(report.id);
      reports = reports.map((r) =>
        r.id === report.id ? { ...r, status: 'dismissed' as const } : r
      );
      addToast(
        reportStatusFilter === 'pending'
          ? 'Report dismissed — moved to the Dismissed filter'
          : 'Report dismissed',
        'success'
      );
    } catch {
      addToast('Failed to dismiss report', 'error');
    }
  }

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  }

</script>

<svelte:head>
  <title>Moderation - Admin</title>
</svelte:head>

<div class="moderation-page">
  <h1 class="page-title">Moderation</h1>

  <Tabs {tabs} bind:active={activeTab}>
    {#if activeTab === 'reports'}
      <div class="tab-toolbar">
        <select
          class="input"
          style="width: 160px"
          bind:value={reportStatusFilter}
          onchange={loadReports}
          aria-label={$t('admin.reports.filter_label')}
        >
          <option value="open">{$t('admin.reports.filter_open')}</option>
          <option value="pending">{$t('admin.reports.status_pending')}</option>
          <option value="investigating">{$t('admin.reports.status_investigating')}</option>
          <option value="resolved">{$t('admin.reports.status_resolved')}</option>
          <option value="dismissed">{$t('admin.reports.status_dismissed')}</option>
          <option value="all">{$t('admin.reports.filter_all')}</option>
        </select>
        <span class="retention-note" aria-live="polite">
          Resolved and dismissed reports are kept for 90 days, then deleted. Pending reports are never deleted automatically.
        </span>
      </div>

      <DataTable
        columns={reportColumns}
        rows={reportRows}
        loading={reportsLoading}
        emptyMessage="No reports found"
      >
        {#snippet rowContent(row)}
          {@const targetAccount = (row['target_account'] as Record<string, any>) ?? null}
          {@const reporter = (row['reporter'] as Record<string, any>) ?? null}
          {@const targetPost = (row['target_post'] as Record<string, any>) ?? null}
          {@const targetHandle = targetAccount?.acct || targetAccount?.handle || 'unknown'}
          {@const reporterHandle = reporter?.acct || reporter?.handle || 'unknown'}
          {@const reportComment = (row['comment'] || row['description']) as string | undefined}
          {@const postText = targetPost ? truncate(stripTags(targetPost.content_html || targetPost.content), 200) : ''}

          <td><span class="report-category">{(row['category'] as string).replace(/_/g, ' ')}</span></td>

          <td>
            {#if targetAccount?.id}
              <a href="/@{targetHandle}" class="report-account-link">@{targetHandle}</a>
            {:else}
              @{targetHandle}
            {/if}
          </td>

          <td>
            {#if reporter?.id}
              <a href="/@{reporterHandle}" class="report-account-link">@{reporterHandle}</a>
            {:else}
              @{reporterHandle}
            {/if}
          </td>

          <td class="report-content-cell">
            {#if reportComment}
              <div class="report-comment">
                <span class="report-meta-label">Reporter's note:</span>
                <span>{reportComment}</span>
              </div>
            {/if}
            {#if row['target_type'] === 'post'}
              {#if targetPost}
                <a
                  href={`/post/${targetPost.id}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="report-post-preview"
                >
                  {#if postText}
                    <span class="report-post-text">{postText}</span>
                  {:else}
                    <span class="report-post-empty">(no text — media only)</span>
                  {/if}
                  <span class="material-symbols-outlined report-post-open">open_in_new</span>
                </a>
                {#if targetPost.deleted_at}
                  <span class="report-deleted-badge">Post already deleted</span>
                {/if}
              {:else}
                <span class="report-post-missing">
                  Post not found (id: <code>{row['target_id']}</code>)
                </span>
              {/if}
            {:else if row['target_type'] === 'account' || row['target_type'] === 'user'}
              <span class="report-meta-label">Account report</span>
            {/if}
            {#if !reportComment && row['target_type'] !== 'post'}
              <span class="report-post-empty">—</span>
            {/if}
          </td>

          <td>
            <span class="status-badge status-{row['status']}">
              {row['status']}
            </span>
          </td>
          <td>
            <a class="report-date-link" href="/admin/moderation/reports/{row['id']}">
              {formatDate(row['created_at'] as string)}
            </a>
          </td>
          <td>
            <div class="action-buttons">
              <a class="btn btn-sm btn-outline" href="/admin/moderation/reports/{row['id']}">
                {$t('admin.reports.view_details')}
              </a>
            {#if OPEN_STATUSES.includes(row['status'] as string)}
                <button
                  class="btn btn-sm btn-primary"
                  type="button"
                  onclick={() => handleResolve(row as unknown as AdminReport)}
                >Resolve</button>
                <button
                  class="btn btn-sm btn-ghost"
                  type="button"
                  onclick={() => handleDismiss(row as unknown as AdminReport)}
                >Dismiss</button>
            {/if}
            </div>
          </td>
        {/snippet}
      </DataTable>

      {#if reportsHasMore && !reportsLoading}
        <div class="load-more-row">
          <button
            class="btn btn-outline"
            type="button"
            disabled={reportsLoadingMore}
            onclick={loadMoreReports}
          >
            {reportsLoadingMore ? $t('admin.reports.loading') : $t('admin.reports.load_more')}
          </button>
        </div>
      {/if}

    {:else if activeTab === 'verifications'}
      <div class="tab-toolbar">
        <select class="input" style="width: 160px" bind:value={verificationStatusFilter}>
          <option value="pending">Pending</option>
          <option value="approved">Approved</option>
          <option value="rejected">Rejected</option>
          <option value="all">All</option>
        </select>
        <span class="retention-note">
          Users request a verified badge here. Approving grants it; rejecting lets you record a reason
          the reviewer (and any audit) can refer back to.
        </span>
      </div>

      {#if verificationsLoading}
        <div class="skeleton" style="height: 72px"></div>
      {:else}
        <div class="list-items">
          {#each filteredVerifications as req (req.id)}
            <div class="verify-item card">
              <div class="verify-main">
                <div class="verify-avatar">
                  {#if req.account?.avatar_url}
                    <img src={req.account.avatar_url} alt="" class="verify-img" />
                  {:else}
                    <span class="verify-initial">
                      {(req.account?.display_name || req.account?.handle || '?').charAt(0).toUpperCase()}
                    </span>
                  {/if}
                </div>
                <div class="verify-info">
                  <div class="verify-identity">
                    {#if req.account?.id}
                      <a href="/@{req.account.handle}" class="verify-name">
                        {req.account.display_name || req.account.handle}
                      </a>
                    {:else}
                      <span class="verify-name">{req.account?.display_name || req.account?.handle || 'Unknown'}</span>
                    {/if}
                    <span class="verify-handle">@{req.account?.handle}</span>
                    <span class="badge-type">{(req.type || '').replace(/_/g, ' ')}</span>
                    <span class="status-badge status-{req.status}">{req.status}</span>
                  </div>
                  {#if req.metadata?.reason}
                    <p class="verify-reason"><span class="report-meta-label">Reason given:</span> {req.metadata.reason}</p>
                  {/if}
                  {#if req.type === 'peer_vouch'}
                    <p class="verify-reason">{$t('admin.verification_vouches', { count: req.vouch_count ?? 0 })}</p>
                  {/if}
                  {#if req.metadata?.domain}
                    <p class="verify-reason"><span class="report-meta-label">Domain:</span> {req.metadata.domain}</p>
                  {/if}
                  {#if req.status === 'rejected' && req.rejection_reason}
                    <p class="verify-rejection"><span class="report-meta-label">Rejected because:</span> {req.rejection_reason}</p>
                  {/if}
                  <span class="verify-date">Requested {formatDate(req.created_at)}</span>
                </div>
              </div>

              {#if req.status === 'pending'}
                {#if rejectingId === req.id}
                  <form class="verify-reject-form" onsubmit={(e) => { e.preventDefault(); confirmReject(req.id); }}>
                    <input
                      class="input"
                      type="text"
                      bind:value={rejectReason}
                      placeholder="Reason for rejection (optional)"
                    />
                    <button class="btn btn-sm btn-danger" type="submit">Confirm reject</button>
                    <button class="btn btn-sm btn-ghost" type="button" onclick={cancelReject}>Cancel</button>
                  </form>
                {:else}
                  <div class="action-buttons">
                    <button class="btn btn-sm btn-primary" type="button" onclick={() => handleApproveVerification(req.id)}>Approve</button>
                    <button class="btn btn-sm btn-ghost" type="button" onclick={() => startReject(req.id)}>Reject</button>
                  </div>
                {/if}
              {/if}
            </div>
          {:else}
            <p class="empty-text">No {verificationStatusFilter === 'all' ? '' : verificationStatusFilter} verification requests</p>
          {/each}
        </div>
      {/if}

    {:else if activeTab === 'queue'}
      <!-- Auto-flagged content (NSFW heuristics, link-shortener bursts,
           etc.) — formerly its own /admin/moderation-queue route. The
           panel manages its own load + filter state so opening the
           Queue tab triggers the fetch lazily. -->
      <ModerationQueuePanel />

    {/if}
  </Tabs>
</div>

<style>
  .moderation-page {
    max-width: 1100px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-6);
  }

  .tab-toolbar {
    margin-block-end: var(--space-4);
    display: flex;
    align-items: center;
    gap: var(--space-4);
    flex-wrap: wrap;
  }

  .report-category {
    font-weight: 600;
    text-transform: capitalize;
  }

  .status-badge {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    text-transform: capitalize;
  }

  .status-pending {
    background: var(--color-warning-soft);
    color: var(--color-on-warning-soft);
  }

  .status-resolved {
    background: var(--color-success-soft);
    color: var(--color-on-success-soft);
  }

  .status-investigating {
    background: var(--color-info-soft);
    color: var(--color-on-info-soft);
  }

  .load-more-row {
    display: flex;
    justify-content: center;
    margin-block-start: var(--space-4);
  }

  .report-date-link {
    color: inherit;
    text-decoration: none;
  }

  .report-date-link:hover {
    color: var(--color-primary);
    text-decoration: underline;
  }

  .status-dismissed {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }

  .action-buttons {
    display: flex;
    gap: var(--space-2);
  }

  .list-items {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .badge-type {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    background: var(--color-info-soft);
    color: var(--color-on-info-soft);
    text-transform: uppercase;
  }

  .empty-text {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    text-align: center;
    padding: var(--space-6) 0;
  }

  .report-content-cell {
    max-width: 360px;
    padding-inline-start: var(--space-4) !important;
  }

  /* Widen the handle cells + keep the whole handle on one line so a
     long acct like @user@example.social can't collide with the next
     column's content. */
  :global(.data-table td:nth-child(2)),
  :global(.data-table td:nth-child(3)) {
    min-width: 140px;
    padding-inline-end: var(--space-6) !important;
  }

  .report-comment {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    line-height: 1.4;
    margin-block-end: 6px;
  }

  .report-meta-label {
    font-size: 0.65rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-tertiary);
    font-weight: 600;
    margin-inline-end: 4px;
  }

  .report-post-preview {
    display: flex;
    align-items: flex-start;
    gap: 6px;
    padding: 6px 8px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-surface);
    text-decoration: none;
    color: var(--color-text);
    font-size: var(--text-xs);
    line-height: 1.4;
    transition: background 0.15s ease, border-color 0.15s ease;
  }

  .report-post-preview:hover {
    background: var(--color-surface-container-low, var(--color-surface));
    border-color: var(--color-primary);
    text-decoration: none;
  }

  .report-post-text {
    flex: 1;
    display: -webkit-box;
    -webkit-line-clamp: 3;
    -webkit-box-orient: vertical;
    overflow: hidden;
    word-break: break-word;
  }

  .report-post-empty {
    color: var(--color-text-tertiary);
    font-style: italic;
    font-size: var(--text-xs);
  }

  .report-post-open {
    font-size: 14px !important;
    color: var(--color-text-tertiary);
    flex-shrink: 0;
  }

  .report-post-missing {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .report-post-missing code {
    font-size: 0.65rem;
  }

  .report-deleted-badge {
    display: inline-block;
    margin-block-start: 4px;
    padding: 2px 6px;
    font-size: 0.65rem;
    font-weight: 600;
    color: var(--color-on-danger-soft);
    background: var(--color-danger-soft);
    border-radius: var(--radius-sm);
  }

  .retention-note {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    line-height: 1.4;
    max-width: 480px;
  }

  .badge-type {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    background: var(--color-info-soft);
    color: var(--color-on-info-soft);
    text-transform: uppercase;
  }

  .report-account-link {
    color: var(--color-primary);
    text-decoration: none;
    /* Never split a handle across a column boundary — keeps
       @long@domain.social from running into the next cell. */
    white-space: nowrap;
    overflow-wrap: normal;
    word-break: keep-all;
    display: inline-block;
    max-width: 100%;
  }

  .report-account-link:hover {
    text-decoration: underline;
  }

  .status-approved {
    background: var(--color-success-soft);
    color: var(--color-on-success-soft);
  }

  .status-rejected {
    background: var(--color-danger-soft);
    color: var(--color-on-danger-soft);
  }

  /* Verification requests list */
  .verify-item {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-4);
    flex-wrap: wrap;
  }

  .verify-main {
    display: flex;
    align-items: flex-start;
    gap: var(--space-3);
    flex: 1;
    min-width: 240px;
  }

  .verify-avatar {
    flex-shrink: 0;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    overflow: hidden;
    background: var(--color-surface);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .verify-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .verify-initial {
    font-weight: 600;
    color: var(--color-text-secondary);
  }

  .verify-info {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }

  .verify-identity {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-wrap: wrap;
  }

  .verify-name {
    font-weight: 600;
    color: var(--color-text);
    text-decoration: none;
  }

  a.verify-name:hover {
    text-decoration: underline;
  }

  .verify-handle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .verify-reason,
  .verify-rejection {
    font-size: var(--text-sm);
    line-height: 1.4;
    margin: 0;
    color: var(--color-text-secondary);
  }

  .verify-rejection {
    color: var(--color-on-danger-soft);
  }

  .verify-date {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .verify-reject-form {
    display: flex;
    gap: var(--space-2);
    align-items: center;
    flex-wrap: wrap;
  }

  .verify-reject-form .input {
    min-width: 220px;
  }
</style>
