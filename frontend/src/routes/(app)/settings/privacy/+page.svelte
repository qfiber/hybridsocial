<script lang="ts">
  import { get } from 'svelte/store';
  import { onMount } from 'svelte';
  import { authStore, setUser } from '$lib/stores/auth.js';
  import { updateAccount, getAccount } from '$lib/api/accounts.js';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import { preferencesStore, updatePreferences } from '$lib/stores/preferences.js';
  import Toggle from '$lib/components/ui/Toggle.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import {
    isAutoLoadRemoteMedia,
    setAutoLoadRemoteMedia,
  } from '$lib/utils/media-preferences.js';

  let isLocked: boolean = $state(false);
  let discoverable: boolean = $state(true);
  let allowUnfurl: boolean = $state(true);
  let hideFollowCounts: boolean = $state(false);
  let dmPreference: string = $state('everyone');
  let groupDmOptIn: boolean = $state(false);
  type InvitePref = 'anyone' | 'only_follows' | 'nobody';
  let allowGroupInvites: InvitePref = $state('anyone');
  let allowPageInvites: InvitePref = $state('anyone');
  let loaded = $state(false);
  let defaultVisibility = $state<string>('public');
  let autoLoadRemoteMedia = $state(true);
  let saving = $state(false);

  // Media preference is local-only — flushes to localStorage on
  // every change, takes effect immediately on every visible
  // <LazyMedia> via the autoLoadRemoteMedia store.
  $effect(() => {
    if (loaded) setAutoLoadRemoteMedia(autoLoadRemoteMedia);
  });

  onMount(async () => {
    const state = get(authStore);
    if (state.user) {
      isLocked = state.user.is_locked ?? false;
      discoverable = (state.user as any).discoverable ?? true;
      allowUnfurl = (state.user as any).allow_unfurl ?? true;
      hideFollowCounts = (state.user as any).hide_follow_counts ?? false;
      allowGroupInvites = ((state.user as any).allow_group_invites ?? 'anyone') as InvitePref;
      allowPageInvites = ((state.user as any).allow_page_invites ?? 'anyone') as InvitePref;
    }

    // Load default visibility from local preferences
    const prefs = get(preferencesStore);
    defaultVisibility = prefs.default_visibility || 'public';

    // Media auto-load preference (localStorage)
    autoLoadRemoteMedia = isAutoLoadRemoteMedia();

    // Refresh the account-level flags from the server so a stale cached
    // snapshot doesn't misrepresent (or silently re-save) the wrong
    // values. `also_known_as` / invite prefs aren't serialised here, so
    // those stay as the cached values.
    const uid = state.user?.id;
    if (uid) {
      try {
        const fresh = await getAccount(uid);
        isLocked = fresh.is_locked ?? isLocked;
        discoverable = (fresh as any).discoverable ?? discoverable;
        allowUnfurl = (fresh as any).allow_unfurl ?? allowUnfurl;
        hideFollowCounts = fresh.hide_follow_counts ?? hideFollowCounts;
      } catch {
        // Keep cached values.
      }
    }

    try {
      const dmPrefs = await api.get<any>('/api/v1/dm_preferences');
      dmPreference = dmPrefs.allow_dms_from || 'everyone';
      groupDmOptIn = dmPrefs.allow_group_dms ?? false;
    } catch {
      // Fall back to defaults, but tell the user we couldn't load their
      // saved message settings so a failed fetch isn't mistaken for
      // "everyone can DM me".
      addToast('Could not load your message settings', 'error');
    }
    loaded = true;
  });

  async function handleSave() {
    if (saving) return;
    saving = true;
    try {
      const updated = await updateAccount({
        is_locked: isLocked,
        discoverable,
        allow_unfurl: allowUnfurl,
        hide_follow_counts: hideFollowCounts,
        allow_group_invites: allowGroupInvites,
        allow_page_invites: allowPageInvites,
      } as any);
      setUser(updated);

      await api.patch('/api/v1/dm_preferences', {
        allow_dms_from: dmPreference,
        allow_group_dms: groupDmOptIn,
      });

      // Save default visibility (syncs to server automatically)
      updatePreferences({ default_visibility: defaultVisibility as any });

      addToast('Privacy settings saved', 'success');
    } catch (e) {
      addToast(e instanceof Error ? e.message : 'Failed to save privacy settings', 'error');
    } finally {
      saving = false;
    }
  }
