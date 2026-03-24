<script lang="ts">
  import type { Identity, Relationship } from '$lib/api/types.js';
  import { relativeTime, fullDateTime } from '$lib/utils/time.js';
  import { api } from '$lib/api/client.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Dropdown from '$lib/components/ui/Dropdown.svelte';
  import VerifiedBadge from '$lib/components/ui/VerifiedBadge.svelte';
  import RoleBadge from '$lib/components/ui/RoleBadge.svelte';

  let {
    account,
    relationship = null,
    isOwnProfile = false,
    onfollow,
    onunfollow,
    onblock,
    onmute,
    onmessage,
    onedit,
  }: {
    account: Identity;
    relationship?: Relationship | null;
    isOwnProfile?: boolean;
    onfollow?: () => void;
    onunfollow?: () => void;
    onblock?: () => void;
    onmute?: () => void;
    onmessage?: () => void;
    onedit?: () => void;
  } = $props();

  let joinDate = $derived(
    new Date(account.created_at).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'long',
    })
  );

  let isFollowing = $derived(relationship?.following ?? false);
  let isRequested = $derived(relationship?.requested ?? false);
  let isBlocking = $derived(relationship?.blocking ?? false);
  let isMuting = $derived(relationship?.muting ?? false);

  let followLabel = $derived(
    isRequested ? 'Requested' : isFollowing ? 'Following' : 'Follow'
  );

  // Report modal state
  let showReportModal = $state(false);
  let reportCategory = $state('spam');
  let reportDescription = $state('');
  let reportSubmitting = $state(false);
  let reportError = $state('');

  const reportCategories = [
    { value: 'spam', label: 'Spam' },
    { value: 'harassment', label: 'Harassment' },
    { value: 'hate_speech', label: 'Hate speech' },
    { value: 'illegal', label: 'Illegal content' },
    { value: 'misinformation', label: 'Misinformation' },
    { value: 'other', label: 'Other' },
  ];

  function openReportModal() {
    reportCategory = 'spam';
    reportDescription = '';
    reportError = '';
    showReportModal = true;
  }

  async function submitReport() {
    reportSubmitting = true;
    reportError = '';
    try {
      await api.post('/api/v1/reports', {
        reported_id: account.id,
        target_type: 'account',
        target_id: account.id,
        category: reportCategory,
        description: reportDescription,
      });
      showReportModal = false;
    } catch {
      reportError = 'Failed to submit report. Please try again.';
    } finally {
      reportSubmitting = false;
    }
  }

  function cancelReport() {
    showReportModal = false;
  }
</script>

