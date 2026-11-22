<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import { t } from '$lib/stores/i18n.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import SettingsSection from '$lib/components/settings/SettingsSection.svelte';

  // The API nests the requester under `account` (Mastodon-style); reading it
  // flat is what crashed this page once (issue #27).
  interface FollowRequest {
    id: string;
    account: { handle: string; acct?: string; display_name: string | null; avatar_url: string | null };
    created_at: string;
  }

  let requests = $state<FollowRequest[]>([]);
  let loading = $state(true);
  let processingId = $state<string | null>(null);

  onMount(async () => {
    try {
      const res = await api.get<FollowRequest[]>('/api/v1/accounts/follow_requests');
      requests = Array.isArray(res) ? res : [];
    } catch {
      addToast($t('settings.requests_load_failed'), 'error');
    } finally {
      loading = false;
    }
  });

  async function decide(request: FollowRequest, verb: 'authorize' | 'reject') {
    processingId = request.id;
    const handle = request.account.acct || request.account.handle;
    try {
      await api.post(`/api/v1/follow_requests/${request.id}/${verb}`);
      requests = requests.filter((r) => r.id !== request.id);
      addToast($t(verb === 'authorize' ? 'settings.requests_approved' : 'settings.requests_declined', { handle }), 'success');
    } catch {
      addToast($t('settings.requests_failed'), 'error');
    } finally {
      processingId = null;
    }
  }

  const formatDate = (iso: string) =>
    new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
</script>

<SettingsSection title={$t('settings.requests_title')} description={$t('settings.requests_desc')}>
  {#if loading}
    <div class="placeholder"><Spinner size={18} /></div>
  {:else if requests.length === 0}
    <p class="placeholder">{$t('settings.requests_empty')}</p>
  {:else}
    {#each requests as request (request.id)}
      {@const a = request.account}
      {@const handle = a.acct || a.handle}
      <div class="list-row">
        <a href="/@{handle}" class="who">
          <Avatar src={a.avatar_url} name={a.display_name || a.handle} size="sm" />
          <span class="who-text">
            <span class="who-name">{a.display_name || a.handle}</span>
            <span class="who-handle" dir="ltr">@{handle} · {formatDate(request.created_at)}</span>
          </span>
        </a>
        <div class="actions">
          <button type="button" class="btn btn-secondary btn-sm" onclick={() => decide(request, 'reject')} disabled={processingId === request.id}>
            {$t('settings.requests_decline')}
          </button>
          <button type="button" class="btn btn-primary btn-sm" onclick={() => decide(request, 'authorize')} disabled={processingId === request.id}>
            {#if processingId === request.id}<Spinner size={14} color="#fff" />{/if}
            {$t('settings.requests_approve')}
          </button>
        </div>
      </div>
    {/each}
  {/if}
</SettingsSection>

<style>
  .list-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-5);
  }

  .who {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    min-width: 0;
    color: var(--color-text);
    text-decoration: none;
  }

  .who:hover .who-name {
    text-decoration: underline;
  }

  .who-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .who-name {
    font-size: var(--text-sm);
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .who-handle {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    text-align: start;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .actions {
    display: flex;
    gap: var(--space-2);
    flex-shrink: 0;
  }

  .placeholder {
    display: flex;
    justify-content: center;
    padding: var(--space-5);
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
  }
</style>
