<script lang="ts">
  import { api } from '$lib/api/client.js';
  import { authStore, setUser } from '$lib/stores/auth.js';
  import { get } from 'svelte/store';
  import type { Identity } from '$lib/api/types.js';
  import Avatar from './Avatar.svelte';

  let {
    onclose,
  }: {
    onclose: () => void;
  } = $props();

  let step = $state(1);
  const totalSteps = 3;

  // Step 1: Avatar & display name
  let displayName = $state(get(authStore).user?.display_name || '');
  let bio = $state('');
  let avatarFile: File | null = $state(null);
  let avatarPreview = $state(get(authStore).user?.avatar_url || '');

  // Step 2: Suggestions
  let suggestions = $state<Identity[]>([]);
  let followedIds = $state<Set<string>>(new Set());
  let suggestionsLoading = $state(false);

  function handleAvatarChange(e: Event) {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (file) {
      avatarFile = file;
      avatarPreview = URL.createObjectURL(file);
    }
  }

  async function saveProfile() {
    try {
      const body: Record<string, string> = {};
      if (displayName) body.display_name = displayName;
      if (bio) body.bio = bio;

      const updated = await api.patch<Identity>('/api/v1/accounts/update_credentials', body);
      setUser(updated);
    } catch { /* */ }
  }

  async function loadSuggestions() {
    suggestionsLoading = true;
    try {
      suggestions = await api.get<Identity[]>('/api/v1/accounts/suggestions');
    } catch { suggestions = []; }
    finally { suggestionsLoading = false; }
  }

  async function toggleFollow(id: string) {
    try {
      if (followedIds.has(id)) {
        await api.post(`/api/v1/accounts/${id}/unfollow`);
        followedIds.delete(id);
        followedIds = new Set(followedIds);
      } else {
        await api.post(`/api/v1/accounts/${id}/follow`);
        followedIds.add(id);
        followedIds = new Set(followedIds);
      }
    } catch { /* */ }
  }

  async function next() {
    if (step === 1) {
      await saveProfile();
      await loadSuggestions();
      step = 2;
    } else if (step === 2) {
      step = 3;
    } else {
      // Mark onboarding complete
      try {
        await api.post('/api/v1/accounts/update_credentials', { onboarded: true });
      } catch { /* */ }
      onclose();
    }
  }

  function skip() {
    if (step < totalSteps) {
      step++;
      if (step === 2) loadSuggestions();
    } else {
      onclose();
    }
  }
</script>

