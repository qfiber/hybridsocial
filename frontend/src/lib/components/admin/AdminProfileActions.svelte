<script lang="ts">
  import type { Identity, AdminUser, ModerationNote } from '$lib/api/types.js';
  import {
    getAdminUser,
    silenceUser,
    unsilenceUser,
    shadowBanUser,
    unshadowBanUser,
    forceSensitiveUser,
    unforceSensitiveUser,
    suspendUser,
    unsuspendUser,
    revokeAllSessions,
    setTrustLevel,
    getModerationNotes,
    createModerationNote,
  } from '$lib/api/admin.js';

  let {
    account,
  }: {
    account: Identity;
  } = $props();

  let expanded = $state(false);
  let adminUser: AdminUser | null = $state(null);
  let loading = $state(false);
  let actionLoading = $state(false);
  let actionError = $state('');
  let actionSuccess = $state('');

  // Silence state
  let showSilenceDialog = $state(false);
  let silenceDuration = $state(0);
  let silenceReason = $state('');

  // Shadow ban confirmation
  let showShadowBanConfirm = $state(false);

  // Suspend state
  let showSuspendDialog = $state(false);
  let suspendReason = $state('');

  // Revoke sessions confirmation
  let showRevokeConfirm = $state(false);

  // Trust level
  let showTrustLevel = $state(false);
  let newTrustLevel = $state(0);

  // Moderation notes
  let showNotes = $state(false);
  let notes: ModerationNote[] = $state([]);
  let notesLoading = $state(false);
  let newNoteContent = $state('');
  let addingNote = $state(false);

  const durationOptions = [
    { value: 0, label: 'Indefinite' },
    { value: 3600, label: '1 hour' },
    { value: 86400, label: '24 hours' },
    { value: 604800, label: '7 days' },
    { value: 2592000, label: '30 days' },
  ];

  async function toggleExpanded() {
    expanded = !expanded;
    if (expanded && !adminUser) {
      await loadAdminUser();
    }
  }

  async function loadAdminUser() {
    loading = true;
    try {
      adminUser = await getAdminUser(account.id);
      newTrustLevel = adminUser.trust_level;
    } catch {
      actionError = 'Failed to load admin data for this user.';
    } finally {
      loading = false;
    }
  }

  function clearMessages() {
    actionError = '';
    actionSuccess = '';
  }

  function showSuccess(msg: string) {
    actionSuccess = msg;
    setTimeout(() => { actionSuccess = ''; }, 3000);
  }

  // Silence
  function openSilenceDialog() {
    clearMessages();
    silenceDuration = 0;
    silenceReason = '';
    showSilenceDialog = true;
  }

  async function confirmSilence() {
    actionLoading = true;
    clearMessages();
    try {
      if (adminUser?.silenced) {
        adminUser = await unsilenceUser(account.id);
        showSuccess('User unsilenced.');
      } else {
        adminUser = await silenceUser(account.id, {
          duration: silenceDuration || undefined,
          reason: silenceReason || undefined,
        });
        showSuccess('User silenced.');
      }
      showSilenceDialog = false;
    } catch {
      actionError = 'Failed to update silence status.';
    } finally {
      actionLoading = false;
    }
  }

  // Shadow ban
  function openShadowBanConfirm() {
    clearMessages();
    showShadowBanConfirm = true;
  }

  async function confirmShadowBan() {
    actionLoading = true;
    clearMessages();
    try {
      if (adminUser?.shadow_banned) {
        adminUser = await unshadowBanUser(account.id);
        showSuccess('Shadow ban removed.');
      } else {
        adminUser = await shadowBanUser(account.id);
        showSuccess('User shadow banned.');
      }
      showShadowBanConfirm = false;
    } catch {
      actionError = 'Failed to update shadow ban status.';
    } finally {
      actionLoading = false;
    }
  }

  // Force sensitive
  async function toggleForceSensitive() {
    actionLoading = true;
    clearMessages();
    try {
      if (adminUser?.force_sensitive) {
        adminUser = await unforceSensitiveUser(account.id);
        showSuccess('Force sensitive removed.');
      } else {
        adminUser = await forceSensitiveUser(account.id);
        showSuccess('User marked as force sensitive.');
      }
    } catch {
      actionError = 'Failed to update force sensitive status.';
    } finally {
      actionLoading = false;
    }
  }

  // Suspend
  function openSuspendDialog() {
    clearMessages();
    suspendReason = '';
    showSuspendDialog = true;
  }

  async function confirmSuspend() {
    actionLoading = true;
    clearMessages();
    try {
      if (adminUser?.status === 'suspended') {
        await unsuspendUser(account.id);
        showSuccess('User unsuspended.');
      } else {
        await suspendUser(account.id);
        showSuccess('User suspended.');
      }
      await loadAdminUser();
      showSuspendDialog = false;
    } catch {
      actionError = 'Failed to update suspension status.';
    } finally {
      actionLoading = false;
    }
  }

  // Revoke sessions
  function openRevokeConfirm() {
    clearMessages();
    showRevokeConfirm = true;
  }

  async function confirmRevokeSessions() {
    actionLoading = true;
    clearMessages();
    try {
      await revokeAllSessions(account.id);
      showSuccess('All sessions revoked.');
      showRevokeConfirm = false;
    } catch {
      actionError = 'Failed to revoke sessions.';
    } finally {
      actionLoading = false;
    }
  }

  // Trust level
  function openTrustLevel() {
    clearMessages();
    newTrustLevel = adminUser?.trust_level ?? 0;
    showTrustLevel = true;
  }

  async function confirmTrustLevel() {
    actionLoading = true;
    clearMessages();
    try {
      adminUser = await setTrustLevel(account.id, newTrustLevel);
      showSuccess(`Trust level set to ${newTrustLevel}.`);
      showTrustLevel = false;
    } catch {
      actionError = 'Failed to set trust level.';
    } finally {
      actionLoading = false;
    }
  }

  // Notes
  async function toggleNotes() {
    showNotes = !showNotes;
    if (showNotes && notes.length === 0) {
      notesLoading = true;
      try {
        notes = await getModerationNotes(account.id);
      } catch {
        actionError = 'Failed to load moderation notes.';
      } finally {
        notesLoading = false;
      }
    }
  }

  async function addNote() {
    if (!newNoteContent.trim()) return;
    addingNote = true;
    try {
      const note = await createModerationNote(account.id, newNoteContent.trim());
      notes = [note, ...notes];
      newNoteContent = '';
    } catch {
      actionError = 'Failed to add note.';
    } finally {
      addingNote = false;
    }
  }

  function closeAllDialogs() {
    showSilenceDialog = false;
    showShadowBanConfirm = false;
    showSuspendDialog = false;
    showRevokeConfirm = false;
    showTrustLevel = false;
  }