<div class="profile-header">
  <div class="profile-banner">
    {#if account.header_url}
      <img src={account.header_url} alt="" class="banner-img" />
    {:else}
      <div class="banner-gradient" aria-hidden="true"></div>
    {/if}
  </div>

  <div class="profile-info-section">
    <div class="profile-avatar-row">
      <div class="profile-avatar-wrapper">
        <Avatar src={account.avatar_url} name={account.display_name || account.handle} size="xl" />
      </div>

      <div class="profile-actions">
        {#if isOwnProfile}
          <button class="btn btn-outline" type="button" onclick={onedit}>
            Edit profile
          </button>
        {:else}
          <button class="btn btn-ghost action-icon-btn" type="button" onclick={onmessage} aria-label="Message">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
            </svg>
          </button>

          <button
            class="btn {isFollowing || isRequested ? 'btn-outline' : 'btn-primary'}"
            type="button"
            onclick={isFollowing ? onunfollow : onfollow}
            disabled={isBlocking}
          >
            {followLabel}
          </button>

          <Dropdown align="end">
            {#snippet trigger()}
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <circle cx="12" cy="5" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="12" cy="19" r="1"/>
              </svg>
            {/snippet}
            <button type="button" onclick={onmute} role="menuitem">
              {isMuting ? 'Unmute' : 'Mute'}
            </button>
            <button type="button" class="dropdown-item-danger" onclick={onblock} role="menuitem">
              {isBlocking ? 'Unblock' : 'Block'}
            </button>
            <div class="dropdown-divider"></div>
            <button type="button" class="dropdown-item-danger" onclick={openReportModal} role="menuitem">
              Report
            </button>
          </Dropdown>
        {/if}
      </div>
    </div>

    <div class="profile-identity">
      <h1 class="profile-display-name">
        {account.display_name || account.handle}
        {#if (account as any).verified}
          <VerifiedBadge size="md" />
        {/if}
        {#if (account as any).badges}
          {#each (account as any).badges as badge (badge.type)}
            <RoleBadge type={badge.type} label={badge.label} size="md" />
          {/each}
        {/if}
      </h1>
      <span class="profile-handle">@{account.handle}</span>
      {#if relationship?.followed_by && !isOwnProfile}
        <span class="follows-you-badge">Follows you</span>
      {/if}
    </div>

    {#if account.bio}
      <p class="profile-bio">{account.bio}</p>
    {/if}

    <div class="profile-meta">
      <span class="profile-meta-item">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/>
        </svg>
        Joined {joinDate}
      </span>
    </div>

    <div class="profile-stats">
      <a href="/@{account.handle}/following" class="stat-link">
        <strong>{account.following_count}</strong>
        <span class="stat-label">Following</span>
      </a>
      <a href="/@{account.handle}/followers" class="stat-link">
        <strong>{account.followers_count}</strong>
        <span class="stat-label">Followers</span>
      </a>
    </div>
  </div>
</div>

{#if showReportModal}
  <div class="report-overlay" onclick={cancelReport} role="dialog" aria-modal="true" aria-label="Report user">
    <div class="report-dialog" onclick={(e) => e.stopPropagation()}>
      <h3 class="report-title">Report @{account.handle}</h3>
      <p class="report-subtitle">Why are you reporting this account?</p>

      <div class="report-form">
        <label class="report-label" for="profile-report-category">Category</label>
        <select id="profile-report-category" class="report-select" bind:value={reportCategory}>
          {#each reportCategories as cat (cat.value)}
            <option value={cat.value}>{cat.label}</option>
          {/each}
        </select>

        <label class="report-label" for="profile-report-description">Description (optional)</label>
        <textarea
          id="profile-report-description"
          class="report-textarea"
          bind:value={reportDescription}
          placeholder="Provide additional details..."
          rows="3"
        ></textarea>

        {#if reportError}
          <p class="report-error">{reportError}</p>
        {/if}
      </div>

      <div class="report-actions">
        <button type="button" class="report-cancel" onclick={cancelReport}>Cancel</button>
        <button type="button" class="report-submit" onclick={submitReport} disabled={reportSubmitting}>
          {reportSubmitting ? 'Submitting...' : 'Submit report'}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .profile-header {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow: hidden;
  }

  .profile-banner {
    height: 180px;
    overflow: hidden;
  }

  .banner-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .banner-gradient {
    width: 100%;
    height: 100%;
    background: linear-gradient(
      var(--gradient-direction),
      var(--gradient-start),
      var(--gradient-end)
    );
  }

  .profile-info-section {
    padding: 0 var(--space-6) var(--space-6);
  }

  .profile-avatar-row {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    margin-block-start: -40px;
  }

  .profile-avatar-wrapper {
    border: 4px solid var(--color-surface-raised);
    border-radius: var(--radius-full);
    background: var(--color-surface-raised);
  }

  .profile-actions {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding-block-start: var(--space-10);
  }

  .action-icon-btn {
    width: 36px;
    height: 36px;
    padding: 0;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full);
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  .profile-identity {
    margin-block-start: var(--space-3);
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .profile-display-name {
    font-size: var(--text-xl);
    font-weight: 700;
    color: var(--color-text);
    line-height: 1.3;
  }

  .profile-handle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .follows-you-badge {
    display: inline-block;
    align-self: flex-start;
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    background: var(--color-surface);
    padding: 2px var(--space-2);
    border-radius: var(--radius-sm);
  }

  .profile-bio {
    margin-block-start: var(--space-3);
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: var(--line-height);
    white-space: pre-wrap;
    word-break: break-word;
  }

  .profile-meta {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-4);
    margin-block-start: var(--space-3);
  }

  .profile-meta-item {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .profile-stats {
    display: flex;
    gap: var(--space-5);
    margin-block-start: var(--space-3);
  }

  .stat-link {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    font-size: var(--text-sm);
    color: var(--color-text);
    text-decoration: none;
  }

  .stat-link:hover {
    text-decoration: underline;
  }

  .stat-link strong {
    font-weight: 700;
  }

  .stat-label {
    color: var(--color-text-secondary);
  }

  /* Report modal */
  .report-overlay {
    position: fixed;
    inset: 0;
    background: var(--color-overlay, rgba(0,0,0,0.5));
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: var(--z-modal, 40);
  }

  .report-dialog {
    background: var(--color-surface-raised, #fff);
    border-radius: var(--radius-lg, 0.75rem);
    padding: var(--space-6, 1.5rem);
    max-width: 400px;
    width: 90%;
    box-shadow: var(--shadow-xl, 0 10px 15px rgba(0,0,0,0.1));
  }

  .report-title {
    font-size: var(--text-lg, 1.125rem);
    font-weight: 600;
    margin-block-end: var(--space-1, 0.25rem);
  }

  .report-subtitle {
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text-secondary, #64748b);
    margin-block-end: var(--space-4, 1rem);
  }

  .report-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-2, 0.5rem);
    margin-block-end: var(--space-4, 1rem);
  }

  .report-label {
    font-size: var(--text-sm, 0.875rem);
    font-weight: 500;
    color: var(--color-text, #0f172a);
  }

  .report-select {
    padding: var(--space-2, 0.5rem);
    border: 1px solid var(--color-border, #e2e8f0);
    border-radius: var(--radius-md, 0.5rem);
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text, #0f172a);
    background: var(--color-bg, #fff);
  }

  .report-textarea {
    padding: var(--space-2, 0.5rem);
    border: 1px solid var(--color-border, #e2e8f0);
    border-radius: var(--radius-md, 0.5rem);
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-text, #0f172a);
    background: var(--color-bg, #fff);
    resize: vertical;
    font-family: inherit;
  }

  .report-error {
    font-size: var(--text-sm, 0.875rem);
    color: var(--color-danger, #ef4444);
  }

  .report-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-3, 0.75rem);
  }

  .report-cancel {
    padding: var(--space-2, 0.5rem) var(--space-4, 1rem);
    border: 1px solid var(--color-border, #e2e8f0);
    border-radius: var(--radius-md, 0.5rem);
    background: transparent;
    color: var(--color-text, #0f172a);
    font-size: var(--text-sm, 0.875rem);
    cursor: pointer;
  }

  .report-submit {
    padding: var(--space-2, 0.5rem) var(--space-4, 1rem);
    border: none;
    border-radius: var(--radius-md, 0.5rem);
    background: var(--color-danger, #ef4444);
    color: white;
    font-size: var(--text-sm, 0.875rem);
    font-weight: 600;
    cursor: pointer;
  }

  .report-submit:hover {
    opacity: 0.9;
  }

  .report-submit:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  @media (max-width: 480px) {
    .profile-banner {
      height: 120px;
    }

    .profile-info-section {
      padding: 0 var(--space-4) var(--space-4);
    }
  }
</style>
