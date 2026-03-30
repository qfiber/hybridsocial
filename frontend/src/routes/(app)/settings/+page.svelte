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

  function handleDiscard() {
    const state = get(authStore);
    if (state.user) {
      displayName = state.user.display_name || '';
      bio = state.user.bio || '';
      showBadge = (state.user as any).show_badge !== false;
    }
    error = null;
    saved = false;
  }
</script>

<div class="stitch-settings">
  <!-- Page header -->
  <div class="stitch-settings-header">
    <h1 class="stitch-settings-title">Account Settings</h1>
    <p class="stitch-settings-subtitle">Manage your profile, preferences, and account details</p>
  </div>

  <!-- Profile Section -->
  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>
        </svg>
      </span>
      <h2 class="stitch-section-title">Profile</h2>
    </div>

    <div class="stitch-section-content">
      <!-- Header image -->
      <div class="stitch-header-preview" onclick={() => headerInput?.click()} role="button" tabindex="0" onkeydown={(e) => { if (e.key === 'Enter') headerInput?.click(); }}>
        <img src={headerUrl || '/images/default-cover.svg'} alt="" class="stitch-header-img" />
        <div class="stitch-header-overlay">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/>
          </svg>
        </div>
        <input bind:this={headerInput} type="file" accept="image/*" class="visually-hidden" onchange={handleHeaderChange} />
      </div>

      <!-- Avatar -->
      <div class="stitch-avatar-area">
        <button type="button" class="stitch-avatar-btn" onclick={() => avatarInput?.click()} aria-label="Change avatar">
          <Avatar src={avatarUrl} name={displayName || handle} size="xl" />
          <div class="stitch-avatar-overlay">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
              <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/>
            </svg>
          </div>
        </button>
        <input bind:this={avatarInput} type="file" accept="image/*" class="visually-hidden" onchange={handleAvatarChange} />
      </div>

      <!-- Form fields -->
      <form class="stitch-form" onsubmit={(e) => { e.preventDefault(); handleSave(); }}>
        <div class="stitch-field">
          <label class="stitch-label" for="display-name">DISPLAY NAME</label>
          <input
            id="display-name"
            type="text"
            class="stitch-input"
            bind:value={displayName}
            placeholder="Your display name"
            maxlength="50"
          />
        </div>

        <div class="stitch-field">
          <label class="stitch-label" for="bio">BIO</label>
          <textarea
            id="bio"
            class="stitch-textarea"
            bind:value={bio}
            placeholder="Tell people about yourself"
            maxlength="500"
            rows="4"
          ></textarea>
          <span class="stitch-hint">{bio.length}/500</span>
        </div>

        <div class="stitch-field">
          <label class="stitch-label" for="handle">HANDLE</label>
          <input
            id="handle"
            type="text"
            class="stitch-input stitch-input-disabled"
            value={handle}
            disabled
          />
          <span class="stitch-hint">Your handle is permanent and cannot be changed. This ensures stable identity across the federation.</span>
        </div>

        <!-- Show badge toggle -->
        <div class="stitch-toggle-row">
          <div class="stitch-toggle-info">
            <span class="stitch-toggle-label">Show role badge</span>
            <span class="stitch-toggle-desc">Display your instance role badge (Admin, Moderator, Owner) on your profile and posts. Group and page badges are always visible.</span>
          </div>
          <label class="stitch-switch">
            <input type="checkbox" bind:checked={showBadge} />
            <span class="stitch-switch-track"></span>
          </label>
        </div>

        {#if error}
          <div class="stitch-error">{error}</div>
        {/if}

        {#if saved}
          <div class="stitch-success">Profile saved successfully</div>
        {/if}

        <div class="stitch-actions">
          <button class="stitch-btn-ghost" type="button" onclick={handleDiscard}>
            Discard Changes
          </button>
          <button class="stitch-btn-primary" type="submit" disabled={saving}>
            {#if saving}
              <Spinner size={16} color="#fff" />
            {/if}
            Save Settings
          </button>
        </div>
      </form>
    </div>
  </section>
</div>

<style>
  /* ---- Page header ---- */
  .stitch-settings {
    max-width: 720px;
  }

  .stitch-settings-header {
    margin-block-end: 32px;
  }

  .stitch-settings-title {
    font-family: 'Manrope', var(--font-sans);
    font-size: 1.875rem;
    font-weight: 800;
    letter-spacing: -0.025em;
    color: var(--color-text);
    margin: 0;
  }

  .stitch-settings-subtitle {
    font-size: 0.875rem;
    color: #6b7280;
    margin-block-start: 4px;
  }

  /* ---- Section ---- */
  .stitch-section {
    margin-block-end: 24px;
  }

  .stitch-section-heading {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-block-end: 16px;
  }

  .stitch-section-icon {
    color: var(--color-primary);
    display: flex;
    align-items: center;
  }

  .stitch-section-title {
    font-size: 1.125rem;
    font-weight: 700;
    color: var(--color-text);
    margin: 0;
  }

  /* ---- Section content container ---- */
  .stitch-section-content {
    background: #f2f4f5;
    border-radius: 16px;
    padding: 0;
    overflow: hidden;
  }

  /* ---- Header image ---- */
  .stitch-header-preview {
    height: 160px;
    cursor: pointer;
    position: relative;
    overflow: hidden;
    background: #e6e8e9;
  }

  .stitch-header-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    transition: opacity 0.2s ease;
  }

  .stitch-header-placeholder {
    width: 100%;
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    color: #9ca3af;
    font-size: 0.8125rem;
  }

  .stitch-header-overlay {
    position: absolute;
    inset: 0;
    background: rgba(0, 0, 0, 0.35);
    display: flex;
    align-items: center;
    justify-content: center;
    color: white;
    opacity: 0;
    transition: opacity 0.2s ease;
  }

  .stitch-header-preview:hover .stitch-header-overlay {
    opacity: 1;
  }

  /* ---- Avatar ---- */
  .stitch-avatar-area {
    padding-inline-start: 32px;
    margin-block-start: -40px;
    margin-block-end: 8px;
    position: relative;
    z-index: 1;
  }

  .stitch-avatar-btn {
    position: relative;
    border: none;
    padding: 0;
    cursor: pointer;
    background: none;
    display: block;
    border-radius: 50%;
    ring: none;
  }

  .stitch-avatar-btn :global(.avatar) {
    width: 96px !important;
    height: 96px !important;
    ring: 4px solid white;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.12);
    border: 4px solid white;
    border-radius: 50%;
  }

  .stitch-avatar-overlay {
    position: absolute;
    inset: 0;
    border-radius: 50%;
    background: rgba(0, 0, 0, 0.4);
    display: flex;
    align-items: center;
    justify-content: center;
    color: white;
    opacity: 0;
    transition: opacity 0.2s ease;
  }

  .stitch-avatar-btn:hover .stitch-avatar-overlay {
    opacity: 1;
  }

  /* ---- Form ---- */
  .stitch-form {
    padding: 24px 32px 32px;
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .stitch-field {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .stitch-label {
    font-size: 0.6875rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #6b7280;
    margin-inline-start: 4px;
  }

  .stitch-input {
    display: block;
    width: 100%;
    padding: 12px 16px;
    background: #e6e8e9;
    border: none;
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    transition: background-color 0.2s ease, box-shadow 0.2s ease;
  }

  .stitch-input::placeholder {
    color: #9ca3af;
  }

  .stitch-input:focus {
    outline: none;
    background: white;
    box-shadow: 0 0 0 2px rgba(var(--color-primary-rgb, 59, 130, 246), 0.2);
  }

  .stitch-input-disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .stitch-textarea {
    display: block;
    width: 100%;
    padding: 12px 16px;
    background: #e6e8e9;
    border: none;
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    resize: vertical;
    font-family: inherit;
    transition: background-color 0.2s ease, box-shadow 0.2s ease;
  }

  .stitch-textarea::placeholder {
    color: #9ca3af;
  }

  .stitch-textarea:focus {
    outline: none;
    background: white;
    box-shadow: 0 0 0 2px rgba(var(--color-primary-rgb, 59, 130, 246), 0.2);
  }

  .stitch-hint {
    font-size: 0.75rem;
    color: #9ca3af;
    margin-inline-start: 4px;
  }

  /* ---- Toggle row ---- */
  .stitch-toggle-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    padding: 12px 0;
    border-block-start: 1px solid rgba(0, 0, 0, 0.06);
  }

  .stitch-toggle-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .stitch-toggle-label {
    font-size: 0.875rem;
    font-weight: 500;
    color: var(--color-text);
  }

  .stitch-toggle-desc {
    font-size: 0.75rem;
    color: #9ca3af;
    line-height: 1.4;
  }

  /* Pill-shaped toggle switch */
  .stitch-switch {
    position: relative;
    display: inline-flex;
    cursor: pointer;
    flex-shrink: 0;
  }

  .stitch-switch input {
    position: absolute;
    opacity: 0;
    width: 0;
    height: 0;
  }

  .stitch-switch-track {
    width: 44px;
    height: 24px;
    background: #d1d5db;
    border-radius: 12px;
    position: relative;
    transition: background-color 0.2s ease;
  }

  .stitch-switch-track::after {
    content: '';
    position: absolute;
    top: 2px;
    left: 2px;
    width: 20px;
    height: 20px;
    background: white;
    border-radius: 50%;
    transition: transform 0.2s ease;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.15);
  }

  .stitch-switch input:checked + .stitch-switch-track {
    background: var(--color-primary);
  }

  .stitch-switch input:checked + .stitch-switch-track::after {
    transform: translateX(20px);
  }

  /* ---- Error / Success ---- */
  .stitch-error {
    padding: 12px 16px;
    background: #fef2f2;
    color: #dc2626;
    border-radius: 10px;
    font-size: 0.875rem;
  }

  .stitch-success {
    padding: 12px 16px;
    background: #f0fdf4;
    color: #16a34a;
    border-radius: 10px;
    font-size: 0.875rem;
  }

  /* ---- Action buttons ---- */
  .stitch-actions {
    display: flex;
    justify-content: flex-end;
    gap: 12px;
    padding-block-start: 8px;
  }

  .stitch-btn-ghost {
    padding: 10px 24px;
    background: transparent;
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    color: #6b7280;
    cursor: pointer;
    transition: color 0.15s ease, background-color 0.15s ease;
  }

  .stitch-btn-ghost:hover {
    color: var(--color-text);
    background: rgba(0, 0, 0, 0.04);
  }

  .stitch-btn-primary {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 10px 28px;
    background: var(--color-primary);
    color: white;
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    box-shadow: 0 4px 14px rgba(var(--color-primary-rgb, 59, 130, 246), 0.2);
    transition: background-color 0.15s ease, box-shadow 0.15s ease, transform 0.1s ease;
  }

  .stitch-btn-primary:hover:not(:disabled) {
    background: var(--color-primary-hover);
    box-shadow: 0 6px 20px rgba(var(--color-primary-rgb, 59, 130, 246), 0.3);
  }

  .stitch-btn-primary:active:not(:disabled) {
    transform: scale(0.98);
  }

  .stitch-btn-primary:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  /* ---- Responsive ---- */
  @media (max-width: 640px) {
    .stitch-settings-title {
      font-size: 1.5rem;
    }

    .stitch-form {
      padding: 20px;
    }

    .stitch-avatar-area {
      padding-inline-start: 20px;
    }

    .stitch-actions {
      flex-direction: column;
    }

    .stitch-btn-ghost,
    .stitch-btn-primary {
      width: 100%;
      justify-content: center;
    }
  }
</style>
