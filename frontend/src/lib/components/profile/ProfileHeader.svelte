<script lang="ts">
  import type { Identity, Relationship } from '$lib/api/types.js';
  import { relativeTime, fullDateTime } from '$lib/utils/time.js';
  import { api } from '$lib/api/client.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Dropdown from '$lib/components/ui/Dropdown.svelte';
  import Modal from '$lib/components/ui/Modal.svelte';
  import VerifiedBadge from '$lib/components/ui/VerifiedBadge.svelte';
  import RoleBadge from '$lib/components/ui/RoleBadge.svelte';
  import AccountTypeIndicator from '$lib/components/ui/AccountTypeIndicator.svelte';
  import ImageLightbox from '$lib/components/ui/ImageLightbox.svelte';
  import DisplayName from '$lib/components/DisplayName.svelte';
  import { renderCustomEmojis } from '$lib/utils/custom-emoji.js';
  import { filterBadges, type Badge } from '$lib/utils/badges.js';

  import type { Snippet } from 'svelte';

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
    staffActions,
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
    staffActions?: Snippet;
  } = $props();

  let joinDate = $derived(
    new Date(account.created_at).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'long',
    })
  );

  // Compact stat figures: 1234 -> "1.2K".
  const nf = new Intl.NumberFormat(undefined, { notation: 'compact', maximumFractionDigits: 1 });
  function compact(n: number | null | undefined): string {
    return nf.format(n ?? 0);
  }

  // Optional profile extras that the header previously ignored.
  let location = $derived((account as { location?: string | null }).location?.trim() || '');
  let fields = $derived(
    ((account as { profile_fields?: { name: string; value: string }[] }).profile_fields ?? [])
      .filter((f) => f.name?.trim() || f.value?.trim())
      .slice(0, 4),
  );
  function isUrl(v: string): boolean {
    return /^https?:\/\//i.test(v.trim());
  }
  function fieldHref(v: string): string {
    return isUrl(v) ? v.trim() : `https://${v.trim()}`;
  }
  function fieldDisplay(v: string): string {
    return v.replace(/^https?:\/\//i, '').replace(/\/$/, '');
  }

  // Deterministic accent hue derived from the account so the fallback
  // cover (no uploaded header) varies per profile instead of everyone
  // getting an identical flat panel — while still anchored to the brand
  // teal in the gradient below.
  let coverHue = $derived.by(() => {
    const src = account.id || account.handle || '';
    let h = 0;
    for (let i = 0; i < src.length; i++) h = (h * 31 + src.charCodeAt(i)) & 0xffff;
    return h % 360;
  });

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

  let badgeView = $derived(
    filterBadges(((account as { badges?: Badge[] }).badges) ?? [], !!account.is_verified),
  );

  // Lightbox for the banner + avatar. We only open it for real
  // uploaded images (skip the default placeholders) so a brand-new
  // account doesn't show the platform's default cover full-screen.
  let lightboxImages = $state<{ url: string; alt?: string | null }[]>([]);
  let lightboxIndex = $state(0);
  let lightboxOpen = $state(false);

  function openAvatar() {
    if (!account.avatar_url) return;
    lightboxImages = [{ url: account.avatar_url, alt: `${account.display_name || account.handle}'s avatar` }];
    lightboxIndex = 0;
    lightboxOpen = true;
  }

  function openBanner() {
    if (!account.header_url) return;
    lightboxImages = [{ url: account.header_url, alt: `${account.display_name || account.handle}'s header` }];
    lightboxIndex = 0;
    lightboxOpen = true;
  }
</script>

<div class="profile-header">
  <div class="profile-banner">
    {#if account.header_url}
      <button
        type="button"
        class="banner-button"
        onclick={openBanner}
        aria-label="View header image"
      >
        <img src={account.header_url} alt="" class="banner-img" />
      </button>
    {:else}
      <div class="banner-gradient" style="--cover-h: {coverHue}" aria-hidden="true"></div>
    {/if}
    <div class="banner-scrim" aria-hidden="true"></div>
  </div>

  <div class="profile-info-section">
    <div class="profile-avatar-row">
      {#if account.avatar_url}
        <button
          type="button"
          class="profile-avatar-wrapper avatar-button"
          onclick={openAvatar}
          aria-label="View profile picture"
        >
          <Avatar src={account.avatar_url} name={account.display_name || account.handle} size="2xl" />
        </button>
      {:else}
        <div class="profile-avatar-wrapper">
          <Avatar src={account.avatar_url} name={account.display_name || account.handle} size="2xl" />
        </div>
      {/if}

      <div class="profile-actions" data-requires-login>
        {#if staffActions}
          {@render staffActions()}
        {/if}
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
        <span class="profile-display-name-text">
          <DisplayName name={account.display_name} fallback={account.handle} emojis={account.emojis} />
        </span>
        <span class="profile-badges">
          {#if badgeView.showVerifiedMark}
            <VerifiedBadge size="md" />
          {/if}
          <AccountTypeIndicator account={account} size={16} />
          {#each badgeView.nonTier as badge (`${badge.type}:${badge.label ?? ''}`)}
            <RoleBadge type={badge.type} label={badge.label} size="md" />
          {/each}
          {#if badgeView.highestTier}
            <RoleBadge type={badgeView.highestTier.type} label={badgeView.highestTier.label} size="md" />
          {/if}
        </span>
      </h1>
      <span class="profile-handle">@{account.acct || account.handle}</span>
      {#if relationship?.followed_by && !isOwnProfile}
        <span class="follows-you-badge">Follows you</span>
      {/if}
      {#if account.domain && account.url}
        <a
          class="profile-remote-link"
          href={account.url}
          target="_blank"
          rel="noopener noreferrer nofollow"
          title={`View this profile on ${account.domain}`}
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/>
          </svg>
          View on {account.domain}
        </a>
      {/if}
    </div>

    {#if account.bio_html}
      <!-- bio_html is server-sanitized via HtmlSanitizeEx.basic_html
           (remote bios) or escaped + nl→<br> (local plaintext bios), then
           custom `:shortcode:` emojis are swapped in from the actor manifest. -->
      <div class="profile-bio">{@html renderCustomEmojis(account.bio_html, account.emojis)}</div>
    {:else if account.bio}
      <p class="profile-bio">{account.bio}</p>
    {/if}

    <div class="profile-meta">
      {#if location}
        <span class="profile-meta-item">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/>
          </svg>
          {location}
        </span>
      {/if}
      <span class="profile-meta-item">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
          <rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/>
        </svg>
        Joined {joinDate}
      </span>
    </div>

    {#if fields.length > 0}
      <dl class="profile-fields">
        {#each fields as field (field.name + field.value)}
          <div class="profile-field">
            <dt class="profile-field-name">{field.name}</dt>
            <dd class="profile-field-value">
              {#if isUrl(field.value) || /\.\w{2,}/.test(field.value)}
                <a href={fieldHref(field.value)} target="_blank" rel="noopener noreferrer ugc" class="profile-field-link">
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                    <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
                  </svg>
                  {fieldDisplay(field.value)}
                </a>
              {:else}
                {field.value}
              {/if}
            </dd>
          </div>
        {/each}
      </dl>
    {/if}

    <!-- Counts come back as `null` when the profile owner has opted
         out of showing them and the viewer isn't them. In that case
         we drop the whole stats block; the lists themselves remain
         linkable from the explicit /following and /followers URLs
         for people who already know them. -->
    {#if account.following_count !== null && account.followers_count !== null}
      <div class="profile-stats">
        {#if account.post_count != null}
          <div class="stat">
            <span class="stat-num">{compact(account.post_count)}</span>
            <span class="stat-label">Posts</span>
          </div>
        {/if}
        <a href="/@{account.handle}/following" class="stat stat-link">
          <span class="stat-num">{compact(account.following_count)}</span>
          <span class="stat-label">Following</span>
        </a>
        <a href="/@{account.handle}/followers" class="stat stat-link">
          <span class="stat-num">{compact(account.followers_count)}</span>
          <span class="stat-label">Followers</span>
        </a>
      </div>
    {/if}
  </div>
</div>

{#if lightboxOpen}
  <ImageLightbox
    images={lightboxImages}
    bind:index={lightboxIndex}
    onclose={() => (lightboxOpen = false)}
  />
{/if}

<Modal bind:open={showReportModal} title={`Report @${account.acct || account.handle}`} onclose={cancelReport}>
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
</Modal>

<style>
  .profile-header {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-2xl);
    box-shadow: var(--shadow-md);
    /* No overflow clipping on the card so the moderation popover can
       escape downward. The banner clips itself. */
  }

  .profile-banner {
    position: relative;
    height: 210px;
    overflow: hidden;
    border-top-left-radius: var(--radius-2xl);
    border-top-right-radius: var(--radius-2xl);
  }

  .banner-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  /* Per-profile mesh cover for accounts without an uploaded header.
     Anchored to the brand teal with a deterministic accent hue so
     every profile still feels on-brand but not identical. */
  .banner-gradient {
    width: 100%;
    height: 100%;
    background:
      radial-gradient(120% 140% at 18% 12%, hsl(var(--cover-h) 68% 55% / 0.85) 0%, transparent 45%),
      radial-gradient(120% 130% at 88% 8%, var(--color-primary-container) 0%, transparent 52%),
      linear-gradient(135deg, var(--color-primary) 0%, hsl(var(--cover-h) 52% 34%) 100%);
  }

  /* Soft bottom scrim so the card edge and avatar read against busy
     header photos. */
  .banner-scrim {
    position: absolute;
    inset: 0;
    pointer-events: none;
    background: linear-gradient(to bottom, transparent 55%, rgba(15, 23, 23, 0.28) 100%);
  }

  /* Buttonized banner / avatar — reset native button chrome so the
     image still fills the slot, only the cursor + focus ring change
     to signal it's now clickable. */
  .banner-button {
    display: block;
    width: 100%;
    height: 100%;
    padding: 0;
    margin: 0;
    border: 0;
    background: transparent;
    cursor: zoom-in;
  }

  .avatar-button {
    padding: 0;
    border: 0;
    background: transparent;
    cursor: zoom-in;
  }

  .banner-button:focus-visible,
  .avatar-button:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .profile-info-section {
    padding: 0 var(--space-6) var(--space-6);
  }

  .profile-avatar-row {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    /* Avatar wrapper is 104px + 8px ring = 112px. Pull it up by half its
       height so it straddles the banner seam ~50/50 (the conventional
       profile placement) instead of sinking low into the card. */
    margin-block-start: -56px;
  }

  /* Ring + drop shadow lift the avatar off the banner. The inner white
     border matches the card so the avatar reads as punched through. */
  .profile-avatar-wrapper {
    /* flex so the inline-flex Avatar isn't seated on the button's text
       baseline — that descender space showed up as a fat gap under the
       image (uneven ring). As a flex item the avatar fills the ring
       evenly on all sides. */
    display: flex;
    border: 4px solid var(--color-surface-raised);
    border-radius: var(--radius-full);
    background: var(--color-surface-raised);
    box-shadow: 0 6px 20px rgba(15, 23, 23, 0.18);
    transition: transform var(--transition-fast);
  }

  @media (prefers-reduced-motion: no-preference) {
    .avatar-button:hover {
      transform: scale(1.03);
    }
  }

  .profile-actions {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding-block-start: var(--space-12);
  }

  .action-icon-btn {
    width: 40px;
    height: 40px;
    padding: 0;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    transition: background var(--transition-fast), border-color var(--transition-fast);
  }

  .action-icon-btn:hover {
    background: var(--color-surface-container-low);
    border-color: var(--color-primary);
    color: var(--color-primary);
  }

  .profile-identity {
    margin-block-start: var(--space-4);
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  /* A profile shows the whole name, so a long one wraps rather than truncates. */
  .profile-display-name-text {
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .profile-display-name {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 8px;
    font-family: var(--font-headline, inherit);
    font-size: var(--text-2xl);
    font-weight: 800;
    letter-spacing: -0.01em;
    color: var(--color-text);
    line-height: 1.2;
  }

  /* Group badges into a flex track so the gap is consistent and they
     don't crowd the display name when wrapping. */
  .profile-badges {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    flex-shrink: 0;
  }

  .profile-handle {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .profile-remote-link {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    align-self: flex-start;
    margin-block-start: 2px;
    font-size: var(--text-sm);
    color: var(--color-primary);
    text-decoration: none;
  }

  .profile-remote-link:hover {
    text-decoration: underline;
  }

  .follows-you-badge {
    display: inline-block;
    align-self: flex-start;
    margin-block-start: var(--space-1);
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-primary);
    background: var(--color-secondary-container);
    padding: 3px var(--space-2);
    border-radius: var(--radius-full);
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

  /* Profile fields — verified links / custom key-value rows. */
  .profile-fields {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
    gap: var(--space-2);
    margin: var(--space-4) 0 0;
  }

  .profile-field {
    background: var(--color-surface-container-low);
    border-radius: var(--radius-lg);
    padding: var(--space-2) var(--space-3);
    min-width: 0;
  }

  .profile-field-name {
    font-size: 0.6875rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-tertiary);
  }

  .profile-field-value {
    margin: 2px 0 0;
    font-size: var(--text-sm);
    color: var(--color-text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .profile-field-link {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    max-width: 100%;
    color: var(--color-primary);
    font-weight: 600;
    text-decoration: none;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .profile-field-link:hover {
    text-decoration: underline;
  }

  .profile-field-link svg {
    flex-shrink: 0;
    opacity: 0.8;
  }

  /* Stats bar — bigger figures, hover pill, tabular numerals so the
     numbers don't jitter. */
  .profile-stats {
    display: flex;
    gap: var(--space-2);
    margin-block-start: var(--space-4);
  }

  .stat {
    display: flex;
    flex-direction: column;
    gap: 1px;
    padding: var(--space-1) var(--space-3);
    border-radius: var(--radius-lg);
    text-decoration: none;
    transition: background var(--transition-fast);
  }

  .stat-link:hover,
  .stat-link:focus-visible {
    background: var(--color-surface-container-low);
    text-decoration: none;
    outline: none;
  }

  .stat-num {
    font-size: var(--text-lg);
    font-weight: 800;
    color: var(--color-text);
    font-variant-numeric: tabular-nums;
    line-height: 1.1;
  }

  .stat-label {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  /* Report modal (rendered inside the shared Modal) */
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
      height: 150px;
    }

    .profile-info-section {
      padding: 0 var(--space-4) var(--space-4);
    }

    .profile-avatar-row {
      margin-block-start: -56px;
    }

    .profile-display-name {
      font-size: var(--text-xl);
    }

    .profile-fields {
      grid-template-columns: 1fr;
    }
  }
</style>
