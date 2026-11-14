<script lang="ts">
  // Instance blocklists: content filters, IP blocks, email domains, media
  // hashes and hashtags. Split out of Moderation, which is now the daily
  // queue (reports, verifications, auto-flags) only.
  import { page } from '$app/state';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import AdminPage from '$lib/components/admin/AdminPage.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { t } from '$lib/stores/i18n.js';
  import { ApiError } from '$lib/api/client.js';
  import {
    getContentFilters, createContentFilter, deleteContentFilter,
    getIpBlocks, createIpBlock, deleteIpBlock,
    getEmailDomainBans, createEmailDomainBan, deleteEmailDomainBan,
    getMediaHashBans, createMediaHashBan, deleteMediaHashBan,
    getHashtagBlocks, createHashtagBlock, deleteHashtagBlock,
  } from '$lib/api/admin.js';
  import type {
    ContentFilter, IpBlock, EmailDomainBan, MediaHashBan, HashtagBlock,
  } from '$lib/api/types.js';

  const tabs = [
    { id: 'filters', label: 'Content Filters' },
    { id: 'ipblocks', label: 'IP Blocks' },
    { id: 'email-domains', label: 'Email Domains' },
    { id: 'media-hashes', label: 'Media Hashes' },
    { id: 'hashtags', label: $t('admin.moderation.hashtags.tab') },
  ];

  const validTabs = tabs.map((tab) => tab.id);

  // Deep links (?tab=hashtags) open a specific list; old Moderation tab
  // links are redirected here with the same parameter.
  const requested = page.url.searchParams.get('tab');
  let activeTab = $state(requested && validTabs.includes(requested) ? requested : 'filters');


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


  $effect(() => {
    if (activeTab === 'filters' && !filtersLoaded && !filtersLoading) {
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


  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  }
</script>

<AdminPage title={$t('admin_blocklists.title')} description={$t('admin_blocklists.description')}>
  <Tabs {tabs} bind:active={activeTab}>
    {#if activeTab === 'filters'}
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
</AdminPage>


<style>

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

  .status-dismissed {
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

  /* Widen the handle cells + keep the whole handle on one line so a
     long acct like @user@example.social can't collide with the next
     column's content. */
  :global(.data-table td:nth-child(2)),
  :global(.data-table td:nth-child(3)) {
    min-width: 140px;
    padding-inline-end: var(--space-6) !important;
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

  .status-approved {
    background: var(--color-success-soft);
    color: var(--color-on-success-soft);
  }

  .status-rejected {
    background: var(--color-danger-soft);
    color: var(--color-on-danger-soft);
  }

</style>