<div class="onboarding-overlay" role="dialog" aria-modal="true">
  <div class="onboarding-modal">
    <!-- Progress -->
    <div class="onboarding-progress">
      {#each Array(totalSteps) as _, i}
        <div class="progress-dot" class:active={i + 1 <= step}></div>
      {/each}
    </div>

    {#if step === 1}
      <!-- Step 1: Profile setup -->
      <div class="onboarding-step">
        <h2 class="step-title">Set up your profile</h2>
        <p class="step-desc">Let people know who you are</p>

        <div class="avatar-upload" onclick={() => document.getElementById('onboard-avatar')?.click()}>
          {#if avatarPreview}
            <img src={avatarPreview} alt="" class="avatar-preview" />
          {:else}
            <div class="avatar-placeholder-big">
              <span class="material-symbols-outlined" style="font-size: 32px">add_a_photo</span>
            </div>
          {/if}
          <input type="file" id="onboard-avatar" accept="image/*" class="visually-hidden" onchange={handleAvatarChange} />
        </div>

        <div class="field">
          <label class="field-label" for="ob-name">Display name</label>
          <input id="ob-name" type="text" class="field-input" bind:value={displayName} placeholder="Your name" />
        </div>

        <div class="field">
          <label class="field-label" for="ob-bio">Bio</label>
          <textarea id="ob-bio" class="field-input field-textarea" bind:value={bio} placeholder="Tell us about yourself..." rows={3}></textarea>
        </div>
      </div>

    {:else if step === 2}
      <!-- Step 2: Follow suggestions -->
      <div class="onboarding-step">
        <h2 class="step-title">Find people to follow</h2>
        <p class="step-desc">Your feed is built from the people you follow</p>

        {#if suggestionsLoading}
          <div class="suggestions-loading">Loading suggestions...</div>
        {:else if suggestions.length === 0}
          <div class="suggestions-loading">No suggestions yet — you can find people in Explore</div>
        {:else}
          <div class="suggestions-list">
            {#each suggestions as user (user.id)}
              <div class="suggestion-row">
                <Avatar src={user.avatar_url} name={user.display_name || user.handle} size="md" />
                <div class="suggestion-info">
                  <span class="suggestion-name">{user.display_name || user.handle}</span>
                  <span class="suggestion-handle">@{user.acct || user.handle}</span>
                </div>
                <button
                  type="button"
                  class="follow-btn"
                  class:following={followedIds.has(user.id)}
                  onclick={() => toggleFollow(user.id)}
                >
                  {followedIds.has(user.id) ? 'Following' : 'Follow'}
                </button>
              </div>
            {/each}
          </div>
        {/if}
      </div>

    {:else}
      <!-- Step 3: Done -->
      <div class="onboarding-step done-step">
        <div class="done-icon">
          <span class="material-symbols-outlined" style="font-size: 48px; color: var(--color-success)">check_circle</span>
        </div>
        <h2 class="step-title">You're all set!</h2>
        <p class="step-desc">Start posting, explore trending topics, and connect with people.</p>
      </div>
    {/if}

    <div class="onboarding-actions">
      <button type="button" class="skip-btn" onclick={skip}>
        {step === totalSteps ? 'Close' : 'Skip'}
      </button>
      <button type="button" class="next-btn" onclick={next}>
        {step === totalSteps ? 'Get started' : 'Continue'}
      </button>
    </div>
  </div>
</div>

<style>
  .onboarding-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 10000;
    animation: fade-in 0.2s ease;
  }

  @keyframes fade-in { from { opacity: 0; } to { opacity: 1; } }

  .onboarding-modal {
    background: var(--color-surface-container-lowest);
    border-radius: 20px;
    width: 90%;
    max-width: 440px;
    padding: 32px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.2);
    animation: modal-in 0.25s cubic-bezier(0.22, 1, 0.36, 1);
  }

  @keyframes modal-in {
    from { opacity: 0; transform: scale(0.95) translateY(10px); }
    to { opacity: 1; transform: scale(1) translateY(0); }
  }

  .onboarding-progress {
    display: flex;
    justify-content: center;
    gap: 8px;
    margin-bottom: 24px;
  }

  .progress-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--color-border);
    transition: background 200ms ease, transform 200ms ease;
  }

  .progress-dot.active {
    background: var(--color-primary);
    transform: scale(1.2);
  }

  .step-title {
    font-size: 1.25rem;
    font-weight: 700;
    text-align: center;
    margin-bottom: 4px;
  }

  .step-desc {
    font-size: 0.875rem;
    color: var(--color-text-secondary);
    text-align: center;
    margin-bottom: 24px;
  }

  .avatar-upload {
    width: 80px;
    height: 80px;
    border-radius: 50%;
    margin: 0 auto 20px;
    cursor: pointer;
    overflow: hidden;
    border: 2px dashed var(--color-border);
    transition: border-color 150ms ease;
  }

  .avatar-upload:hover { border-color: var(--color-primary); }

  .avatar-preview {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .avatar-placeholder-big {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--color-text-tertiary);
  }

  .field { margin-bottom: 16px; }
  .field-label {
    display: block;
    font-size: 0.75rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--color-text-secondary);
    margin-bottom: 6px;
  }
  .field-input {
    width: 100%;
    padding: 10px 14px;
    border: 1px solid var(--color-border);
    border-radius: 10px;
    font-size: 0.875rem;
    color: var(--color-text);
    background: var(--color-surface);
  }
  .field-input:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 2px var(--color-primary-soft, rgba(0, 128, 128, 0.1));
  }
  .field-textarea { resize: vertical; font-family: inherit; }

  .visually-hidden {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
  }

  .suggestions-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
    max-height: 300px;
    overflow-y: auto;
  }

  .suggestion-row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px;
    border-radius: 10px;
    transition: background 150ms ease;
  }

  .suggestion-row:hover { background: var(--color-surface); }

  .suggestion-info { flex: 1; min-width: 0; }
  .suggestion-name { display: block; font-size: 0.875rem; font-weight: 600; }
  .suggestion-handle { display: block; font-size: 0.75rem; color: var(--color-text-secondary); }

  .follow-btn {
    padding: 6px 16px;
    border: 2px solid var(--color-primary);
    border-radius: 9999px;
    background: transparent;
    color: var(--color-primary);
    font-size: 0.8125rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 150ms ease;
    flex-shrink: 0;
  }

  .follow-btn:hover { background: var(--color-primary); color: white; }
  .follow-btn.following { background: var(--color-primary); color: white; }
  .follow-btn.following:hover { background: transparent; color: var(--color-primary); }

  .suggestions-loading {
    text-align: center;
    padding: 24px;
    color: var(--color-text-tertiary);
    font-size: 0.875rem;
  }

  .done-step { padding: 20px 0; }
  .done-icon { text-align: center; margin-bottom: 12px; }

  .onboarding-actions {
    display: flex;
    justify-content: space-between;
    margin-top: 24px;
  }

  .skip-btn {
    padding: 10px 20px;
    background: none;
    border: none;
    color: var(--color-text-secondary);
    font-size: 0.875rem;
    font-weight: 500;
    cursor: pointer;
  }

  .skip-btn:hover { color: var(--color-text); }

  .next-btn {
    padding: 10px 28px;
    background: var(--color-primary);
    color: white;
    border: none;
    border-radius: 9999px;
    font-size: 0.875rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 150ms ease;
  }

  .next-btn:hover { opacity: 0.9; }
</style>