</script>

<div class="admin-profile-section">
  <button
    type="button"
    class="admin-profile-toggle"
    onclick={toggleExpanded}
    aria-expanded={expanded}
  >
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
    </svg>
    <span class="admin-profile-toggle-label">Moderation</span>
    <svg
      width="14" height="14"
      viewBox="0 0 24 24"
      fill="none" stroke="currentColor" stroke-width="2"
      class="admin-chevron"
      class:admin-chevron-open={expanded}
      aria-hidden="true"
    >
      <polyline points="6 9 12 15 18 9"/>
    </svg>
  </button>

  {#if expanded}
    <div class="admin-profile-panel">
      {#if loading}
        <div class="admin-panel-loading">Loading moderation data...</div>
      {:else if adminUser}
        <!-- Status badges -->
        <div class="admin-status-badges">
          <span class="admin-badge admin-badge-status" class:admin-badge-active={adminUser.status === 'active'} class:admin-badge-danger={adminUser.status === 'suspended'}>
            {adminUser.status}
          </span>
          {#if adminUser.silenced}
            <span class="admin-badge admin-badge-warn">Silenced</span>
          {/if}
          {#if adminUser.shadow_banned}
            <span class="admin-badge admin-badge-danger">Shadow Banned</span>
          {/if}
          {#if adminUser.force_sensitive}
            <span class="admin-badge admin-badge-warn">Force Sensitive</span>
          {/if}
          <span class="admin-badge admin-badge-info">Trust: {adminUser.trust_level}</span>
        </div>

        <!-- Feedback messages -->
        {#if actionError}
          <div class="admin-message admin-message-error" role="alert">{actionError}</div>
        {/if}
        {#if actionSuccess}
          <div class="admin-message admin-message-success" role="status">{actionSuccess}</div>
        {/if}

        <!-- Action buttons -->
        <div class="admin-action-grid">
          <button
            type="button"
            class="admin-action-button"
            class:admin-action-active={adminUser.silenced}
            onclick={adminUser.silenced ? confirmSilence : openSilenceDialog}
            disabled={actionLoading}
          >
            {adminUser.silenced ? 'Unsilence' : 'Silence'}
          </button>

          <button
            type="button"
            class="admin-action-button"
            class:admin-action-active={adminUser.shadow_banned}
            onclick={openShadowBanConfirm}
            disabled={actionLoading}
          >
            {adminUser.shadow_banned ? 'Remove Shadow Ban' : 'Shadow Ban'}
          </button>

          <button
            type="button"
            class="admin-action-button"
            class:admin-action-active={adminUser.force_sensitive}
            onclick={toggleForceSensitive}
            disabled={actionLoading}
          >
            {adminUser.force_sensitive ? 'Remove Force Sensitive' : 'Force Sensitive'}
          </button>

          <button
            type="button"
            class="admin-action-button admin-action-danger"
            class:admin-action-active={adminUser.status === 'suspended'}
            onclick={openSuspendDialog}
            disabled={actionLoading}
          >
            {adminUser.status === 'suspended' ? 'Unsuspend' : 'Suspend'}
          </button>

          <button
            type="button"
            class="admin-action-button admin-action-danger"
            onclick={openRevokeConfirm}
            disabled={actionLoading}
          >
            Revoke All Sessions
          </button>

          <button
            type="button"
            class="admin-action-button"
            onclick={openTrustLevel}
            disabled={actionLoading}
          >
            Set Trust Level
          </button>
        </div>

        <!-- Moderation notes toggle -->
        <button
          type="button"
          class="admin-notes-toggle"
          onclick={toggleNotes}
          aria-expanded={showNotes}
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/>
          </svg>
          View Moderation Notes ({notes.length})
        </button>

        {#if showNotes}
          <div class="admin-notes-section">
            <div class="admin-note-form">
              <textarea
                class="admin-note-input"
                bind:value={newNoteContent}
                placeholder="Add a moderation note..."
                rows="2"
              ></textarea>
              <button
                type="button"
                class="admin-note-submit"
                onclick={addNote}
                disabled={addingNote || !newNoteContent.trim()}
              >
                {addingNote ? 'Adding...' : 'Add Note'}
              </button>
            </div>

            {#if notesLoading}
              <div class="admin-panel-loading">Loading notes...</div>
            {:else if notes.length === 0}
              <p class="admin-notes-empty">No moderation notes yet.</p>
            {:else}
              <div class="admin-notes-list">
                {#each notes as note (note.id)}
                  <div class="admin-note">
                    <div class="admin-note-header">
                      <span class="admin-note-author">{note.author.display_name || note.author.handle}</span>
                      <time class="admin-note-time" datetime={note.created_at}>
                        {new Date(note.created_at).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' })}
                      </time>
                    </div>
                    <p class="admin-note-content">{note.content}</p>
                  </div>
                {/each}
              </div>
            {/if}
          </div>
        {/if}

        <!-- View in admin link -->
        <a href="/admin/users?q={account.handle}" class="admin-view-link">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/>
          </svg>
          View in Admin Panel
        </a>
      {/if}
    </div>
  {/if}
</div>

<!-- Silence dialog -->
{#if showSilenceDialog}
  <div class="admin-overlay" onclick={() => { showSilenceDialog = false; }} role="dialog" aria-modal="true" aria-label="Silence user">
    <div class="admin-dialog" onclick={(e) => e.stopPropagation()}>
      <h3 class="admin-dialog-title">Silence @{account.handle}</h3>
      <p class="admin-dialog-message">Silenced users can still post but won't appear in public timelines.</p>

      <div class="admin-dialog-form">
        <label class="admin-dialog-label" for="silence-duration">Duration</label>
        <select id="silence-duration" class="admin-dialog-select" bind:value={silenceDuration}>
          {#each durationOptions as opt (opt.value)}
            <option value={opt.value}>{opt.label}</option>
          {/each}
        </select>

        <label class="admin-dialog-label" for="silence-reason">Reason (optional)</label>
        <textarea
          id="silence-reason"
          class="admin-dialog-textarea"
          bind:value={silenceReason}
          placeholder="Reason for silencing..."
          rows="2"
        ></textarea>
      </div>

      <div class="admin-dialog-actions">
        <button type="button" class="admin-dialog-cancel" onclick={() => { showSilenceDialog = false; }}>Cancel</button>
        <button type="button" class="admin-dialog-confirm-warn" onclick={confirmSilence} disabled={actionLoading}>
          {actionLoading ? 'Processing...' : 'Silence User'}
        </button>
      </div>
    </div>
  </div>
{/if}

<!-- Shadow ban confirmation -->
{#if showShadowBanConfirm}
  <div class="admin-overlay" onclick={() => { showShadowBanConfirm = false; }} role="dialog" aria-modal="true" aria-label="Shadow ban user">
    <div class="admin-dialog" onclick={(e) => e.stopPropagation()}>
      <h3 class="admin-dialog-title">{adminUser?.shadow_banned ? 'Remove Shadow Ban' : 'Shadow Ban'} @{account.handle}</h3>
      <p class="admin-dialog-message">
        {#if adminUser?.shadow_banned}
          This will remove the shadow ban. The user's content will be visible again.
        {:else}
          Shadow banned users can post normally but their content is hidden from everyone else.
        {/if}
      </p>

      <div class="admin-dialog-actions">
        <button type="button" class="admin-dialog-cancel" onclick={() => { showShadowBanConfirm = false; }}>Cancel</button>
        <button type="button" class="admin-dialog-confirm-warn" onclick={confirmShadowBan} disabled={actionLoading}>
          {actionLoading ? 'Processing...' : (adminUser?.shadow_banned ? 'Remove Shadow Ban' : 'Shadow Ban')}
        </button>
      </div>
    </div>
  </div>
{/if}

<!-- Suspend dialog -->
{#if showSuspendDialog}
  <div class="admin-overlay" onclick={() => { showSuspendDialog = false; }} role="dialog" aria-modal="true" aria-label="Suspend user">
    <div class="admin-dialog" onclick={(e) => e.stopPropagation()}>
      <h3 class="admin-dialog-title">{adminUser?.status === 'suspended' ? 'Unsuspend' : 'Suspend'} @{account.handle}</h3>
      <p class="admin-dialog-message">
        {#if adminUser?.status === 'suspended'}
          This will reactivate the user's account.
        {:else}
          Suspended users cannot log in or interact. This is a severe action.
        {/if}
      </p>

      {#if adminUser?.status !== 'suspended'}
        <div class="admin-dialog-form">
          <label class="admin-dialog-label" for="suspend-reason">Reason (optional)</label>
          <textarea
            id="suspend-reason"
            class="admin-dialog-textarea"
            bind:value={suspendReason}
            placeholder="Reason for suspension..."
            rows="2"
          ></textarea>
        </div>
      {/if}

      <div class="admin-dialog-actions">
        <button type="button" class="admin-dialog-cancel" onclick={() => { showSuspendDialog = false; }}>Cancel</button>
        <button type="button" class="admin-dialog-confirm-danger" onclick={confirmSuspend} disabled={actionLoading}>
          {actionLoading ? 'Processing...' : (adminUser?.status === 'suspended' ? 'Unsuspend' : 'Suspend User')}
        </button>
      </div>
    </div>
  </div>
{/if}

<!-- Revoke sessions confirmation -->
{#if showRevokeConfirm}
  <div class="admin-overlay" onclick={() => { showRevokeConfirm = false; }} role="dialog" aria-modal="true" aria-label="Revoke all sessions">
    <div class="admin-dialog" onclick={(e) => e.stopPropagation()}>
      <h3 class="admin-dialog-title">Revoke all sessions</h3>
      <p class="admin-dialog-message">This will force @{account.handle} to log in again on all devices.</p>

      <div class="admin-dialog-actions">
        <button type="button" class="admin-dialog-cancel" onclick={() => { showRevokeConfirm = false; }}>Cancel</button>
        <button type="button" class="admin-dialog-confirm-danger" onclick={confirmRevokeSessions} disabled={actionLoading}>
          {actionLoading ? 'Revoking...' : 'Revoke All Sessions'}
        </button>
      </div>
    </div>
  </div>
{/if}

<!-- Trust level dialog -->
{#if showTrustLevel}
  <div class="admin-overlay" onclick={() => { showTrustLevel = false; }} role="dialog" aria-modal="true" aria-label="Set trust level">
    <div class="admin-dialog" onclick={(e) => e.stopPropagation()}>
      <h3 class="admin-dialog-title">Set Trust Level</h3>
      <p class="admin-dialog-message">Current trust level: {adminUser?.trust_level ?? 0}</p>

      <div class="admin-dialog-form">
        <label class="admin-dialog-label" for="trust-level">Trust Level</label>
        <select id="trust-level" class="admin-dialog-select" bind:value={newTrustLevel}>
          <option value={0}>0 - New User</option>
          <option value={1}>1 - Basic</option>
          <option value={2}>2 - Member</option>
          <option value={3}>3 - Trusted</option>
        </select>
      </div>

      <div class="admin-dialog-actions">
        <button type="button" class="admin-dialog-cancel" onclick={() => { showTrustLevel = false; }}>Cancel</button>
        <button type="button" class="admin-dialog-confirm" onclick={confirmTrustLevel} disabled={actionLoading}>
          {actionLoading ? 'Saving...' : 'Set Trust Level'}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .admin-profile-section {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-warning, #f59e0b);
    border-radius: var(--radius-xl);
    overflow: hidden;
  }

  .admin-profile-toggle {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    width: 100%;
    padding: var(--space-3) var(--space-4);
    background: transparent;
    border: none;
    cursor: pointer;
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-warning, #f59e0b);
    font-family: inherit;
    transition: background-color var(--transition-fast);
  }

  .admin-profile-toggle:hover {
    background: var(--color-warning-light, rgba(245, 158, 11, 0.08));
  }

  .admin-profile-toggle-label {
    flex: 1;
    text-align: start;
  }

  .admin-chevron {
    transition: transform var(--transition-fast);
  }

  .admin-chevron-open {
    transform: rotate(180deg);
  }

  .admin-profile-panel {
    padding: 0 var(--space-4) var(--space-4);
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .admin-panel-loading {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    text-align: center;
    padding: var(--space-4);
  }

  .admin-status-badges {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2);
  }

  .admin-badge {
    display: inline-flex;
    align-items: center;
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-sm);
    text-transform: capitalize;
  }

  .admin-badge-active {
    background: var(--color-success-light, rgba(34, 197, 94, 0.1));
    color: var(--color-success, #22c55e);
  }

  .admin-badge-status {
    background: var(--color-bg-tertiary);
    color: var(--color-text-secondary);
  }

  .admin-badge-warn {
    background: var(--color-warning-light, rgba(245, 158, 11, 0.1));
    color: var(--color-warning, #f59e0b);
  }

  .admin-badge-danger {
    background: var(--color-danger-light, rgba(239, 68, 68, 0.1));
    color: var(--color-danger, #ef4444);
  }

  .admin-badge-info {
    background: var(--color-primary-light, rgba(99, 102, 241, 0.1));
    color: var(--color-primary);
  }

  .admin-message {
    font-size: var(--text-sm);
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
  }

  .admin-message-error {
    background: var(--color-danger-light, rgba(239, 68, 68, 0.1));
    color: var(--color-danger, #ef4444);
  }

  .admin-message-success {
    background: var(--color-success-light, rgba(34, 197, 94, 0.1));
    color: var(--color-success, #22c55e);
  }

  .admin-action-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--space-2);
  }

  .admin-action-button {
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: transparent;
    color: var(--color-text);
    font-size: var(--text-xs);
    font-weight: 500;
    cursor: pointer;
    transition: background-color var(--transition-fast), border-color var(--transition-fast);
    font-family: inherit;
    text-align: center;
  }

  .admin-action-button:hover:not(:disabled) {
    background: var(--color-bg-tertiary);
    border-color: var(--color-text-tertiary);
  }

  .admin-action-button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .admin-action-active {
    background: var(--color-warning-light, rgba(245, 158, 11, 0.1));
    border-color: var(--color-warning, #f59e0b);
    color: var(--color-warning, #f59e0b);
  }

  .admin-action-danger {
    color: var(--color-danger, #ef4444);
    border-color: var(--color-danger-light, rgba(239, 68, 68, 0.2));
  }

  .admin-action-danger:hover:not(:disabled) {
    background: var(--color-danger-light, rgba(239, 68, 68, 0.1));
    border-color: var(--color-danger, #ef4444);
  }

  .admin-action-danger.admin-action-active {
    background: var(--color-danger-light, rgba(239, 68, 68, 0.1));
    border-color: var(--color-danger, #ef4444);
    color: var(--color-danger, #ef4444);
  }

  .admin-notes-toggle {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    width: 100%;
    padding: var(--space-2) 0;
    background: transparent;
    border: none;
    cursor: pointer;
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    font-family: inherit;
    transition: color var(--transition-fast);
  }

  .admin-notes-toggle:hover {
    color: var(--color-text);
  }

  .admin-notes-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .admin-note-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .admin-note-input {
    padding: var(--space-2);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    color: var(--color-text);
    background: var(--color-bg);
    resize: vertical;
    font-family: inherit;
  }

  .admin-note-input:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 2px var(--color-primary-light);
  }

  .admin-note-submit {
    align-self: flex-end;
    padding: var(--space-1) var(--space-3);
    border: none;
    border-radius: var(--radius-md);
    background: var(--color-primary);
    color: var(--color-text-inverse);
    font-size: var(--text-xs);
    font-weight: 600;
    cursor: pointer;
  }

  .admin-note-submit:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .admin-note-submit:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .admin-notes-empty {
    font-size: var(--text-sm);
    color: var(--color-text-tertiary);
    text-align: center;
    padding: var(--space-2) 0;
  }

  .admin-notes-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    max-height: 300px;
    overflow-y: auto;
  }

  .admin-note {
    padding: var(--space-2) var(--space-3);
    background: var(--color-bg-tertiary);
    border-radius: var(--radius-md);
  }

  .admin-note-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-block-end: var(--space-1);
  }

  .admin-note-author {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text);
  }

  .admin-note-time {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .admin-note-content {
    font-size: var(--text-sm);
    color: var(--color-text);
    white-space: pre-wrap;
    word-break: break-word;
  }

  .admin-view-link {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    color: var(--color-primary);
    text-decoration: none;
    padding: var(--space-1) 0;
  }

  .admin-view-link:hover {
    text-decoration: underline;
  }

  /* Dialog styles */
  .admin-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    backdrop-filter: blur(2px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 9999;
    animation: admin-overlay-in 0.15s ease;
  }

  @keyframes admin-overlay-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes admin-dialog-in {
    from { opacity: 0; transform: scale(0.95) translateY(4px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .admin-dialog {
    background: var(--color-surface-raised, #fff);
    border-radius: var(--radius-xl, 1rem);
    padding: var(--space-6, 1.5rem);
    max-width: 420px;
    width: 90%;
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.15);
    animation: admin-dialog-in 0.2s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .admin-dialog-title {
    font-size: var(--text-lg, 1.125rem);
    font-weight: 600;
    margin-block-end: var(--space-2, 0.5rem);
  }

  .admin-dialog-message {
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text-secondary, #64748b);
    margin-block-end: var(--space-4, 1rem);
  }

  .admin-dialog-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-2, 0.5rem);
    margin-block-end: var(--space-4, 1rem);
  }

  .admin-dialog-label {
    font-size: var(--text-sm, 0.875rem);
    font-weight: 500;
    color: var(--color-text, #0f172a);
  }

  .admin-dialog-select {
    padding: var(--space-2, 0.5rem);
    border: 1px solid var(--color-border, #e2e8f0);
    border-radius: var(--radius-md, 0.5rem);
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text, #0f172a);
    background: var(--color-bg, #fff);
  }

  .admin-dialog-textarea {
    padding: var(--space-2, 0.5rem);
    border: 1px solid var(--color-border, #e2e8f0);
    border-radius: var(--radius-md, 0.5rem);
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text, #0f172a);
    background: var(--color-bg, #fff);
    resize: vertical;
    font-family: inherit;
  }

  .admin-dialog-textarea:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 2px var(--color-primary-light);
  }

  .admin-dialog-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3, 0.75rem);
  }

  .admin-dialog-cancel {
    padding: var(--space-2, 0.5rem) var(--space-4, 1rem);
    border: 1px solid var(--color-border, #e2e8f0);
    border-radius: var(--radius-md, 0.5rem);
    background: transparent;
    color: var(--color-text, #0f172a);
    font-size: var(--text-sm, 0.875rem);
    cursor: pointer;
  }

  .admin-dialog-cancel:hover {
    background: var(--color-bg-tertiary);
  }

  .admin-dialog-confirm {
    padding: var(--space-2, 0.5rem) var(--space-4, 1rem);
    border: none;
    border-radius: var(--radius-md, 0.5rem);
    background: var(--color-primary);
    color: white;
    font-size: var(--text-sm, 0.875rem);
    font-weight: 600;
    cursor: pointer;
  }

  .admin-dialog-confirm:hover {
    opacity: 0.9;
  }

  .admin-dialog-confirm:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .admin-dialog-confirm-warn {
    padding: var(--space-2, 0.5rem) var(--space-4, 1rem);
    border: none;
    border-radius: var(--radius-md, 0.5rem);
    background: var(--color-warning, #f59e0b);
    color: white;
    font-size: var(--text-sm, 0.875rem);
    font-weight: 600;
    cursor: pointer;
  }

  .admin-dialog-confirm-warn:hover {
    opacity: 0.9;
  }

  .admin-dialog-confirm-warn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .admin-dialog-confirm-danger {
    padding: var(--space-2, 0.5rem) var(--space-4, 1rem);
    border: none;
    border-radius: var(--radius-md, 0.5rem);
    background: var(--color-danger, #ef4444);
    color: white;
    font-size: var(--text-sm, 0.875rem);
    font-weight: 600;
    cursor: pointer;
  }

  .admin-dialog-confirm-danger:hover {
    opacity: 0.9;
  }

  .admin-dialog-confirm-danger:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  @media (max-width: 480px) {
    .admin-action-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