</script>

<div class="settings-section">
  <h2 class="section-title">Privacy</h2>

  <form class="settings-form" onsubmit={(e) => { e.preventDefault(); handleSave(); }}>
    <div class="setting-row">
      <div class="setting-info">
        <span class="setting-label">Lock account</span>
        <span class="setting-description">Manually approve follow requests</span>
      </div>
      <Toggle bind:checked={isLocked} name="locked" />
    </div>

    <div class="setting-row">
      <div class="setting-info">
        <span class="setting-label">Group invites</span>
        <span class="setting-description">
          Who can invite you into a group. "Only people I follow" treats
          the existing follow graph as your allow-list. "Nobody" rejects
          invites at the database level — no notification, no pending
          row, just a polite 403 to the inviter.
        </span>
      </div>
      <select class="setting-select" bind:value={allowGroupInvites}>
        <option value="anyone">Anyone</option>
        <option value="only_follows">Only people I follow</option>
        <option value="nobody">Nobody</option>
      </select>
    </div>

    <div class="setting-row">
      <div class="setting-info">
        <span class="setting-label">Page manager invites</span>
        <span class="setting-description">
          Who can invite you to co-manage an organization page. Same
          three-way policy as group invites.
        </span>
      </div>
      <select class="setting-select" bind:value={allowPageInvites}>
        <option value="anyone">Anyone</option>
        <option value="only_follows">Only people I follow</option>
        <option value="nobody">Nobody</option>
      </select>
    </div>

    <div class="setting-row">
      <div class="setting-info">
        <span class="setting-label">Show me in the directory and search engines</span>
        <span class="setting-description">
          Appear in the New Members widget and the <a href="/directory">directory</a>
          when you're a recent signup, and let search engines index your profile and
          public posts. When off, your profile page and public posts can still be
          viewed without logging in, but aren't promoted or indexed.
        </span>
      </div>
      <Toggle bind:checked={discoverable} name="discoverable" />
    </div>

    <div class="setting-row">
      <div class="setting-info">
        <span class="setting-label">Hide follower & following counts</span>
        <span class="setting-description">
          When on, your follower / following totals are hidden from
          everyone except you. The lists themselves stay accessible
          to people you've chosen to share them with — this just
          removes the headline numbers from your profile.
        </span>
      </div>
      <Toggle bind:checked={hideFollowCounts} name="hide-follow-counts" />
    </div>

    <div class="setting-row">
      <div class="setting-info">
        <span class="setting-label">Allow link previews of my profile</span>
        <span class="setting-description">
          When someone shares <code>/@{'{'}your-handle{'}'}</code> on WhatsApp,
          Telegram, Facebook, Discord, etc., the link can unfurl into a card
          with your display name, avatar, and bio. Turn this off and those
          platforms only see a generic placeholder — the link still works,
          but your profile details aren't exposed to external services.
        </span>
      </div>
      <Toggle bind:checked={allowUnfurl} name="allow-unfurl" />
    </div>

    <div class="setting-divider"></div>

    <div class="encryption-notice">
      <div class="encryption-notice-title">
        <span class="material-symbols-outlined encryption-notice-icon">lock</span>
        <span>Direct message encryption</span>
      </div>
      <p>
        <strong>Local DMs are encrypted at rest</strong> — stored as ciphertext
        in our database with a per-conversation key (amber lock icon in your
        inbox). We can decrypt them if compelled. This is not end-to-end encryption.
      </p>
      <p>
        DMs with people on other servers travel over HTTPS but the remote
        server sees plaintext.
      </p>
      <p class="encryption-notice-dim">
        End-to-end encryption (green lock) is on the roadmap. Until then,
        use Signal or Matrix for conversations that must stay private.
      </p>
    </div>

    <div class="setting-divider"></div>

    <div class="form-group">
      <label class="form-label" for="dm-pref">Who can send you direct messages</label>
      <select id="dm-pref" class="input" bind:value={dmPreference}>
        <option value="everyone">Everyone</option>
        <option value="followers">Followers only</option>
        <option value="mutual">Mutual followers only</option>
        <option value="nobody">Nobody</option>
      </select>
    </div>

    <div class="setting-row">
      <div class="setting-info">
        <span class="setting-label">Allow group DM invites</span>
        <span class="setting-description">Let others add you to group conversations</span>
      </div>
      <Toggle bind:checked={groupDmOptIn} name="group-dm" />
    </div>

    <div class="setting-divider"></div>

    <div class="setting-row">
      <div class="setting-info">
        <span class="setting-label">Auto-load remote media</span>
        <span class="setting-description">
          When on, images and videos from other instances load
          automatically as you scroll. Turn off to save data on
          metered connections — remote media stays as a tap-to-load
          placeholder until you ask for it. Posts from this instance
          always auto-load.
        </span>
      </div>
      <Toggle bind:checked={autoLoadRemoteMedia} name="auto-load-remote-media" />
    </div>

    <div class="setting-divider"></div>

    <div class="form-group">
      <label class="form-label" for="default-vis">Default post visibility</label>
      <select id="default-vis" class="input" bind:value={defaultVisibility}>
        <option value="public">Public</option>
        <option value="followers">Followers only</option>
        <option value="direct">Direct (mentioned people only)</option>
      </select>
      <span class="form-hint">New posts will default to this visibility setting</span>
    </div>

    <div class="form-actions">
      <button class="btn btn-primary" type="submit" disabled={saving}>
        {#if saving}
          <Spinner size={16} color="var(--color-text-on-primary)" />
        {/if}
        Save changes
      </button>
    </div>
  </form>
</div>

<style>
  .settings-section {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow: hidden;
  }

  .section-title {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--color-text);
    padding: var(--space-4) var(--space-6);
    border-block-end: 1px solid var(--color-border);
  }

  .settings-form {
    padding: var(--space-6);
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .setting-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-4);
  }

  .setting-select {
    min-width: 180px;
    padding: 8px 12px;
    border: 1px solid var(--color-border);
    border-radius: 8px;
    background: var(--color-surface-container-lowest, #fff);
    color: var(--color-text);
    font-size: var(--text-sm);
    cursor: pointer;
  }

  .setting-select:focus {
    outline: 2px solid var(--color-primary);
    outline-offset: 1px;
  }

  .setting-info {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .setting-label {
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
  }

  .setting-description {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .setting-divider {
    height: 1px;
    background: var(--color-border);
  }

  .encryption-notice {
    background: var(--color-surface-alt, rgba(0,0,0,0.03));
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    padding: var(--space-4);
    font-size: var(--text-sm);
    color: var(--color-text);
  }

  .encryption-notice-title {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-weight: 700;
    margin-block-end: var(--space-2);
  }

  .encryption-notice-icon {
    font-size: 18px;
    color: var(--color-warning, #d97706);
  }

  .encryption-notice p {
    margin: 0 0 var(--space-2) 0;
    line-height: 1.5;
  }

  .encryption-notice p:last-child {
    margin-block-end: 0;
  }

  .encryption-notice-dim {
    color: var(--color-text-tertiary);
    font-size: var(--text-xs);
  }

  .form-group {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .form-label {
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
  }

  .form-hint {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .form-actions {
    display: flex;
    justify-content: flex-end;
  }
</style>
