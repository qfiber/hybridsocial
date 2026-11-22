<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getSessions, revokeSession, revokeOtherSessions } from '$lib/api/sessions.js';
  import type { Session } from '$lib/api/sessions.js';
  import { t } from '$lib/stores/i18n.js';
  import { t as translate } from '$lib/utils/i18n.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';
  import SettingsSection from '$lib/components/settings/SettingsSection.svelte';

  let sessions: Session[] = $state([]);
  let loading = $state(true);

  // Revoking a session signs a device out, so confirm before doing it.
  let confirmTarget = $state<{ kind: 'one'; session: Session } | { kind: 'all' } | null>(null);
  let showConfirm = $state(false);
  let working = $state(false);

  onMount(async () => {
    try {
      sessions = await getSessions();
    } catch {
      addToast(translate('settings.security_sessions_load_failed'), 'error');
    } finally {
      loading = false;
    }
  });

  function askRevoke(session: Session) {
    confirmTarget = { kind: 'one', session };
    showConfirm = true;
  }

  function askRevokeOthers() {
    confirmTarget = { kind: 'all' };
    showConfirm = true;
  }

  let otherCount = $derived(sessions.filter((s) => !s.current).length);

  async function executeConfirm() {
    if (!confirmTarget || working) return;
    working = true;
    try {
      if (confirmTarget.kind === 'one') {
        const id = confirmTarget.session.id;
        await revokeSession(id);
        sessions = sessions.filter((s) => s.id !== id);
        addToast(translate('settings.security_sessions_revoked'), 'success');
      } else {
        const result = await revokeOtherSessions();
        sessions = sessions.filter((s) => s.current);
        addToast(translate('settings.security_sessions_revoked_others', { count: result.count }), 'success');
      }
      showConfirm = false;
      confirmTarget = null;
    } catch {
      addToast(translate('settings.security_sessions_revoke_failed'), 'error');
    } finally {
      working = false;
    }
  }

  function timeAgo(iso: string | null): string {
    if (!iso) return $t('settings.security_time_never');
    const diff = Date.now() - new Date(iso).getTime();
    const minutes = Math.floor(diff / 60000);
    if (minutes < 1) return $t('settings.security_time_now');
    if (minutes < 60) return $t('settings.security_time_minutes', { n: minutes });
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return $t('settings.security_time_hours', { n: hours });
    const days = Math.floor(hours / 24);
    return $t('settings.security_time_days', { n: days });
  }
</script>

<SettingsSection title={$t('settings.security_sessions_title')} description={$t('settings.security_sessions_desc')}>
  {#if loading}
    <div class="sessions-note"><Spinner size={20} /> {$t('settings.security_sessions_loading')}</div>
  {:else if sessions.length === 0}
    <div class="sessions-note">{$t('settings.security_sessions_empty')}</div>
  {:else}
    {#each sessions as session (session.id)}
      <div class="session" class:current={session.current}>
        <div class="session-icon" aria-hidden="true">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            {#if session.device_name?.includes('Android') || session.device_name?.includes('iOS')}
              <rect x="5" y="2" width="14" height="20" rx="2" ry="2"/><line x1="12" y1="18" x2="12.01" y2="18"/>
            {:else}
              <rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/>
            {/if}
          </svg>
        </div>
        <div class="session-info">
          <div class="session-name">
            {session.device_name}
            {#if session.current}
              <span class="session-badge">{$t('settings.security_sessions_this_device')}</span>
            {/if}
          </div>
          <div class="session-meta">
            {#if session.location}
              <span>{session.location}</span>
              <span>&middot;</span>
            {/if}
            {#if session.ip_address}
              <span dir="ltr">{session.ip_address}</span>
              <span>&middot;</span>
            {/if}
            <span>{$t('settings.security_sessions_active', { time: timeAgo(session.last_active_at) })}</span>
          </div>
        </div>
        {#if !session.current}
          <button type="button" class="btn btn-ghost btn-sm session-revoke" onclick={() => askRevoke(session)}>
            {$t('settings.security_sessions_revoke')}
          </button>
        {/if}
      </div>
    {/each}

    {#if otherCount > 0}
      <div class="sessions-actions">
        <button type="button" class="btn btn-danger btn-sm" onclick={askRevokeOthers}>
          {$t('settings.security_sessions_revoke_others')}
        </button>
      </div>
    {/if}
  {/if}
</SettingsSection>

<Modal
  bind:open={showConfirm}
  title={confirmTarget?.kind === 'all' ? $t('settings.security_sessions_confirm_all_title') : $t('settings.security_sessions_confirm_one_title')}
  onclose={() => { confirmTarget = null; }}
>
  {#if confirmTarget}
    <p class="confirm-message">
      {#if confirmTarget.kind === 'all'}
        {$t('settings.security_sessions_confirm_all', { count: otherCount })}
      {:else}
        {$t('settings.security_sessions_confirm_one', { name: confirmTarget.session.device_name })}
      {/if}
    </p>
    <div class="confirm-actions">
      <button type="button" class="btn btn-ghost btn-sm" onclick={() => (showConfirm = false)}>{$t('common.cancel')}</button>
      <button type="button" class="btn btn-danger btn-sm" onclick={executeConfirm} disabled={working}>
        {#if working}<Spinner size={14} color="#fff" />{/if}
        {$t('settings.security_sessions_revoke')}
      </button>
    </div>
  {/if}
</Modal>

<style>
  .sessions-note {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-4) var(--space-5);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .session {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-5);
  }

  .session-icon {
    display: flex;
    color: var(--color-text-secondary);
    flex-shrink: 0;
  }

  .session.current .session-icon {
    color: var(--color-primary);
  }

  .session-info {
    flex: 1;
    min-width: 0;
  }

  .session-name {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .session-badge {
    font-size: var(--text-xs);
    font-weight: 700;
    color: var(--color-primary);
    background: var(--color-surface-container-high);
    padding: 1px var(--space-2);
    border-radius: var(--radius-full);
  }

  .session-meta {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-1);
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .session-revoke {
    flex-shrink: 0;
    color: var(--color-danger);
  }

  .sessions-actions {
    display: flex;
    justify-content: flex-end;
    padding: var(--space-3) var(--space-5) var(--space-4);
  }

  .confirm-message {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: 1.5;
    margin-block-end: var(--space-4);
  }

  .confirm-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
  }
</style>
