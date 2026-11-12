<script lang="ts">
  import Modal from '$lib/components/ui/Modal.svelte';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import { getGroups } from '$lib/api/groups.js';
  import type { Group } from '$lib/api/types.js';
  import type { Post } from '$lib/api/types.js';
  import { t } from '$lib/stores/i18n.js';

  let {
    open = $bindable(false),
    post,
    onclose,
  }: {
    open?: boolean;
    post: Post;
    onclose?: () => void;
  } = $props();

  // Only groups the viewer has joined — you can't post into a group you're
  // not a member of, so those are the only valid share targets.
  let groups = $state<Group[]>([]);
  let loading = $state(true);
  let loadError = $state(false);
  let query = $state('');
  let loaded = false;

  async function load() {
    loading = true;
    loadError = false;
    try {
      // The groups index returns a bare array (not a { data } envelope);
      // handle both, same as the Groups page.
      const res = await getGroups('member');
      groups = Array.isArray(res) ? res : ((res as any).data ?? []);
    } catch {
      loadError = true;
    } finally {
      loading = false;
    }
  }

  // Fetch the first time the modal opens, then keep the list around.
  $effect(() => {
    if (open && !loaded) {
      loaded = true;
      void load();
    }
  });

  let filtered = $derived(
    query.trim()
      ? groups.filter((g) => (g.name || '').toLowerCase().includes(query.trim().toLowerCase()))
      : groups,
  );

  function share(group: Group) {
    // Reuse the composer's quote + group-scope path: it embeds the original
    // as a quote and anchors the new post to the group timeline. The user
    // can add commentary or post the bare share.
    window.dispatchEvent(
      new CustomEvent('open-composer', {
        detail: {
          quotePost: post,
          groupId: group.id,
          contextLabel: $t('share_group.context', { name: group.name || $t('share_group.group_fallback') }),
        },
      }),
    );
    close();
  }

  function close() {
    open = false;
    query = '';
    onclose?.();
  }
</script>

<Modal open={open} title={$t('share_group.title')} size="sm" onclose={close}>
  {#if loading}
    <div class="stg-center"><Spinner /></div>
  {:else if loadError}
    <div class="stg-empty">
      <p class="stg-empty-title">{$t('share_group.load_error')}</p>
      <button type="button" class="btn btn-primary btn-sm" onclick={load}>{$t('common.retry')}</button>
    </div>
  {:else if groups.length === 0}
    <div class="stg-empty">
      <p class="stg-empty-title">{$t('share_group.empty_title')}</p>
      <p class="stg-empty-hint">{$t('share_group.empty_hint')}</p>
      <a class="btn btn-primary btn-sm" href="/groups" onclick={close}>{$t('share_group.find')}</a>
    </div>
  {:else}
    {#if groups.length > 6}
      <input
        type="text"
        class="input stg-search"
        placeholder={$t('share_group.search_placeholder')}
        bind:value={query}
        aria-label={$t('share_group.search_label')}
      />
    {/if}
    {#if filtered.length === 0}
      <p class="stg-noresults">{$t('share_group.no_match', { query })}</p>
    {:else}
      <ul class="stg-list">
        {#each filtered as group (group.id)}
          <li>
            <button type="button" class="stg-item" onclick={() => share(group)}>
              <Avatar src={group.avatar_url} name={group.name} size="sm" />
              <span class="stg-item-text">
                <span class="stg-item-name">{group.name}</span>
                <span class="stg-item-meta">{group.member_count} {group.member_count === 1 ? $t('share_group.member_one') : $t('share_group.member_other')}</span>
              </span>
            </button>
          </li>
        {/each}
      </ul>
    {/if}
  {/if}
</Modal>

<style>
  .stg-center {
    display: flex;
    justify-content: center;
    padding: var(--space-5, 24px);
  }

  .stg-empty {
    text-align: center;
    padding: var(--space-5, 24px) var(--space-3, 12px);
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--space-2, 8px);
  }

  .stg-empty-title {
    font-weight: 600;
    margin: 0;
  }

  .stg-empty-hint {
    margin: 0;
    color: var(--color-text-secondary);
    font-size: var(--text-sm, 0.875rem);
    max-width: 34ch;
    line-height: 1.5;
  }

  .stg-search {
    width: 100%;
    margin-bottom: var(--space-3, 12px);
  }

  .stg-noresults {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm, 0.875rem);
    text-align: center;
    padding: var(--space-3, 12px);
  }

  .stg-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-1, 4px);
    max-height: 55vh;
    max-height: 55dvh;
    overflow-y: auto;
  }

  .stg-item {
    display: flex;
    align-items: center;
    gap: var(--space-3, 12px);
    width: 100%;
    padding: var(--space-2, 8px);
    border: none;
    border-radius: var(--radius-md, 8px);
    background: transparent;
    cursor: pointer;
    text-align: start;
    color: inherit;
    transition: background-color 0.12s ease;
  }

  .stg-item:hover,
  .stg-item:focus-visible {
    background: var(--color-surface-hover, rgba(0, 0, 0, 0.06));
    outline: none;
  }

  .stg-item-text {
    display: flex;
    flex-direction: column;
    gap: 1px;
    min-width: 0;
  }

  .stg-item-name {
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .stg-item-meta {
    font-size: var(--text-xs, 0.75rem);
    color: var(--color-text-tertiary);
  }
</style>
