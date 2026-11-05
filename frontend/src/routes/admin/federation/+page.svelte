<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import DataTable from '$lib/components/admin/DataTable.svelte';
  import Pagination from '$lib/components/admin/Pagination.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import {
    getKnownInstances,
    getFederationPolicies, createFederationPolicy, deleteFederationPolicy,
    purgeInstancePreview, purgeInstanceContent,
    getAdminSettings, updateAdminSettings
  } from '$lib/api/admin.js';
  import { api, ApiError } from '$lib/api/client.js';
  import { t } from '$lib/stores/i18n.js';
  import { t as translate } from '$lib/utils/i18n.js';
  import Sparkline from '$lib/components/admin/Sparkline.svelte';
  import RelaysPanel from '$lib/components/admin/RelaysPanel.svelte';
  import type { KnownInstance, FederationPolicy, DeliveryQueueStats, InstancePurgePreview } from '$lib/api/types.js';

  const tabs = [
    { id: 'instances', label: 'Known Instances' },
    { id: 'policies', label: 'Policies' },
    { id: 'delivery', label: 'Delivery Queue' },
    { id: 'relays', label: 'Relays' }
  ];

  let activeTab = $state('instances');

  // Known Instances
  let instances: KnownInstance[] = $state([]);
  let instancesLoading = $state(true);
  let instanceSortKey = $state('last_activity_at');
  let instanceSortDir = $state<'asc' | 'desc'>('desc');

  // Client-side pagination: both federation endpoints return their full
  // set (no server-side limit), and we slice locally so sorting stays
  // instant without a round-trip per click. ~1.9k known instances is a
  // lot of DOM to paint at once.
  const INSTANCES_PAGE_SIZE = 50;
  let instancePage = $state(1);

  // DataTable reports sort state but does NOT reorder rows — it renders
  // `rows` exactly as passed. Sorting therefore has to happen here;
  // without it the header arrow moved but the table never re-sorted.
  let sortedInstances = $derived.by(() => {
    const key = instanceSortKey;
    const dir = instanceSortDir === 'asc' ? 1 : -1;
    return [...instances].sort((a, b) => {
      const av = (a as unknown as Record<string, unknown>)[key];
      const bv = (b as unknown as Record<string, unknown>)[key];
      // Nulls (an instance we've never seen activity from, unknown
      // software) sort last regardless of direction, so they never
      // crowd out the rows an admin is actually looking for.
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
      if (key.endsWith('_at')) {
        return (new Date(av as string).getTime() - new Date(bv as string).getTime()) * dir;
      }
      return String(av).localeCompare(String(bv)) * dir;
    });
  });

  // A re-sort or a reload can leave you on a page that no longer exists;
  // snap back to the first page rather than showing an empty table.
  $effect(() => {
    void instanceSortKey;
    void instanceSortDir;
    void instances.length;
    instancePage = 1;
  });

  let instanceRows = $derived(
    sortedInstances
      .slice((instancePage - 1) * INSTANCES_PAGE_SIZE, instancePage * INSTANCES_PAGE_SIZE)
      .map((i) => ({ ...i } as Record<string, unknown>))
  );

  const instanceColumns = [
    { key: 'domain', label: 'Domain', sortable: true },
    { key: 'software', label: 'Software' },
    { key: 'user_count', label: 'Users', sortable: true },
    { key: 'last_activity_at', label: 'Last Activity', sortable: true },
    { key: 'status', label: 'Status' }
  ];

  // Policies
  let policies: FederationPolicy[] = $state([]);
  let policiesLoading = $state(false);

  const POLICIES_PAGE_SIZE = 25;
  let policyPage = $state(1);
  let pagedPolicies = $derived(
    policies.slice((policyPage - 1) * POLICIES_PAGE_SIZE, policyPage * POLICIES_PAGE_SIZE)
  );

  // Removing a policy can shrink the list past the current page
  // (deleting the only entry on the last page, say). Clamp instead of
  // resetting to 1 so an admin pruning entries keeps their place.
  // `policyPage` is read untracked — a plain read here would make the
  // effect depend on what it writes and re-run itself.
  $effect(() => {
    const maxPage = Math.max(1, Math.ceil(policies.length / POLICIES_PAGE_SIZE));
    if (untrack(() => policyPage) > maxPage) policyPage = maxPage;
  });
  let newPolicyDomain = $state('');
  let newPolicyType = $state<'allow' | 'silence' | 'suspend' | 'force_nsfw' | 'block_media'>('silence');
  let newPolicyReason = $state('');

  // Delivery Queue
  // The Delivery Queue tab now reads from /admin/federation/delivery
  // which bundles three queries: queue snapshot, last-hour throughput
  // by activity type, and the top failing destination domains. Old
  // BEAM-stats blob (/admin/queue_stats) was misnamed — it was VM
  // metrics, not delivery metrics — so we drop it from this tab.
  type FederationDelivery = {
    queue: {
      pending: number;
      retrying: number;
      failed_24h: number;
      delivered_24h: number;
      oldest_pending_age_seconds: number;
    };
    throughput: {
      buckets: { t: string; total: number; by_type: Record<string, number> }[];
      totals_by_type: Record<string, number>;
    };
    top_failing: {
      domain: string;
      failures: number;
      last_error: string | null;
      last_attempt_at: string | null;
      max_attempts: number;
    }[];
    latency: {
      domain: string;
      samples: number;
      p50_ms: number | null;
      p95_ms: number | null;
      max_ms: number | null;
    }[];
  };
  let deliveryStats: FederationDelivery | null = $state(null);
  let deliveryLoading = $state(false);

  // Dead-letter queue: rows with status=failed. The Delivery Queue tab
  // grows a section below the throughput/failures cards listing them
  // with per-row Retry / Drop buttons and a per-domain Retry-all
  // bulk action.
  type DeadLetter = {
    id: string;
    activity_id: string;
    activity_type: string | null;
    actor_id: string | null;
    target_inbox: string;
    domain: string | null;
    attempts: number;
    last_attempt_at: string | null;
    inserted_at: string;
    error: string | null;
    body_available: boolean;
  };
  let deadLetters: DeadLetter[] = $state([]);
  let deadLettersTotal = $state(0);
  let deadLettersLoading = $state(false);
  let deadLettersBusy = $state<string | null>(null);
  // Whole-queue failure counts per domain. The list itself is one page
  // of 50, so without these the group headers (and the bulk-drop
  // confirm) would only describe the page, not the backlog behind it.
  let deadLetterDomainCounts = $state<Record<string, number>>({});
  // Domains an admin has switched outbound delivery off for.
  let deliveryDisabled = $state<Set<string>>(new Set());

  async function loadDeadLetters() {
    deadLettersLoading = true;
    try {
      const res = await api.get<{
        data: DeadLetter[];
        total: number;
        by_domain?: { domain: string; count: number }[];
        disabled_domains?: string[];
      }>('/api/v1/admin/federation/dead_letters', { limit: '50' });
      deadLetters = res.data || [];
      deadLettersTotal = res.total || 0;
      deadLetterDomainCounts = Object.fromEntries(
        (res.by_domain || []).map((d) => [d.domain, d.count]),
      );
      deliveryDisabled = new Set(res.disabled_domains || []);
    } catch {
      addToast('Failed to load dead-letter queue', 'error');
    } finally {
      deadLettersLoading = false;
    }
  }

  // Total failures for a domain across the whole queue, falling back to
  // the loaded page if the breakdown hasn't arrived yet.
  function domainFailureCount(domain: string, loaded: number) {
    return deadLetterDomainCounts[domain] ?? loaded;
  }

  async function retryDeadLetter(item: DeadLetter) {
    if (deadLettersBusy) return;
    deadLettersBusy = item.id;
    try {
      const res = await api.post<{ status: string }>(
        `/api/v1/admin/federation/dead_letters/${item.id}/retry`,
      );
      if (res.status === 'delivered') {
        addToast('Delivered', 'success');
        deadLetters = deadLetters.filter((d) => d.id !== item.id);
        deadLettersTotal = Math.max(0, deadLettersTotal - 1);
      } else {
        addToast('Retry failed — error updated on the row', 'warning');
        await loadDeadLetters();
      }
      await loadDelivery();
    } catch (e) {
      const apiErr = e as { body?: { error?: string } };
      const code = apiErr?.body?.error;
      if (code === 'dead_letter.body_not_available') {
        addToast('Cannot retry — activity body was not stored on this row', 'error');
      } else if (code === 'dead_letter.actor_not_found') {
        addToast('Cannot retry — original actor no longer exists', 'error');
      } else {
        addToast('Retry failed', 'error');
      }
    } finally {
      deadLettersBusy = null;
    }
  }

  async function dropDeadLetter(item: DeadLetter) {
    if (deadLettersBusy) return;
    if (!confirm(`Permanently drop this delivery to ${item.domain ?? item.target_inbox}? This can't be undone.`)) return;
    deadLettersBusy = item.id;
    try {
      await api.delete(`/api/v1/admin/federation/dead_letters/${item.id}`);
      deadLetters = deadLetters.filter((d) => d.id !== item.id);
      deadLettersTotal = Math.max(0, deadLettersTotal - 1);
      addToast('Dropped', 'success');
      await loadDelivery();
    } catch {
      addToast('Failed to drop', 'error');
    } finally {
      deadLettersBusy = null;
    }
  }

  async function retryAllForDomain(domain: string) {
    if (deadLettersBusy) return;
    if (!confirm(`Retry every failed delivery for ${domain}?`)) return;
    deadLettersBusy = `domain:${domain}`;
    try {
      const res = await api.post<{ delivered: number; failed: number }>(
        '/api/v1/admin/federation/dead_letters/retry_domain',
        { domain },
      );
      addToast(
        `${domain}: ${res.delivered} delivered · ${res.failed} still failing`,
        res.failed === 0 ? 'success' : 'warning',
      );
      await loadDeadLetters();
      await loadDelivery();
    } catch {
      addToast('Bulk retry failed', 'error');
    } finally {
      deadLettersBusy = null;
    }
  }

  // Peers with outbound delivery switched off. Kept separate from the
  // dead-letter groups: once a peer is switched off and its queue
  // cleared it has no rows left, and it would otherwise disappear with
  // no way to undo.
  type DisabledPeer = {
    domain: string;
    disabled_at: string;
    reason: string | null;
    software: string | null;
  };
  let disabledPeers: DisabledPeer[] = $state([]);

  async function loadDisabledPeers() {
    try {
      const res = await api.get<{ data: DisabledPeer[] }>(
        '/api/v1/admin/federation/delivery_disabled',
      );
      disabledPeers = res.data || [];
    } catch {
      // Non-fatal: the rest of the tab is still useful.
      disabledPeers = [];
    }
  }

  // Retention window for federation_deliveries rows. Every fan-out
  // writes one row per recipient and nothing used to remove them, so
  // the dead-letter queue grew without bound.
  let retentionDays = $state<number | null>(null);
  let retentionSaving = $state(false);

  async function loadRetention() {
    try {
      const settings = await getAdminSettings();
      const s = settings.find((x) => x.key === 'federation_delivery_retention_days');
      retentionDays = s ? Number(s.value) : 30;
    } catch {
      retentionDays = 30;
    }
  }

  async function saveRetention() {
    if (retentionDays === null || retentionDays < 0) return;
    retentionSaving = true;
    try {
      await updateAdminSettings([
        { key: 'federation_delivery_retention_days', value: Math.floor(retentionDays) },
      ]);
      addToast(
        retentionDays === 0
          ? 'Delivery rows will be kept forever'
          : `Delivery rows older than ${retentionDays} days will be pruned hourly`,
        'success',
      );
    } catch {
      addToast('Failed to save retention', 'error');
    } finally {
      retentionSaving = false;
    }
  }

  async function dropAllForDomain(domain: string, total: number) {
    if (deadLettersBusy) return;
    if (
      !confirm(
        `Permanently drop all ${total.toLocaleString()} failed deliveries to ${domain}? This can't be undone.`,
      )
    )
      return;
    deadLettersBusy = `domain:${domain}`;
    try {
      const res = await api.post<{ dropped: number }>(
        '/api/v1/admin/federation/dead_letters/drop_domain',
        { domain },
      );
      addToast(`Dropped ${res.dropped.toLocaleString()} from ${domain}`, 'success');
      await loadDeadLetters();
      await loadDelivery();
    } catch {
      addToast('Bulk drop failed', 'error');
    } finally {
      deadLettersBusy = null;
    }
  }

  // Outbound kill switch for peers that are gone for good. Separate
  // from a suspend policy: that's a moderation decision about their
  // content, this is "stop wasting delivery attempts on a dead host".
  async function stopDelivering(domain: string, queued: number) {
    if (deadLettersBusy) return;
    const reason = prompt(
      `Stop delivering to ${domain}?\n\nNothing will be sent to this instance until you resume it, ` +
        `and its ${queued.toLocaleString()} queued failures will be dropped. ` +
        `Inbound content is unaffected — use a policy for that.\n\nReason (optional):`,
    );
    if (reason === null) return;
    deadLettersBusy = `domain:${domain}`;
    try {
      const res = await api.post<{ dropped: number }>(
        '/api/v1/admin/federation/delivery_disabled',
        { domain, reason: reason || null, drop_dead_letters: true },
      );
      addToast(
        `Delivery to ${domain} stopped · ${res.dropped.toLocaleString()} dropped`,
        'success',
      );
      await loadDeadLetters();
      await loadDisabledPeers();
      await loadDelivery();
      await loadInstances();
    } catch {
      addToast('Failed to stop delivery', 'error');
    } finally {
      deadLettersBusy = null;
    }
  }

  async function resumeDelivering(domain: string) {
    if (deadLettersBusy) return;
    deadLettersBusy = `domain:${domain}`;
    try {
      await api.delete(`/api/v1/admin/federation/delivery_disabled/${encodeURIComponent(domain)}`);
      addToast(`Delivery to ${domain} resumed`, 'success');
      await loadDeadLetters();
      await loadDisabledPeers();
      await loadInstances();
    } catch {
      addToast('Failed to resume delivery', 'error');
    } finally {
      deadLettersBusy = null;
    }
  }

  // Group dead letters by domain so the per-domain bulk action button
  // surfaces naturally next to its rows.
  let deadLettersByDomain = $derived.by(() => {
    const groups: Record<string, DeadLetter[]> = {};
    for (const dl of deadLetters) {
      const key = dl.domain ?? 'unknown';
      if (!groups[key]) groups[key] = [];
      groups[key].push(dl);
    }
    return Object.entries(groups)
      .map(([domain, items]) => ({ domain, items }))
      .sort((a, b) => b.items.length - a.items.length);
  });

  // Purge
  let purgeModalOpen = $state(false);
  let purgeDomain = $state('');
  let purgePreview: InstancePurgePreview | null = $state(null);
  let purgePreviewLoading = $state(false);
  let purging = $state(false);

  onMount(async () => {
    await loadInstances();
  });

  async function loadInstances() {
    instancesLoading = true;
    try {
      const result = await getKnownInstances();
      instances = Array.isArray(result.data) ? result.data : [];
    } catch {
      addToast('Failed to load instances', 'error');
      instances = [];
    } finally {
      instancesLoading = false;
    }
  }

  async function loadPolicies() {
    policiesLoading = true;
    try {
      policies = await getFederationPolicies();
    } catch {
      addToast('Failed to load policies', 'error');
    } finally {
      policiesLoading = false;
      policiesLoaded = true;
    }
  }

  async function loadDelivery() {
    deliveryLoading = true;
    try {
      deliveryStats = await api.get<FederationDelivery>('/api/v1/admin/federation/delivery');
    } catch {
      addToast('Failed to load delivery stats', 'error');
    } finally {
      deliveryLoading = false;
      deliveryLoaded = true;
    }
  }

  function formatAge(seconds: number): string {
    if (!seconds || seconds <= 0) return '—';
    if (seconds < 60) return `${seconds}s`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
    if (seconds < 86_400) return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
    return `${Math.floor(seconds / 86_400)}d ${Math.floor((seconds % 86_400) / 3600)}h`;
  }

  function formatRelative(iso: string | null): string {
    if (!iso) return '—';
    const diff = Date.now() - new Date(iso).getTime();
    const sec = Math.max(0, Math.floor(diff / 1000));
    return formatAge(sec) + ' ago';
  }

  // Throughput series for the sparkline. The backend returns one row
  // per minute that had any deliveries, so we densify to 60 buckets
  // (one per minute) — missing minutes count as zero so the chart
  // doesn't telescope across gaps.
  let throughputSeries = $derived.by(() => {
    if (!deliveryStats?.throughput?.buckets?.length) return [] as { t: string; v: number }[];
    const buckets = deliveryStats.throughput.buckets;
    const byMinute = new Map<number, number>();
    for (const b of buckets) {
      byMinute.set(new Date(b.t).getTime(), b.total);
    }
    const now = Date.now();
    const start = Math.floor((now - 60 * 60_000) / 60_000) * 60_000;
    const out: { t: string; v: number }[] = [];
    for (let i = 0; i <= 60; i++) {
      const t = start + i * 60_000;
      out.push({ t: new Date(t).toISOString(), v: byMinute.get(t) ?? 0 });
    }
    return out;
  });

  // Activity-type chips ordered by count desc, six most common types.
  let typeBreakdown = $derived.by(() => {
    if (!deliveryStats?.throughput?.totals_by_type) return [] as { type: string; count: number }[];
    return Object.entries(deliveryStats.throughput.totals_by_type)
      .map(([type, count]) => ({ type, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 6);
  });

  let policiesLoaded = $state(false);
  let deliveryLoaded = $state(false);

  $effect(() => {
    if (activeTab === 'policies' && !policiesLoaded && !policiesLoading) {
      loadPolicies();
    } else if (activeTab === 'delivery' && !deliveryLoaded && !deliveryLoading) {
      loadDelivery();
      loadDeadLetters();
      loadDisabledPeers();
      loadRetention();
    }
  });

  async function handleAddPolicy() {
    if (!newPolicyDomain.trim()) return;
    try {
      const policy = await createFederationPolicy({
        domain: newPolicyDomain,
        policy: newPolicyType,
        reason: newPolicyReason || null
      });
      // The backend upserts by normalized domain, so this may update a listed
      // row rather than add one. Appending would duplicate the keyed {#each} entry.
      policies = [...policies.filter((p) => p.domain !== policy.domain), policy];
      // The new policy is appended, so once the list spills past one
      // page it would land on the last one and look like nothing
      // happened. Follow it there.
      policyPage = Math.max(1, Math.ceil(policies.length / POLICIES_PAGE_SIZE));
      newPolicyDomain = '';
      newPolicyReason = '';
      addToast('Federation policy created', 'success');
    } catch (err) {
      addToast(
        err instanceof ApiError && err.status === 422
          ? translate('admin.federation.policy_invalid_domain')
          : 'Failed to create policy',
        'error'
      );
    }
  }

  async function handleDeletePolicy(domain: string) {
    try {
      await deleteFederationPolicy(domain);
      policies = policies.filter((p) => p.domain !== domain);
      addToast('Policy removed', 'success');
    } catch {
      addToast('Failed to remove policy', 'error');
    }
  }


  async function openPurgeModal(domain: string) {
    purgeDomain = domain;
    purgePreview = null;
    purgeModalOpen = true;
    purgePreviewLoading = true;
    try {
      purgePreview = await purgeInstancePreview(domain);
    } catch {
      addToast('Failed to load purge preview', 'error');
    } finally {
      purgePreviewLoading = false;
    }
  }

  async function handlePurge() {
    if (!purgeDomain) return;
    purging = true;
    try {
      await purgeInstanceContent(purgeDomain);
      addToast(`Content from ${purgeDomain} purged`, 'success');
      purgeModalOpen = false;
      await loadInstances();
    } catch {
      addToast('Failed to purge instance content', 'error');
    } finally {
      purging = false;
    }
  }

  function isSuspended(domain: string): boolean {
    return policies.some((p) => p.domain === domain && p.policy === 'suspend');
  }

  function policyBadgeClass(policy: string): string {
    switch (policy) {
      case 'allow': return 'policy-allow';
      case 'silence': return 'policy-silence';
      case 'suspend': return 'policy-suspend';
      case 'force_nsfw': return 'policy-force_nsfw';
      case 'block_media': return 'policy-block_media';
      default: return '';
    }
  }

  function formatDate(iso: string | null): string {
    if (!iso) return 'Never';
    return new Date(iso).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  }
</script>

<svelte:head>
  <title>Federation - Admin</title>
</svelte:head>

<div class="federation-page">
  <h1 class="page-title">Federation</h1>

  <Tabs {tabs} bind:active={activeTab}>
    {#if activeTab === 'instances'}
      <DataTable
        columns={instanceColumns}
        rows={instanceRows}
        bind:sortKey={instanceSortKey}
        bind:sortDir={instanceSortDir}
        loading={instancesLoading}
        emptyMessage="No known instances"
      >
        {#snippet rowContent(row)}
          <td><strong>{row['domain']}</strong></td>
          <td>
            {#if row['software']}
              {row['software']}
              {#if row['software_version']}
                <span class="text-secondary"> {row['software_version']}</span>
              {/if}
            {:else}
              <span class="text-tertiary">Unknown</span>
            {/if}
          </td>
          <td>{(row['user_count'] as number).toLocaleString()}</td>
          <td>{formatDate(row['last_activity_at'] as string | null)}</td>
          <td>
            {#if row['status'] === 'none' || !row['status']}
              <span class="text-tertiary" title="No moderation policy applied">—</span>
            {:else}
              <span class="instance-status instance-{row['status']}">
                {(row['status'] as string).replace(/_/g, ' ')}
              </span>
            {/if}
            {#if row['delivery_disabled']}
              <span class="dl-off-badge" title="Outbound delivery is switched off for this instance">
                Delivery off
              </span>
            {/if}
          </td>
        {/snippet}
      </DataTable>

      {#if !instancesLoading}
        <Pagination
          bind:currentPage={instancePage}
          totalItems={instances.length}
          pageSize={INSTANCES_PAGE_SIZE}
          itemLabel="instances"
          ariaLabel="Known instances pagination"
        />
      {/if}

    {:else if activeTab === 'policies'}
      <form class="add-form" onsubmit={(e) => { e.preventDefault(); handleAddPolicy(); }}>
        <input class="input" type="text" bind:value={newPolicyDomain} placeholder="domain.example" required />
        <select class="input" bind:value={newPolicyType} style="width: 160px">
          <option value="allow">Allow</option>
          <option value="silence">Silence</option>
          <option value="suspend">Suspend</option>
          <option value="force_nsfw">Force NSFW</option>
          <option value="block_media">Block Media</option>
        </select>
        <input class="input" type="text" bind:value={newPolicyReason} placeholder="Reason (optional)" />
        <button class="btn btn-primary" type="submit">Add Policy</button>
      </form>

      <p class="text-secondary">{$t('admin.federation.policy_scope_help')}</p>

      <div class="policy-help">
        <div class="policy-help-item">
          <strong>Allow</strong>
          <span>Explicitly allow federation with this domain, overriding any global restrictions.</span>
        </div>
        <div class="policy-help-item">
          <strong>Silence</strong>
          <span>Posts from this domain won't appear in public timelines or search, but existing followers can still see them.</span>
        </div>
        <div class="policy-help-item">
          <strong>Suspend</strong>
          <span>{$t('admin.federation.policy_suspend_help')}</span>
        </div>
        <div class="policy-help-item">
          <strong>Force NSFW</strong>
          <span>All media from this domain is automatically marked as sensitive and hidden behind a content warning.</span>
        </div>
        <div class="policy-help-item">
          <strong>Block Media</strong>
          <span>Strip all images, videos, and audio from posts. Text content is still federated.</span>
        </div>
      </div>

      <div class="list-items">
        {#each pagedPolicies as policy (policy.domain)}
          <div class="list-item card">
            <div class="list-item-info">
              <strong>{policy.domain}</strong>
              <span class="policy-badge {policyBadgeClass(policy.policy)}">{policy.policy.replace(/_/g, ' ')}</span>
              {#if policy.reason}
                <span class="text-secondary">- {policy.reason}</span>
              {/if}
            </div>
            <div class="list-item-actions">
              {#if policy.policy === 'suspend'}
                <button
                  class="btn btn-sm btn-outline"
                  type="button"
                  onclick={() => openPurgeModal(policy.domain)}
                >Purge Content</button>
              {/if}
              <button
                class="btn btn-sm btn-danger"
                type="button"
                onclick={() => handleDeletePolicy(policy.domain)}
              >Remove</button>
            </div>
          </div>
        {:else}
          <p class="empty-text">No federation policies configured</p>
        {/each}
      </div>

      <Pagination
        bind:currentPage={policyPage}
        totalItems={policies.length}
        pageSize={POLICIES_PAGE_SIZE}
        itemLabel="policies"
        ariaLabel="Federation policies pagination"
      />

    {:else if activeTab === 'delivery'}
      {#if deliveryLoading}
        <div class="delivery-loading">
          <div class="skeleton" style="height: 80px"></div>
          <div class="skeleton" style="height: 120px; margin-top: 16px"></div>
        </div>
      {:else if deliveryStats}
        <!-- Queue snapshot: the four numbers an admin checks first. -->
        <section class="delivery-section">
          <h3 class="delivery-section-title">Queue</h3>
          <div class="delivery-grid">
            <div class="delivery-stat card">
              <div class="delivery-label">Pending</div>
              <div class="delivery-value">{deliveryStats.queue.pending.toLocaleString()}</div>
              <div class="delivery-sub">never attempted</div>
            </div>
            <div class="delivery-stat card">
              <div class="delivery-label">Retrying</div>
              <div class="delivery-value" class:delivery-warn={deliveryStats.queue.retrying > 0}>
                {deliveryStats.queue.retrying.toLocaleString()}
              </div>
              <div class="delivery-sub">failed at least once</div>
            </div>
            <div class="delivery-stat card">
              <div class="delivery-label">Failed (24h)</div>
              <div class="delivery-value" class:delivery-failed={deliveryStats.queue.failed_24h > 0}>
                {deliveryStats.queue.failed_24h.toLocaleString()}
              </div>
              <div class="delivery-sub">exhausted retries</div>
            </div>
            <div class="delivery-stat card">
              <div class="delivery-label">Oldest pending</div>
              <div class="delivery-value">{formatAge(deliveryStats.queue.oldest_pending_age_seconds)}</div>
              <div class="delivery-sub">backlog age</div>
            </div>
          </div>
        </section>

        <!-- Last-hour throughput + per-type breakdown. -->
        <section class="delivery-section">
          <div class="delivery-section-head">
            <h3 class="delivery-section-title">Throughput · last hour</h3>
            <span class="delivery-section-meta">
              {deliveryStats.queue.delivered_24h.toLocaleString()} delivered in last 24h
            </span>
          </div>
          <div class="delivery-throughput card">
            <div class="throughput-chart">
              <Sparkline points={throughputSeries} width={640} height={64} />
            </div>
            {#if typeBreakdown.length > 0}
              <ul class="throughput-types">
                {#each typeBreakdown as t (t.type)}
                  <li class="throughput-type">
                    <span class="throughput-type-label">{t.type}</span>
                    <span class="throughput-type-count">{t.count.toLocaleString()}</span>
                  </li>
                {/each}
              </ul>
            {:else}
              <p class="empty-text">No deliveries in the last hour.</p>
            {/if}
          </div>
        </section>

        <!-- Top failing destinations: where federation is currently broken. -->
        <section class="delivery-section">
          <h3 class="delivery-section-title">Top failing destinations · last 24h</h3>
          {#if deliveryStats.top_failing.length > 0}
            <div class="top-failing">
              {#each deliveryStats.top_failing as row (row.domain)}
                <div class="failing-row card">
                  <div class="failing-head">
                    <span class="failing-domain">{row.domain}</span>
                    <span class="failing-count">{row.failures.toLocaleString()} failures</span>
                  </div>
                  {#if row.last_error}
                    <div class="failing-error" title={row.last_error}>{row.last_error}</div>
                  {/if}
                  <div class="failing-meta">
                    <span>Max attempts: {row.max_attempts}</span>
                    <span>Last: {formatRelative(row.last_attempt_at)}</span>
                  </div>
                </div>
              {/each}
            </div>
          {:else}
            <p class="empty-text">No failing destinations in the last 24h.</p>
          {/if}
        </section>

        <!-- Per-peer delivery latency: p50/p95 ms over the last hour
             for the top destinations by sample count. Spots a slow
             peer dragging the queue without needing per-row data. -->
        <section class="delivery-section">
          <h3 class="delivery-section-title">Per-peer latency · last hour</h3>
          {#if deliveryStats.latency.length === 0}
            <p class="empty-text">Not enough delivered samples in the last hour to compute percentiles.</p>
          {:else}
            <div class="latency-grid card">
              <div class="latency-row latency-head">
                <span>Domain</span>
                <span class="latency-num">p50</span>
                <span class="latency-num">p95</span>
                <span class="latency-num">max</span>
                <span class="latency-num">samples</span>
              </div>
              {#each deliveryStats.latency as l (l.domain)}
                <div class="latency-row">
                  <span class="latency-domain">{l.domain}</span>
                  <span class="latency-num">{l.p50_ms ?? '—'} ms</span>
                  <span class="latency-num" class:latency-warn={(l.p95_ms ?? 0) > 1000} class:latency-bad={(l.p95_ms ?? 0) > 5000}>{l.p95_ms ?? '—'} ms</span>
                  <span class="latency-num">{l.max_ms ?? '—'} ms</span>
                  <span class="latency-num">{l.samples.toLocaleString()}</span>
                </div>
              {/each}
            </div>
          {/if}
        </section>

        <!-- Dead-letter queue: deliveries that exhausted their retries.
             Lists them grouped by domain so the per-domain bulk
             retry sits next to its rows; per-row retry/drop fall
             back if the body wasn't stored (pre-feature rows). -->
        <section class="delivery-section">
          <div class="delivery-section-head">
            <h3 class="delivery-section-title">Dead-letter queue</h3>
            <span class="delivery-section-meta">
              {deadLettersTotal.toLocaleString()} total
            </span>
          </div>
          {#if deadLettersLoading}
            <div class="skeleton" style="height: 96px"></div>
          {:else if deadLetters.length === 0}
            <p class="empty-text">No dead letters. Federation is clean.</p>
          {:else}
            <div class="dead-letter-groups">
              {#each deadLettersByDomain as group (group.domain)}
                <div class="dead-letter-group card">
                  <header class="dl-group-head">
                    <span class="failing-domain">{group.domain}</span>
                    <span class="dl-group-meta">
                      {domainFailureCount(group.domain, group.items.length).toLocaleString()} failed
                      {#if domainFailureCount(group.domain, group.items.length) > group.items.length}
                        <span class="dl-group-page">({group.items.length} shown)</span>
                      {/if}
                    </span>
                    {#if deliveryDisabled.has(group.domain)}
                      <span class="dl-off-badge" title="Outbound delivery is switched off">
                        Delivery off
                      </span>
                    {/if}
                    <div class="dl-group-actions">
                      {#if group.items.length > 1 && !deliveryDisabled.has(group.domain)}
                        <button
                          type="button"
                          class="btn btn-sm btn-outline"
                          onclick={() => retryAllForDomain(group.domain)}
                          disabled={deadLettersBusy === `domain:${group.domain}`}
                        >
                          {deadLettersBusy === `domain:${group.domain}` ? 'Retrying…' : 'Retry all'}
                        </button>
                      {/if}
                      <button
                        type="button"
                        class="btn btn-sm btn-danger"
                        onclick={() =>
                          dropAllForDomain(
                            group.domain,
                            domainFailureCount(group.domain, group.items.length),
                          )}
                        disabled={deadLettersBusy === `domain:${group.domain}`}
                      >
                        Drop all
                      </button>
                      {#if deliveryDisabled.has(group.domain)}
                        <button
                          type="button"
                          class="btn btn-sm btn-outline"
                          onclick={() => resumeDelivering(group.domain)}
                          disabled={deadLettersBusy === `domain:${group.domain}`}
                        >
                          Resume delivery
                        </button>
                      {:else}
                        <button
                          type="button"
                          class="btn btn-sm btn-danger"
                          onclick={() =>
                            stopDelivering(
                              group.domain,
                              domainFailureCount(group.domain, group.items.length),
                            )}
                          disabled={deadLettersBusy === `domain:${group.domain}`}
                          title="Stop all outbound delivery to this instance (for peers that no longer exist)"
                        >
                          Stop delivering
                        </button>
                      {/if}
                    </div>
                  </header>
                  <ul class="dl-list">
                    {#each group.items as item (item.id)}
                      <li class="dl-row">
                        <div class="dl-row-main">
                          <span class="dl-type">{item.activity_type ?? 'Activity'}</span>
                          <span class="dl-attempts">{item.attempts} attempt{item.attempts === 1 ? '' : 's'}</span>
                          <span class="dl-when">{formatRelative(item.last_attempt_at)}</span>
                        </div>
                        {#if item.error}
                          <div class="dl-error" title={item.error}>{item.error}</div>
                        {/if}
                        <div class="dl-row-actions">
                          <button
                            type="button"
                            class="btn btn-sm btn-primary"
                            onclick={() => retryDeadLetter(item)}
                            disabled={!item.body_available || deadLettersBusy === item.id}
                            title={item.body_available ? '' : 'Body not stored on this row'}
                          >
                            {deadLettersBusy === item.id ? 'Retrying…' : 'Retry'}
                          </button>
                          <button
                            type="button"
                            class="btn btn-sm btn-danger"
                            onclick={() => dropDeadLetter(item)}
                            disabled={deadLettersBusy === item.id}
                          >
                            Drop
                          </button>
                        </div>
                      </li>
                    {/each}
                  </ul>
                </div>
              {/each}
            </div>
          {/if}
        </section>

        <!-- Peers we've stopped delivering to. Listed separately so a
             switched-off instance with an empty queue is still visible
             and reversible. -->
        {#if disabledPeers.length > 0}
          <section class="delivery-section">
            <div class="delivery-section-head">
              <h3 class="delivery-section-title">Delivery stopped</h3>
              <span class="delivery-section-meta">{disabledPeers.length} instance{disabledPeers.length === 1 ? '' : 's'}</span>
            </div>
            <p class="delivery-section-note">
              Nothing is sent to these instances and no queue rows are created for them.
              Inbound content is unaffected — use a policy for that.
            </p>
            <div class="disabled-peers">
              {#each disabledPeers as peer (peer.domain)}
                <div class="disabled-peer card">
                  <div class="disabled-peer-info">
                    <strong>{peer.domain}</strong>
                    <span class="text-secondary">
                      stopped {formatRelative(peer.disabled_at)}{peer.reason ? ` · ${peer.reason}` : ''}
                    </span>
                  </div>
                  <button
                    type="button"
                    class="btn btn-sm btn-outline"
                    onclick={() => resumeDelivering(peer.domain)}
                    disabled={deadLettersBusy === `domain:${peer.domain}`}
                  >
                    Resume delivery
                  </button>
                </div>
              {/each}
            </div>
          </section>
        {/if}

        <!-- Retention: federation_deliveries is an append-only attempt
             log, so without a window it grows forever. -->
        <section class="delivery-section">
          <div class="delivery-section-head">
            <h3 class="delivery-section-title">Retention</h3>
          </div>
          <div class="retention-row">
            <label class="retention-label" for="delivery-retention">
              Keep delivered / failed rows for
            </label>
            <input
              id="delivery-retention"
              class="input retention-input"
              type="number"
              min="0"
              step="1"
              bind:value={retentionDays}
            />
            <span class="retention-unit">days</span>
            <button
              class="btn btn-sm btn-primary"
              type="button"
              onclick={saveRetention}
              disabled={retentionSaving || retentionDays === null}
            >
              {retentionSaving ? 'Saving…' : 'Save'}
            </button>
          </div>
          <p class="delivery-section-note">
            Older rows are pruned hourly. Pending and retrying deliveries are never touched.
            Set to 0 to keep everything.
          </p>
        </section>

        <div class="delivery-actions">
          <button class="btn btn-outline" type="button" onclick={() => { loadDelivery(); loadDeadLetters(); loadDisabledPeers(); }}>
            Refresh
          </button>
        </div>
      {/if}

    {:else if activeTab === 'relays'}
      <!-- Lifted from the standalone /admin/relays page so all
           federation surfaces (peers, policies, queue, relays) live
           in one place. The panel manages its own load state. -->
      <RelaysPanel />
    {/if}
  </Tabs>
</div>

<Modal bind:open={purgeModalOpen} title="Purge Instance Content">
  <p class="purge-warning">
    {$t('admin.federation.purge_warning', { domain: purgeDomain ?? '' })}
  </p>
  {#if purgePreviewLoading}
    <div class="skeleton" style="height: 60px"></div>
  {:else if purgePreview}
    <div class="purge-stats">
      <div class="purge-stat">
        <span class="purge-stat-label">{$t('admin.federation.purge_accounts')}</span>
        <span class="purge-stat-value">{purgePreview.identities_affected.toLocaleString()}</span>
      </div>
      <div class="purge-stat">
        <span class="purge-stat-label">{$t('admin.federation.purge_posts')}</span>
        <span class="purge-stat-value">{purgePreview.posts_removed.toLocaleString()}</span>
      </div>
      <div class="purge-stat">
        <span class="purge-stat-label">{$t('admin.federation.purge_follows')}</span>
        <span class="purge-stat-value">{purgePreview.follows_removed.toLocaleString()}</span>
      </div>
      <div class="purge-stat">
        <span class="purge-stat-label">{$t('admin.federation.purge_reactions')}</span>
        <span class="purge-stat-value">{purgePreview.reactions_removed.toLocaleString()}</span>
      </div>
      <div class="purge-stat">
        <span class="purge-stat-label">{$t('admin.federation.purge_boosts')}</span>
        <span class="purge-stat-value">{purgePreview.boosts_removed.toLocaleString()}</span>
      </div>
    </div>
  {/if}
  <div class="modal-actions">
    <button class="btn btn-ghost" type="button" onclick={() => (purgeModalOpen = false)}>Cancel</button>
    <button
      class="btn btn-danger"
      type="button"
      disabled={purging || purgePreviewLoading}
      onclick={handlePurge}
    >
      {purging ? 'Purging...' : 'Purge All Content'}
    </button>
  </div>
</Modal>

<style>
  .federation-page {
    max-width: 1100px;
  }

  .policy-help {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: var(--space-4);
    background: var(--color-surface-container-low, #f5f5f5);
    border-radius: var(--radius-lg);
    margin-block-end: var(--space-4);
  }

  .policy-help-item {
    display: flex;
    gap: 8px;
    font-size: 0.8125rem;
    line-height: 1.4;
  }

  .policy-help-item strong {
    flex-shrink: 0;
    min-width: 90px;
    color: var(--color-text);
  }

  .policy-help-item span {
    color: var(--color-text-secondary);
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-6);
  }

  .instance-status {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    text-transform: capitalize;
  }

  .instance-up {
    background: var(--color-success-soft);
    color: var(--color-on-success-soft);
  }

  .instance-down {
    background: var(--color-danger-soft);
    color: var(--color-on-danger-soft);
  }

  .instance-unknown {
    background: var(--color-surface);
    color: var(--color-text-secondary);
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

  .list-item-actions {
    display: flex;
    gap: var(--space-2);
    flex-shrink: 0;
  }

  .policy-badge {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    text-transform: capitalize;
  }

  .policy-allow {
    background: var(--color-success-soft);
    color: var(--color-on-success-soft);
  }

  .policy-silence {
    background: var(--color-warning-soft);
    color: var(--color-on-warning-soft);
  }

  .policy-suspend {
    background: var(--color-danger-soft);
    color: var(--color-on-danger-soft);
  }

  .policy-force_nsfw {
    background: var(--color-info-soft);
    color: var(--color-on-info-soft);
  }

  .policy-block_media {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }

  .delivery-section {
    margin-block-end: var(--space-5);
  }

  .delivery-section-head {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    margin-block-end: var(--space-2);
  }

  .delivery-section-title {
    font-size: var(--text-sm);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--color-text-secondary);
    margin: 0 0 var(--space-2);
  }

  .delivery-section-meta {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .delivery-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: var(--space-3);
  }

  .delivery-stat {
    padding: var(--space-4);
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .delivery-label {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .delivery-value {
    font-size: var(--text-2xl);
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    line-height: 1.1;
  }

  .delivery-sub {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .delivery-ok { color: var(--color-success); }
  .delivery-warn { color: var(--color-on-warning-soft); }
  .delivery-failed { color: var(--color-danger); }

  .delivery-throughput {
    padding: var(--space-4);
    display: flex;
    flex-direction: column;
    /* Comfortable air between the sparkline and the type chips —
       the previous space-3 had a tall spike kissing the chip row.
       Sparkline.svelte uses `overflow: visible` so a near-edge peak
       can render above its nominal box; clipping it would cut off
       data, padding the gap is the right answer. */
    gap: var(--space-5);
    margin-block-start: var(--space-2);
  }

  .throughput-chart {
    width: 100%;
    padding-block: var(--space-2);
  }

  .throughput-types {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    gap: var(--space-3);
    flex-wrap: wrap;
  }

  .throughput-type {
    display: inline-flex;
    align-items: baseline;
    gap: 6px;
    padding: 4px 10px;
    border-radius: 9999px;
    background: var(--color-surface);
    font-size: var(--text-xs);
  }

  .throughput-type-label {
    font-weight: 600;
    color: var(--color-text);
  }

  .throughput-type-count {
    color: var(--color-text-secondary);
    font-variant-numeric: tabular-nums;
  }

  .top-failing {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .failing-row {
    padding: var(--space-3) var(--space-4);
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .failing-head {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: var(--space-3);
  }

  .failing-domain {
    font-weight: 700;
    font-family: var(--font-mono);
    font-size: var(--text-sm);
  }

  .failing-count {
    font-size: var(--text-xs);
    color: var(--color-danger);
    font-weight: 600;
  }

  .failing-error {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    font-family: var(--font-mono);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .failing-meta {
    display: flex;
    gap: var(--space-3);
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .delivery-actions {
    display: flex;
    gap: var(--space-3);
    margin-block-start: var(--space-3);
  }

  .delivery-loading {
    padding: var(--space-4) 0;
  }

  /* Per-peer latency table — five columns, monospace numbers so the
     three timing columns line up regardless of magnitude. */
  .latency-grid {
    padding: var(--space-2) var(--space-4);
    display: flex;
    flex-direction: column;
  }

  .latency-row {
    display: grid;
    grid-template-columns: 1.5fr repeat(4, 1fr);
    gap: var(--space-3);
    align-items: center;
    padding: 8px 0;
    font-size: var(--text-sm);
  }

  .latency-row + .latency-row {
    border-block-start: 1px solid var(--color-border);
  }

  .latency-head {
    font-size: var(--text-xs);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-tertiary);
  }

  .latency-domain {
    font-family: var(--font-mono);
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .latency-num {
    text-align: end;
    font-variant-numeric: tabular-nums;
    color: var(--color-text-secondary);
  }

  .latency-warn { color: var(--color-on-warning-soft); font-weight: 600; }
  .latency-bad { color: var(--color-danger); font-weight: 700; }

  .dead-letter-groups {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .dead-letter-group {
    padding: var(--space-3) var(--space-4);
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .dl-group-head {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    flex-wrap: wrap;
  }

  .dl-group-meta {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    flex: 1;
  }

  .dl-group-page {
    color: var(--color-text-tertiary);
  }

  .dl-group-actions {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-wrap: wrap;
  }

  .dl-off-badge {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    background: var(--color-danger-tint);
    color: var(--color-danger);
  }

  .disabled-peers {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .disabled-peer {
    padding: var(--space-3) var(--space-4);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    flex-wrap: wrap;
  }

  .disabled-peer-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
    font-size: var(--text-sm);
    min-width: 0;
  }

  .delivery-section-note {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin: var(--space-2) 0 0;
  }

  .retention-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-wrap: wrap;
  }

  .retention-label {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .retention-input {
    width: 90px;
  }

  .retention-unit {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .dl-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    border-block-start: 1px solid var(--color-border);
    padding-block-start: var(--space-2);
  }

  .dl-row {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 4px var(--space-3);
    align-items: center;
  }

  .dl-row-main {
    display: flex;
    align-items: baseline;
    gap: var(--space-3);
    font-size: var(--text-sm);
  }

  .dl-type {
    font-weight: 600;
  }

  .dl-attempts,
  .dl-when {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .dl-error {
    grid-column: 1;
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    font-family: var(--font-mono);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .dl-row-actions {
    grid-column: 2;
    grid-row: 1 / span 2;
    display: flex;
    gap: 6px;
    flex-shrink: 0;
  }

  .purge-warning {
    font-size: var(--text-sm);
    color: var(--color-danger);
    margin-block-end: var(--space-4);
  }

  .purge-stats {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: var(--space-3);
    margin-block-end: var(--space-4);
  }

  .purge-stat {
    text-align: center;
    padding: var(--space-3);
    background: var(--color-surface);
    border-radius: var(--radius-md);
  }

  .purge-stat-label {
    display: block;
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-1);
  }

  .purge-stat-value {
    font-size: var(--text-lg);
    font-weight: 700;
  }

  .modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    margin-block-start: var(--space-4);
  }

  .empty-text {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    text-align: center;
    padding: var(--space-6) 0;
  }
</style>
