<script lang="ts">
  import { get } from 'svelte/store';
  import { onMount } from 'svelte';
  import { authStore, setUser } from '$lib/stores/auth.js';
  import { updateAccount, updateAvatar, updateHeader } from '$lib/api/accounts.js';
  import type { Identity } from '$lib/api/types.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  let displayName = $state('');
  let bio = $state('');
  let handle = $state('');
  let avatarUrl: string | null = $state(null);
  let headerUrl: string | null = $state(null);
  let showBadge = $state(true);
  let saving = $state(false);
  let saved = $state(false);
  let error: string | null = $state(null);
  let avatarInput: HTMLInputElement | undefined = $state();
  let headerInput: HTMLInputElement | undefined = $state();

  onMount(() => {
    const state = get(authStore);
    if (state.user) {
      displayName = state.user.display_name || '';
      bio = state.user.bio || '';
      handle = state.user.handle;
      avatarUrl = state.user.avatar_url;
      headerUrl = state.user.header_url;
      showBadge = (state.user as any).show_badge !== false;
    }
  });

  async function handleSave() {
    saving = true;
    error = null;
    saved = false;
    try {
      const updated = await updateAccount({
        display_name: displayName,
        bio,
        show_badge: showBadge,
      });
      setUser(updated);
      saved = true;
      setTimeout(() => { saved = false; }, 3000);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to save';
    } finally {
      saving = false;
    }
  }

  async function handleAvatarChange(e: Event) {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    try {
      const updated = await updateAvatar(file);
      avatarUrl = updated.avatar_url;
      setUser(updated);
    } catch (err) {
      error = err instanceof Error ? err.message : 'Failed to upload avatar';
    }
  }

  async function handleHeaderChange(e: Event) {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    try {
      const updated = await updateHeader(file);
      headerUrl = updated.header_url;
      setUser(updated);
    } catch (err) {
      error = err instanceof Error ? err.message : 'Failed to upload header';
    }
  }
</script>

<div class="settings-section">
  <h2 class="section-title">Edit Profile</h2>

  <div class="header-preview" onclick={() => headerInput?.click()} role="button" tabindex="0" onkeydown={(e) => { if (e.key === 'Enter') headerInput?.click(); }}>
    {#if headerUrl}
      <img src={headerUrl} alt="" class="header-preview-img" />
    {:else}
      <div class="header-preview-placeholder">
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/>
        </svg>
        <span>Change header image</span>
      </div>
    {/if}
    <input bind:this={headerInput} type="file" accept="image/*" class="visually-hidden" onchange={handleHeaderChange} />
  </div>

  <div class="avatar-edit">
    <button type="button" class="avatar-edit-btn" onclick={() => avatarInput?.click()} aria-label="Change avatar">
      <Avatar src={avatarUrl} name={displayName || handle} size="xl" />
      <div class="avatar-edit-overlay">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/>
        </svg>
      </div>
    </button>
    <input bind:this={avatarInput} type="file" accept="image/*" class="visually-hidden" onchange={handleAvatarChange} />
  </div>

  <form class="settings-form" onsubmit={(e) => { e.preventDefault(); handleSave(); }}>
    <div class="form-group">
      <label class="form-label" for="display-name">Display name</label>
      <input
        id="display-name"
        type="text"
        class="input"
        bind:value={displayName}
        placeholder="Your display name"
        maxlength="50"
      />
    </div>

    <div class="form-group">
      <label class="form-label" for="bio">Bio</label>
      <textarea
        id="bio"
        class="textarea"
        bind:value={bio}
        placeholder="Tell people about yourself"
        maxlength="500"
        rows="4"
      ></textarea>
      <span class="form-hint">{bio.length}/500</span>
    </div>

    <div class="form-group">
      <label class="form-label" for="handle">Handle</label>
      <input
        id="handle"
        type="text"
        class="input"
        value={handle}
        disabled
      />
      <span class="form-hint">Your handle is permanent and cannot be changed. This ensures stable identity across the federation.</span>
    </div>

    <div class="form-group">
      <label class="form-toggle-row">
        <input type="checkbox" bind:checked={showBadge} class="form-checkbox" />
        <div>
          <span class="form-label">Show role badge</span>
          <span class="form-hint">Display your instance role badge (Admin, Moderator, Owner) on your profile and posts. Group and page badges are always visible.</span>
        </div>
      </label>
    </div>

    {#if error}
      <div class="form-error">{error}</div>
    {/if}

    {#if saved}
      <div class="form-success">Profile saved successfully</div>
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

  .header-preview {
    height: 140px;
    cursor: pointer;
    position: relative;
    overflow: hidden;
  }

  .header-preview:hover .header-preview-placeholder,
  .header-preview:hover .header-preview-img {
    opacity: 0.7;
  }

  .header-preview-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    transition: opacity var(--transition-fast);
  }

  .header-preview-placeholder {
    width: 100%;
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--space-2);
    background: var(--color-surface);
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    transition: opacity var(--transition-fast);
  }

  .avatar-edit {
    padding-inline-start: var(--space-6);
    margin-block-start: -40px;
    position: relative;
    z-index: 1;
  }

  .avatar-edit-btn {
    position: relative;
    border: 4px solid var(--color-surface-raised);
    border-radius: var(--radius-full);
    background: none;
    padding: 0;
    cursor: pointer;
    display: block;
  }

  .avatar-edit-overlay {
    position: absolute;
    inset: 0;
    border-radius: var(--radius-full);
    background: rgba(0, 0, 0, 0.4);
    display: flex;
    align-items: center;
    justify-content: center;
    color: white;
    opacity: 0;
    transition: opacity var(--transition-fast);
  }

  .avatar-edit-btn:hover .avatar-edit-overlay {
    opacity: 1;
  }

  .settings-form {
    padding: var(--space-6);
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
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

  .form-toggle-row {
    display: flex;
    align-items: flex-start;
    gap: var(--space-3);
    cursor: pointer;
  }

  .form-checkbox {
    width: 18px;
    height: 18px;
    accent-color: var(--color-primary);
    margin-top: 2px;
    flex-shrink: 0;
  }

  .form-hint {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .form-warning {
    color: var(--color-warning);
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
