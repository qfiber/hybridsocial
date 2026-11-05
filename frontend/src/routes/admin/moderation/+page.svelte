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
    getContentFilters, createContentFilter, deleteContentFilter,
    getIpBlocks, createIpBlock, deleteIpBlock,
    getEmailDomainBans, createEmailDomainBan, deleteEmailDomainBan,
    getMediaHashBans, createMediaHashBan, deleteMediaHashBan,
    getHashtagBlocks, createHashtagBlock, deleteHashtagBlock,
    getVerifications, approveVerification, rejectVerification,
  } from '$lib/api/admin.js';
  import ModerationQueuePanel from '$lib/components/admin/ModerationQueuePanel.svelte';
  import type {
    AdminReport, ContentFilter, IpBlock,
    EmailDomainBan, MediaHashBan, HashtagBlock,
  } from '$lib/api/types.js';
  import type { VerificationRequest } from '$lib/api/admin.js';

  const tabs = [
    { id: 'reports', label: 'Reports' },
    { id: 'verifications', label: 'Verifications' },
    { id: 'queue', label: 'Queue' },
    { id: 'filters', label: 'Content Filters' },
    { id: 'ipblocks', label: 'IP Blocks' },
    { id: 'email-domains', label: 'Email Domains' },
    { id: 'media-hashes', label: 'Media Hashes' },
    { id: 'hashtags', label: $t('admin.moderation.hashtags.tab') },
  ];

  const validTabs = tabs.map((tab) => tab.id);

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

  // Content Filters state
  let filters: ContentFilter[] = $state([]);
  let filtersLoading = $state(false);
  let newFilterType = $state<'word' | 'phrase' | 'regex'>('word');
  let newFilterPattern = $state('');
  let newFilterAction = $state<'flag' | 'reject'>('flag');

  // Banned Domains state

  // IP Blocks state
  let ipBlocks: IpBlock[] = $state([]);
  let ipBlocksLoading = $state(false);
  let filtersLoaded = $state(false);
  let ipBlocksLoaded = $state(false);
  let newIp = $state('');
  let newIpSubnetMask = $state('');
  let newIpReason = $state('');

  // Email-domain bans state (reject registration from these domains).
  let emailBans: EmailDomainBan[] = $state([]);
  let emailBansLoading = $state(false);
  let emailBansLoaded = $state(false);
  let newEmailDomain = $state('');
  let newEmailReason = $state('');

  // Media-hash bans state (reject uploads / federated attachments
  // matching these known-bad hashes).
  let mediaHashBans: MediaHashBan[] = $state([]);
  let mediaHashBansLoading = $state(false);
  let mediaHashBansLoaded = $state(false);
  let hashtagBlocks: HashtagBlock[] = $state([]);
  let hashtagBlocksLoading = $state(false);
  let hashtagBlocksLoaded = $state(false);
  let newHashtags = $state('');
  let newHashtagAction = $state<HashtagBlock['action']>('no_trending');
  let newHashtagReason = $state('');
  let newHash = $state('');
  let newHashDescription = $state('');

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
    } catch {
      addToast('Failed to approve verification', 'error');
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
    } catch {
      addToast('Failed to reject verification', 'error');
    }
  }

  async function loadFilters() {
    filtersLoading = true;
    try {
      filters = await getContentFilters();
    } catch {
      addToast('Failed to load content filters', 'error');
    } finally {
      filtersLoading = false;
      filtersLoaded = true;
    }
  }

  async function loadIpBlocks() {
    ipBlocksLoading = true;
    try {
      ipBlocks = await getIpBlocks();
    } catch {
      addToast('Failed to load IP blocks', 'error');
    } finally {
      ipBlocksLoading = false;
      ipBlocksLoaded = true;
    }
  }

  async function loadEmailBans() {
    emailBansLoading = true;
    try {
      emailBans = await getEmailDomainBans();
    } catch {
      addToast('Failed to load email domain bans', 'error');
    } finally {
      emailBansLoading = false;
      emailBansLoaded = true;
    }
  }

  async function loadMediaHashBans() {
    mediaHashBansLoading = true;
    try {
      mediaHashBans = await getMediaHashBans();
    } catch {
      addToast('Failed to load media hash bans', 'error');
    } finally {
      mediaHashBansLoading = false;
      mediaHashBansLoaded = true;
    }
  }

  $effect(() => {
    if (activeTab === 'verifications' && !verificationsLoaded && !verificationsLoading) {
      loadVerifications();
    } else if (activeTab === 'filters' && !filtersLoaded && !filtersLoading) {
      loadFilters();
    } else if (activeTab === 'ipblocks' && !ipBlocksLoaded && !ipBlocksLoading) {
      loadIpBlocks();
    } else if (activeTab === 'email-domains' && !emailBansLoaded && !emailBansLoading) {
      loadEmailBans();
    } else if (activeTab === 'media-hashes' && !mediaHashBansLoaded && !mediaHashBansLoading) {
      loadMediaHashBans();
    } else if (activeTab === 'hashtags' && !hashtagBlocksLoaded && !hashtagBlocksLoading) {
      loadHashtagBlocks();
    }
  });

  async function loadHashtagBlocks() {
    hashtagBlocksLoading = true;
    try {
      hashtagBlocks = await getHashtagBlocks();
    } catch {
      addToast($t('admin.moderation.hashtags.load_failed'), 'error');
    } finally {
      hashtagBlocksLoading = false;
      hashtagBlocksLoaded = true;
    }
  }

  // Accepts several tags at once, since spam tends to arrive as a batch. Each
  // saves on its own, so one bad entry doesn't lose the others: failures stay
  // in the input to be corrected.
  async function handleAddHashtagBlocks() {
    const names = [...new Set(newHashtags.split(/[\s,]+/).filter(Boolean))];
    if (names.length === 0) return;

    const results = await Promise.allSettled(
      names.map((name) =>
        createHashtagBlock({
          name,
          action: newHashtagAction,
          reason: newHashtagReason.trim() || null
        })
      )
    );

    const saved = results.flatMap((r) => (r.status === 'fulfilled' ? [r.value] : []));
    const failed = names.filter((_, i) => results[i].status === 'rejected');
    const savedNames = new Set(saved.map((b) => b.name));

    // A re-blocked tag updates its existing row rather than adding one.
    hashtagBlocks = [...saved, ...hashtagBlocks.filter((b) => !savedNames.has(b.name))];
    newHashtags = failed.join(' ');

    if (failed.length > 0) {
      addToast($t('admin.moderation.hashtags.add_failed', { tags: failed.join(' ') }), 'error');
    } else {
      newHashtagReason = '';
      addToast($t('admin.moderation.hashtags.added'), 'success');
    }
  }

  async function handleRemoveHashtagBlock(id: string) {
    try {
      await deleteHashtagBlock(id);
      hashtagBlocks = hashtagBlocks.filter((b) => b.id !== id);
      addToast($t('admin.moderation.hashtags.removed'), 'success');
    } catch {
      addToast($t('admin.moderation.hashtags.remove_failed'), 'error');
    }
  }

  async function handleAddEmailBan() {
    if (!newEmailDomain.trim()) return;
    try {
      const ban = await createEmailDomainBan(newEmailDomain.trim(), newEmailReason.trim() || undefined);
      emailBans = [ban, ...emailBans];
      newEmailDomain = '';
      newEmailReason = '';
      addToast('Email domain blocked', 'success');
    } catch (err) {
      addToast(
        err instanceof ApiError && err.status === 422
          ? $t('admin.moderation.email_domains.invalid')
          : 'Failed to block email domain',
        'error'
      );
    }
  }

  async function handleRemoveEmailBan(id: string) {
    try {
      await deleteEmailDomainBan(id);
      emailBans = emailBans.filter((b) => b.id !== id);
      addToast('Email domain unblocked', 'success');
    } catch {
      addToast('Failed to unblock email domain', 'error');
    }
  }

  async function handleAddMediaHashBan() {
    if (!newHash.trim()) return;
    try {
      const ban = await createMediaHashBan({
        hash: newHash.trim(),
        // The only kind uploads are checked against.
        hash_type: 'sha256',
        description: newHashDescription.trim() || undefined,
      });
      mediaHashBans = [...mediaHashBans, ban];
      newHash = '';
      newHashDescription = '';
      addToast('Media hash banned', 'success');
    } catch (err) {
      addToast(
        err instanceof ApiError && err.status === 422
          ? $t('admin.moderation.media_hashes.invalid')
          : 'Failed to ban media hash',
        'error'
      );
    }
  }

  async function handleRemoveMediaHashBan(id: string) {
    try {
      await deleteMediaHashBan(id);
      mediaHashBans = mediaHashBans.filter((b) => b.id !== id);
      addToast('Media hash ban removed', 'success');
    } catch {
      addToast('Failed to remove media hash ban', 'error');
    }
  }

  function truncateHash(hash: string): string {
    if (hash.length <= 16) return hash;
    return hash.slice(0, 8) + '…' + hash.slice(-8);
  }

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

  async function handleAddFilter() {
    if (!newFilterPattern.trim()) return;
    try {
      const filter = await createContentFilter({
        type: newFilterType,
        pattern: newFilterPattern.trim(),
        action: newFilterAction
      });
      filters = [filter, ...filters];
      newFilterPattern = '';
      addToast('Content filter created', 'success');
    } catch (err) {
      addToast(
        err instanceof ApiError && err.status === 422
          ? $t('admin.moderation.filters.invalid')
          : 'Failed to create content filter',
        'error'
      );
    }
  }

  async function handleDeleteFilter(id: string) {
    try {
      await deleteContentFilter(id);
      filters = filters.filter((f) => f.id !== id);
      addToast('Content filter removed', 'success');
    } catch {
      addToast('Failed to remove content filter', 'error');
    }
  }

  async function handleAddIpBlock() {
    if (!newIp.trim()) return;
    try {
      const block = await createIpBlock({
        ip_address: newIp.trim(),
        subnet_mask: newIpSubnetMask.trim() || null,
        reason: newIpReason.trim() || null,
        expires_at: null
      });
      ipBlocks = [...ipBlocks, block];
      newIp = '';
      newIpSubnetMask = '';
      newIpReason = '';
      addToast('IP block created', 'success');
    } catch (e: any) {
      const msg = e?.body?.message || e?.body?.error_description || 'Failed to create IP block';
      addToast(msg, 'error');
    }
  }

  async function handleDeleteIpBlock(id: string) {
    try {
      await deleteIpBlock(id);
      ipBlocks = ipBlocks.filter((b) => b.id !== id);
      addToast('IP block removed', 'success');
    } catch {
      addToast('Failed to remove IP block', 'error');
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

    {:else if activeTab === 'filters'}
      <form class="add-form" onsubmit={(e) => { e.preventDefault(); handleAddFilter(); }}>
        <select class="input" bind:value={newFilterType} aria-label={$t('admin.moderation.filters.type_label')} style="width: 120px">
          <option value="word">{$t('admin.moderation.filters.type_word')}</option>
          <option value="phrase">{$t('admin.moderation.filters.type_phrase')}</option>
          <option value="regex">{$t('admin.moderation.filters.type_regex')}</option>
        </select>
        <input
          class="input"
          type="text"
          bind:value={newFilterPattern}
          placeholder={$t('admin.moderation.filters.pattern_placeholder')}
          aria-label={$t('admin.moderation.filters.pattern_placeholder')}
          required
        />
        <select class="input" bind:value={newFilterAction} aria-label={$t('admin.moderation.filters.action_label')} style="width: 170px">
          <option value="flag">{$t('admin.moderation.filters.action_flag')}</option>
          <option value="reject">{$t('admin.moderation.filters.action_reject')}</option>
        </select>
        <button class="btn btn-primary" type="submit">Add</button>
      </form>

      <p class="text-secondary">{$t('admin.moderation.filters.help')}</p>

      <div class="list-items">
        {#each filters as filter (filter.id)}
          <div class="list-item card">
            <div class="list-item-info">
              <span class="badge-type">{filter.type}</span>
              <code class="filter-pattern">{filter.pattern}</code>
              <span class="badge-action badge-{filter.action}">{filter.action}</span>
              {#if filter.scope !== 'all'}
                <span class="badge-scope">{filter.scope}</span>
              {/if}
              {#if filter.replacement}
                <span class="text-secondary">- {filter.replacement}</span>
              {/if}
            </div>
            <button
              class="btn btn-sm btn-danger"
              type="button"
              onclick={() => handleDeleteFilter(filter.id)}
            >Remove</button>
          </div>
        {:else}
          <p class="empty-text">No content filters configured</p>
        {/each}
      </div>

    {:else if activeTab === 'ipblocks'}
      <form class="add-form" onsubmit={(e) => { e.preventDefault(); handleAddIpBlock(); }}>
        <input class="input" type="text" bind:value={newIp} placeholder="IP address (IPv4 or IPv6)" required />
        <input class="input" type="text" bind:value={newIpSubnetMask} placeholder="CIDR (optional, e.g. 24)" style="width: 180px" />
        <input class="input" type="text" bind:value={newIpReason} placeholder="Reason (optional)" />
        <button class="btn btn-primary" type="submit">Block IP</button>
      </form>

      <div class="list-items">
        {#each ipBlocks as block (block.id)}
          <div class="list-item card">
            <div class="list-item-info">
              <code>{block.ip_address}{#if block.subnet_mask}/{block.subnet_mask}{/if}</code>
              {#if block.reason}
                <span class="text-secondary">- {block.reason}</span>
              {/if}
            </div>
            <button
              class="btn btn-sm btn-danger"
              type="button"
              onclick={() => handleDeleteIpBlock(block.id)}
            >Remove</button>
          </div>
        {:else}
          <p class="empty-text">No IP blocks</p>
        {/each}
      </div>

    {:else if activeTab === 'email-domains'}
      <p class="text-secondary">{$t('admin.moderation.email_domains.help')}</p>

      <form class="add-form" onsubmit={(e) => { e.preventDefault(); handleAddEmailBan(); }}>
        <input class="input" type="text" bind:value={newEmailDomain} placeholder="domain.example" required />
        <input class="input" type="text" bind:value={newEmailReason} placeholder="Reason (optional)" />
        <button class="btn btn-primary" type="submit">Block domain</button>
      </form>

      {#if emailBansLoading}
        <div class="skeleton" style="height: 50px"></div>
      {:else}
        <div class="list-items">
          {#each emailBans as ban (ban.id)}
            <div class="list-item card">
              <div class="list-item-info">
                <strong>{ban.domain}</strong>
                {#if ban.reason}
                  <span class="text-secondary">— {ban.reason}</span>
                {/if}
                <span class="text-tertiary" style="font-size: var(--text-xs)">Added {formatDate(ban.created_at)}</span>
              </div>
              <button class="btn btn-sm btn-danger" type="button" onclick={() => handleRemoveEmailBan(ban.id)}>
                Remove
              </button>
            </div>
          {:else}
            <p class="empty-text">No blocked email domains</p>
          {/each}
        </div>
      {/if}

    {:else if activeTab === 'media-hashes'}
      <form class="add-form" onsubmit={(e) => { e.preventDefault(); handleAddMediaHashBan(); }}>
        <input
          class="input"
          type="text"
          bind:value={newHash}
          placeholder={$t('admin.moderation.media_hashes.placeholder')}
          aria-label={$t('admin.moderation.media_hashes.placeholder')}
          required
        />
        <input class="input" type="text" bind:value={newHashDescription} placeholder="Description (optional)" />
        <button class="btn btn-primary" type="submit">Ban hash</button>
      </form>

      {#if mediaHashBansLoading}
        <div class="skeleton" style="height: 50px"></div>
      {:else}
        <div class="list-items">
          {#each mediaHashBans as ban (ban.id)}
            <div class="list-item card">
              <div class="list-item-info">
                <code class="hash-value" title={ban.hash}>{truncateHash(ban.hash)}</code>
                <span class="badge-type">{ban.hash_type}</span>
                {#if ban.description}
                  <span class="text-secondary">— {ban.description}</span>
                {/if}
                <span class="text-tertiary" style="font-size: var(--text-xs)">Added {formatDate(ban.created_at)}</span>
              </div>
              <button class="btn btn-sm btn-danger" type="button" onclick={() => handleRemoveMediaHashBan(ban.id)}>
                Remove
              </button>
            </div>
          {:else}
            <p class="empty-text">No media hash bans</p>
          {/each}
        </div>
      {/if}
    {:else if activeTab === 'hashtags'}
      <form class="add-form" onsubmit={(e) => { e.preventDefault(); handleAddHashtagBlocks(); }}>
        <input
          class="input"
          type="text"
          bind:value={newHashtags}
          placeholder={$t('admin.moderation.hashtags.tags_placeholder')}
          aria-label={$t('admin.moderation.hashtags.tags_placeholder')}
          required
        />
        <select
          class="input"
          bind:value={newHashtagAction}
          aria-label={$t('admin.moderation.hashtags.action_label')}
          style="width: 200px"
        >
          <option value="no_trending">{$t('admin.moderation.hashtags.action_no_trending')}</option>
          <option value="hide">{$t('admin.moderation.hashtags.action_hide')}</option>
          <option value="reject">{$t('admin.moderation.hashtags.action_reject')}</option>
        </select>
        <input
          class="input"
          type="text"
          bind:value={newHashtagReason}
          placeholder={$t('admin.moderation.hashtags.reason_placeholder')}
          aria-label={$t('admin.moderation.hashtags.reason_placeholder')}
        />
        <button class="btn btn-primary" type="submit">{$t('admin.moderation.hashtags.submit')}</button>
      </form>

      <p class="text-secondary">{$t('admin.moderation.hashtags.help_no_trending')}</p>
      <p class="text-secondary">{$t('admin.moderation.hashtags.help_hide')}</p>
      <p class="text-secondary">{$t('admin.moderation.hashtags.help_reject')}</p>

      {#if hashtagBlocksLoading}
        <div class="skeleton" style="height: 50px"></div>
      {:else}
        <div class="list-items">
          {#each hashtagBlocks as block (block.id)}
            <div class="list-item card">
              <div class="list-item-info">
                <strong>#{block.name}</strong>
                <span class="badge-type">{$t(`admin.moderation.hashtags.action_${block.action}`)}</span>
                {#if block.reason}
                  <span class="text-secondary">{block.reason}</span>
                {/if}
                <span class="text-tertiary" style="font-size: var(--text-xs)">{formatDate(block.created_at)}</span>
              </div>
              <button class="btn btn-sm btn-danger" type="button" onclick={() => handleRemoveHashtagBlock(block.id)}>
                {$t('admin.moderation.hashtags.remove')}
              </button>
            </div>
          {:else}
            <p class="empty-text">{$t('admin.moderation.hashtags.empty')}</p>
          {/each}
        </div>
      {/if}
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

  .add-form {
    display: flex;
    gap: var(--space-2);
    margin-block-end: var(--space-4);
    flex-wrap: wrap;
    align-items: flex-end;
  }

  .add-form .input {
    flex: 1;
    min-width: 150px;
  }

  .list-items {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .list-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
  }

  .list-item-info {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-wrap: wrap;
    font-size: var(--text-sm);
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

  .filter-pattern {
    font-size: var(--text-sm);
    background: var(--color-surface);
    padding: 2px var(--space-2);
    border-radius: var(--radius-sm);
  }

  .badge-action {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    text-transform: capitalize;
  }

  .badge-flag {
    background: var(--color-warning-soft);
    color: var(--color-on-warning-soft);
  }


  .badge-reject {
    background: var(--color-danger-soft);
    color: var(--color-on-danger-soft);
  }

  .badge-scope {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    background: var(--color-surface);
    color: var(--color-text-secondary);
    text-transform: capitalize;
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

  .hash-value {
    font-size: var(--text-sm);
    background: var(--color-surface);
    padding: 2px var(--space-2);
    border-radius: var(--radius-sm);
    cursor: help;
    font-family: var(--font-mono, monospace);
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
