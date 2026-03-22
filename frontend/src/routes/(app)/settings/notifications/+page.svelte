<script lang="ts">
  import { onMount } from 'svelte';
  import { getNotificationPreferences, updateNotificationPreferences } from '$lib/api/notifications.js';
  import Toggle from '$lib/components/ui/Toggle.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let follows = $state(true);
  let reactions = $state(true);
  let boosts = $state(true);
  let mentions = $state(true);
  let polls = $state(true);
  let groupInvites = $state(true);

  let saving = $state(false);
  let saved = $state(false);
  let loading = $state(true);
  let error: string | null = $state(null);

  onMount(async () => {
    try {
      const prefs = await getNotificationPreferences();
      follows = prefs.follows;
      reactions = prefs.favourites;
      boosts = prefs.boosts;
      mentions = prefs.mentions;
      polls = prefs.polls;
      groupInvites = prefs.group_invites;
    } catch {
      // Use defaults
    } finally {
      loading = false;
    }
  });

  async function handleSave() {
    saving = true;
    error = null;
    saved = false;
    try {
      await updateNotificationPreferences({
        follows,
        favourites: reactions,
        boosts,
        mentions,
        polls,
        group_invites: groupInvites,
      });
      saved = true;
      setTimeout(() => { saved = false; }, 3000);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to save';
    } finally {
      saving = false;
    }
  }

</script>

<div class="settings-section">
  <h2 class="section-title">Notification Preferences</h2>

  {#if loading}
    <div class="settings-loading">
      <Spinner />
    </div>
  {:else}
    <form class="settings-form" onsubmit={(e) => { e.preventDefault(); handleSave(); }}>
      <p class="form-description">Choose which notifications you want to receive.</p>

      <div class="setting-row">
        <div class="setting-info">
          <span class="setting-label">Follows</span>
          <span class="setting-description">Someone follows you or sends a follow request</span>
        </div>
        <Toggle bind:checked={follows} name="follows" />
      </div>

      <div class="setting-row">
        <div class="setting-info">
          <span class="setting-label">Mentions</span>
          <span class="setting-description">Someone mentions you in a post</span>
        </div>
        <Toggle bind:checked={mentions} name="mentions" />
      </div>

      <div class="setting-row">
        <div class="setting-info">
          <span class="setting-label">Reactions</span>
          <span class="setting-description">Someone reacts to or favourites your post</span>
        </div>
        <Toggle bind:checked={reactions} name="reactions" />
      </div>

      <div class="setting-row">
        <div class="setting-info">
          <span class="setting-label">Boosts</span>
          <span class="setting-description">Someone boosts your post</span>
        </div>
        <Toggle bind:checked={boosts} name="boosts" />
      </div>

      <div class="setting-row">
        <div class="setting-info">
          <span class="setting-label">Polls</span>
          <span class="setting-description">A poll you voted in has ended</span>
        </div>
        <Toggle bind:checked={polls} name="polls" />
      </div>

      <div class="setting-row">
        <div class="setting-info">
          <span class="setting-label">Group invites</span>
          <span class="setting-description">Someone invites you to a group</span>
        </div>
        <Toggle bind:checked={groupInvites} name="groupInvites" />
      </div>

      {#if error}
        <div class="form-error">{error}</div>
      {/if}

      {#if saved}
        <div class="form-success">Notification preferences saved</div>
      {/if}

      <div class="form-actions">
        <button class="btn btn-primary" type="submit" disabled={saving}>
          {#if saving}
            <Spinner size={16} color="var(--color-text-on-primary)" />
          {/if}
          Save changes
        </button>
      </div>
    </form>
  {/if}
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

  .settings-loading {
    display: flex;
    justify-content: center;
    padding: var(--space-8);
  }

  .form-description {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .setting-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-4);
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

  .form-error {
    padding: var(--space-3);
    background: var(--color-danger-soft);
    color: var(--color-danger);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  .form-success {
    padding: var(--space-3);
    background: var(--color-success-soft);
    color: var(--color-success);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  .form-actions {
    display: flex;
    justify-content: flex-end;
  }
</style>
