<script lang="ts">
  import { instanceName } from '$lib/stores/instance.js';
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import type { Identity } from '$lib/api/types.js';
  import type { GroupDetail, GroupApplication, GroupMember } from '$lib/api/groups.js';
  import {
    getGroup,
    getGroupScreening,
    updateGroupScreening,
    updateGroup,
    getGroupApplications,
    approveApplication,
    rejectApplication,
    getGroupMembers,
    updateMemberRole,
    banMember,
    inviteToGroup
  } from '$lib/api/groups.js';
  import { search } from '$lib/api/search.js';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import { addToast } from '$lib/stores/toast.js';

  let group = $state<GroupDetail | null>(null);
  let loading = $state(true);
  let saving = $state(false);
  let activeTab = $state('general');

  // General settings
  let name = $state('');
  let description = $state('');
  let visibility = $state<'public' | 'private' | 'secret'>('public');
  let joinPolicy = $state<'open' | 'approval' | 'invite'>('open');

  // Screening
  let screeningQuestions = $state<string[]>([]);
  let minAccountAgeDays = $state(0);
  let requireProfileImage = $state(false);

  // Applications
  let applications = $state<GroupApplication[]>([]);
  let applicationsLoading = $state(false);
  let applicationsLoaded = $state(false);

  // Members
  let members = $state<GroupMember[]>([]);
  let membersLoading = $state(false);
  let membersLoaded = $state(false);

  // Invite
  let inviteQuery = $state('');
  let inviteResults = $state<Identity[]>([]);
  let inviteSearching = $state(false);
  let inviting = $state(false);
  let inviteTimeout: ReturnType<typeof setTimeout> | undefined;

  let groupId = $derived(page.params.id!);

  // Role tiers — match the backend's @moderate_roles / @manage_roles
  // ladder. Moderators get the moderate-tier tabs (applications,
  // members for ban/unban) but not General, Screening, or role
  // changes. Admins/owners get everything.
  const MANAGE_ROLES = ['admin', 'owner'];
  const MODERATE_ROLES = ['moderator', 'admin', 'owner'];

  let canManage = $derived(MANAGE_ROLES.includes(group?.role ?? ''));
  let canModerate = $derived(MODERATE_ROLES.includes(group?.role ?? ''));

  // Tabs are filtered by the role tier the user holds — moderators
  // open the page straight on the Applications tab since General /
  // Screening are hidden from them. Tabs render via the filtered
  // list; the on-page state checks below also gate the per-tab
  // bodies in case the user types a tab id into the URL.
  let tabs = $derived(
    [
      canManage ? { id: 'general', label: 'General' } : null,
      canManage ? { id: 'screening', label: 'Screening' } : null,
      canModerate ? { id: 'applications', label: 'Applications' } : null,
      canModerate ? { id: 'members', label: 'Members' } : null,
      canManage ? { id: 'invite', label: 'Invite' } : null
    ].filter((t) => t !== null) as { id: string; label: string }[]
  );

  onMount(async () => {
    try {
      const g = await getGroup(groupId);
      group = g;
      name = g.name;
      description = g.description ?? '';
      visibility = g.visibility;
      joinPolicy = g.join_policy;

      // Redirect if the viewer has no moderation privileges at all.
      // Members and non-members go back to the group profile;
      // moderators land on the Applications tab (the first tab they
      // can see).
      if (!MODERATE_ROLES.includes(g.role ?? '')) {
        goto(`/groups/${groupId}`);
        return;
      }

      // Prefill the Screening tab from the group's saved config so managers
      // edit the real questions/rules instead of a blank form (which, on save,
      // used to overwrite them with defaults).
      if (MANAGE_ROLES.includes(g.role ?? '')) {
        try {
          const s = await getGroupScreening(groupId);
          screeningQuestions = (s.questions ?? []).map((q) => q.text);
          minAccountAgeDays = s.min_account_age_days ?? 0;
          requireProfileImage = s.require_profile_image ?? false;
        } catch {
          // Non-fatal — leave the screening form at its defaults.
        }
      }

      if (!canManage && activeTab === 'general') {
        activeTab = 'applications';
      }
    } catch {
      goto(`/groups/${groupId}`);
    } finally {
      loading = false;
    }
  });

  $effect(() => {
    if (activeTab === 'applications' && !applicationsLoaded) {
      loadApplications();
    }
    if (activeTab === 'members' && !membersLoaded) {
      loadMembers();
    }
  });

  async function loadApplications() {
    applicationsLoading = true;
    try {
      const result = await getGroupApplications(groupId);
      applications = result.data;
      applicationsLoaded = true;
    } catch {
      // Error loading
    } finally {
      applicationsLoading = false;
    }
  }

  async function loadMembers() {
    membersLoading = true;
    try {
      const result = await getGroupMembers(groupId);
      members = result.data;
      membersLoaded = true;
    } catch {
      // Error loading
    } finally {
      membersLoading = false;
    }
  }

  async function saveGeneral() {
    saving = true;
    try {
      const updated = await updateGroup(groupId, {
        name,
        description: description || undefined,
        visibility,
        join_policy: joinPolicy
      });
      group = updated;
    } catch {
      // Error saving
    } finally {
      saving = false;
    }
  }

  async function saveScreening() {
    saving = true;
    try {
      // Screening has its own endpoint; the generic group update silently
      // drops it, which is why saving here used to be a no-op.
      const saved = await updateGroupScreening(groupId, {
        questions: screeningQuestions.filter((q) => q.trim()).map((text) => ({ text })),
        min_account_age_days: minAccountAgeDays,
        require_profile_image: requireProfileImage
      });
      // Reflect the persisted, filtered result back into the form.
      screeningQuestions = (saved.questions ?? []).map((q) => q.text);
      minAccountAgeDays = saved.min_account_age_days ?? 0;
      requireProfileImage = saved.require_profile_image ?? false;
      addToast('Screening settings saved', 'success');
    } catch {
      addToast('Could not save screening settings', 'error');
    } finally {
      saving = false;
    }
  }

  function addQuestion() {
    screeningQuestions = [...screeningQuestions, ''];
  }

  function removeQuestion(index: number) {
    screeningQuestions = screeningQuestions.filter((_, i) => i !== index);
  }

  async function handleApprove(applicationId: string) {
    try {
      await approveApplication(groupId, applicationId);
      applications = applications.filter((a) => a.id !== applicationId);
    } catch {
      // Error
    }
  }

  async function handleReject(applicationId: string) {
    try {
      await rejectApplication(groupId, applicationId);
      applications = applications.filter((a) => a.id !== applicationId);
    } catch {
      // Error
    }
  }

  async function handleRoleChange(memberId: string, role: string) {
    try {
      await updateMemberRole(groupId, memberId, role);
      members = members.map((m) =>
        m.id === memberId ? { ...m, role: role as GroupMember['role'] } : m
      );
    } catch {
      // Error
    }
  }

  async function handleBan(memberId: string) {
    if (!confirm('Are you sure you want to ban this member?')) return;
    try {
      await banMember(groupId, memberId);
      members = members.filter((m) => m.id !== memberId);
    } catch {
      // Error
    }
  }

  function handleInviteSearch() {
    if (inviteTimeout) clearTimeout(inviteTimeout);
    const q = inviteQuery.trim();
    if (q.length < 2) {
      inviteResults = [];
      return;
    }
    inviteSearching = true;
    inviteTimeout = setTimeout(async () => {
      try {
        const res = await search(q, { type: 'accounts', limit: 10 });
        inviteResults = res.accounts;
      } catch {
        inviteResults = [];
      } finally {
        inviteSearching = false;
      }
    }, 300);
  }

  async function handleInvite(accountId: string) {
    inviting = true;
    try {
      await inviteToGroup(groupId, accountId);
      // Drop the invitee from the result list immediately so a quick
      // double-click can't re-fire the request and 422 on duplicate.
      inviteResults = inviteResults.filter((a) => a.id !== accountId);
      addToast('Invite sent', 'success');
    } catch (err: unknown) {
      const apiErr = err as { body?: { error?: string }; message?: string };
      const msg =
        apiErr?.body?.error === 'invite.disabled_by_recipient'
          ? "This user doesn't accept invites"
          : apiErr?.body?.error === 'invite.recipient_follows_only'
            ? 'Only people they follow can invite them'
            : apiErr?.message || 'Could not send invite';
      addToast(msg, 'error');
    } finally {
      inviting = false;
    }
  }

  function goBack() {
    goto(`/groups/${groupId}`);
  }
</script>

<svelte:head>
  <title>Group Settings - {$instanceName}</title>
</svelte:head>

<div class="settings-page">
  {#if loading}
    <div class="page-loading">
      <Spinner />
    </div>
  {:else}
    <div class="page-header">
      <button type="button" class="back-btn" onclick={goBack} aria-label="Back to group">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <polyline points="15 18 9 12 15 6" />
        </svg>
      </button>
      <h1 class="page-title">Group Settings</h1>
    </div>

    <Tabs {tabs} bind:active={activeTab}>
      {#if activeTab === 'general'}
        <form class="settings-form" onsubmit={(e) => { e.preventDefault(); saveGeneral(); }}>
          <div class="form-group">
            <label for="group-name" class="form-label">Name</label>
            <input id="group-name" type="text" class="input" bind:value={name} required />
          </div>

          <div class="form-group">
            <label for="group-desc" class="form-label">Description</label>
            <textarea id="group-desc" class="textarea" bind:value={description} rows="4"></textarea>
          </div>

          <div class="form-group">
            <label for="group-visibility" class="form-label">Visibility</label>
            <select id="group-visibility" class="input" bind:value={visibility}>
              <option value="public">Public</option>
              <option value="private">Private</option>
              <option value="secret">Secret</option>
            </select>
          </div>

          <div class="form-group">
            <label for="group-policy" class="form-label">Join Policy</label>
            <select id="group-policy" class="input" bind:value={joinPolicy}>
              <option value="open">Open</option>
              <option value="approval">Requires Approval</option>
              <option value="invite">Invite Only</option>
            </select>
          </div>

          <button type="submit" class="btn btn-primary" disabled={saving}>
            {saving ? 'Saving...' : 'Save Changes'}
          </button>
        </form>

      {:else if activeTab === 'screening'}
        <form class="settings-form" onsubmit={(e) => { e.preventDefault(); saveScreening(); }}>
          <div class="form-group">
            <label class="form-label">Screening Questions</label>
            {#each screeningQuestions as question, i}
              <div class="question-row">
                <input
                  type="text"
                  class="input"
                  placeholder="Enter a question..."
                  bind:value={screeningQuestions[i]}
                />
                <button type="button" class="btn btn-ghost btn-sm" onclick={() => removeQuestion(i)} aria-label="Remove question">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
                  </svg>
                </button>
              </div>
            {/each}
            <button type="button" class="btn btn-outline btn-sm" onclick={addQuestion}>
              Add Question
            </button>
          </div>

          <div class="form-group">
            <label for="min-age" class="form-label">Minimum Account Age (days)</label>
            <input id="min-age" type="number" class="input" bind:value={minAccountAgeDays} min="0" />
          </div>

          <div class="form-group form-check">
            <label class="check-label">
              <input type="checkbox" bind:checked={requireProfileImage} />
              <span>Require profile image</span>
            </label>
          </div>

          <button type="submit" class="btn btn-primary" disabled={saving}>
            {saving ? 'Saving...' : 'Save Screening'}
          </button>
        </form>

      {:else if activeTab === 'applications'}
        {#if applicationsLoading}
          <div class="tab-loading"><Spinner /></div>
        {:else if applications.length === 0}
          <div class="tab-empty"><p class="empty-text">No pending applications</p></div>
        {:else}
          <ul class="application-list">
            {#each applications as app (app.id)}
              <li class="application-item">
                <div class="applicant-info">
                  <Avatar src={app.account.avatar_url} name={app.account.display_name || app.account.handle} size="md" />
                  <div class="applicant-details">
                    <span class="applicant-name">{app.account.display_name || app.account.handle}</span>
                    <span class="applicant-handle">@{app.account.handle}</span>
                    <time class="applicant-date">{new Date(app.created_at).toLocaleDateString()}</time>
                  </div>
                </div>
                {#if app.answers.length > 0}
                  <div class="applicant-answers">
                    {#each app.answers as qa}
                      <div class="qa-item">
                        <p class="qa-question">{qa.question}</p>
                        <p class="qa-answer">{qa.answer}</p>
                      </div>
                    {/each}
                  </div>
                {/if}
                <div class="application-actions">
                  <button type="button" class="btn btn-primary btn-sm" onclick={() => handleApprove(app.id)}>Approve</button>
                  <button type="button" class="btn btn-outline btn-sm" onclick={() => handleReject(app.id)}>Reject</button>
                </div>
              </li>
            {/each}
          </ul>
        {/if}

      {:else if activeTab === 'members'}
        {#if membersLoading}
          <div class="tab-loading"><Spinner /></div>
        {:else}
          <ul class="member-mgmt-list">
            {#each members as member (member.account.id)}
              <li class="member-mgmt-item">
                <div class="member-row">
                  <Avatar src={member.account.avatar_url} name={member.account.display_name || member.account.handle} size="sm" />
                  <div class="member-details">
                    <span class="member-name-text">{member.account.display_name || member.account.handle}</span>
                    <span class="member-handle-text">@{member.account.handle}</span>
                  </div>
                </div>
                {#if member.role !== 'owner'}
                  <div class="member-actions">
                    {#if canManage}
                      <select
                        class="input role-select"
                        value={member.role}
                        onchange={(e) => handleRoleChange(member.id, (e.target as HTMLSelectElement).value)}
                      >
                        <option value="member">Member</option>
                        <option value="moderator">Moderator</option>
                        <option value="admin">Admin</option>
                      </select>
                    {:else}
                      <!-- Mods see the role label but can't change it.
                           Promotions and demotions stay an admin-tier
                           action (lifting moderators above their own
                           rank would let them silently elevate). -->
                      <span class="role-badge">{member.role}</span>
                    {/if}
                    <button type="button" class="btn btn-danger btn-sm" onclick={() => handleBan(member.id)}>
                      Ban
                    </button>
                  </div>
                {/if}
              </li>
            {/each}
          </ul>
        {/if}

      {:else if activeTab === 'invite'}
        <div class="invite-section">
          <input
            type="text"
            class="input"
            placeholder="Search users to invite..."
            bind:value={inviteQuery}
            oninput={handleInviteSearch}
          />

          {#if inviteSearching}
            <div class="tab-loading"><Spinner size={20} /></div>
          {:else if inviteResults.length > 0}
            <ul class="invite-results">
              {#each inviteResults as account (account.id)}
                <li class="invite-item">
                  <div class="invite-user">
                    <Avatar src={account.avatar_url} name={account.display_name || account.handle} size="sm" />
                    <div class="invite-user-info">
                      <span class="invite-user-name">{account.display_name || account.handle}</span>
                      <span class="invite-user-handle">@{account.handle}</span>
                    </div>
                  </div>
                  <button type="button" class="btn btn-primary btn-sm" onclick={() => handleInvite(account.id)} disabled={inviting}>
                    Invite
                  </button>
                </li>
              {/each}
            </ul>
          {:else if inviteQuery.trim().length >= 2}
            <p class="empty-text" style="text-align: center; padding: var(--space-4);">No users found</p>
          {/if}
        </div>
      {/if}
    </Tabs>
  {/if}
</div>

<style>
  .settings-page {
    max-width: var(--feed-max-width);
    margin: 0 auto;
    width: 100%;
  }

  .page-loading {
    display: flex;
    justify-content: center;
    padding: var(--space-16);
  }

  .page-header {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding-block-end: var(--space-4);
    border-block-end: 1px solid var(--color-border);
    margin-block-end: var(--space-4);
  }

  .back-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    border: none;
    background: none;
    border-radius: var(--radius-full);
    color: var(--color-text-secondary);
    cursor: pointer;
    transition: background var(--transition-fast);
  }

  .back-btn:hover {
    background: var(--color-surface);
  }

  .page-title {
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-text);
  }

  .settings-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .form-group {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .form-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .form-check {
    flex-direction: row;
  }

  .check-label {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    color: var(--color-text);
    cursor: pointer;
  }

  .question-row {
    display: flex;
    gap: var(--space-2);
    align-items: center;
  }

  .question-row .input {
    flex: 1;
  }

  .tab-loading {
    display: flex;
    justify-content: center;
    padding: var(--space-8);
  }

  .tab-empty {
    text-align: center;
    padding: var(--space-12);
  }

  .empty-text {
    color: var(--color-text-tertiary);
  }

  .application-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .application-item {
    padding: var(--space-4);
    background: var(--color-surface);
    border-radius: var(--radius-lg);
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .applicant-info {
    display: flex;
    align-items: center;
    gap: var(--space-3);
  }

  .applicant-details {
    display: flex;
    flex-direction: column;
  }

  .applicant-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .applicant-handle {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .applicant-date {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .applicant-answers {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    padding-inline-start: var(--space-4);
  }

  .qa-question {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
  }

  .qa-answer {
    font-size: var(--text-sm);
    color: var(--color-text);
  }

  .application-actions {
    display: flex;
    gap: var(--space-2);
    justify-content: flex-end;
  }

  .member-mgmt-list {
    display: flex;
    flex-direction: column;
  }

  .member-mgmt-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-3) var(--space-2);
    border-block-end: 1px solid var(--color-border);
    gap: var(--space-3);
    flex-wrap: wrap;
  }

  .member-mgmt-item:last-child {
    border-block-end: none;
  }

  .member-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    min-width: 0;
    flex: 1;
  }

  .member-details {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .member-name-text {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .member-handle-text {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .member-actions {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .role-select {
    width: auto;
    min-width: 120px;
    padding: var(--space-1) var(--space-2);
    font-size: var(--text-xs);
  }

  .role-badge {
    display: inline-flex;
    align-items: center;
    padding: var(--space-1) var(--space-3);
    border-radius: var(--radius-full);
    background: var(--color-surface-container, var(--color-surface));
    color: var(--color-text-secondary);
    font-size: var(--text-xs);
    font-weight: 600;
    text-transform: capitalize;
  }

  .invite-section {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .invite-results {
    display: flex;
    flex-direction: column;
  }

  .invite-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--space-3) var(--space-2);
    border-block-end: 1px solid var(--color-border);
  }

  .invite-item:last-child {
    border-block-end: none;
  }

  .invite-user {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    min-width: 0;
  }

  .invite-user-info {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .invite-user-name {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .invite-user-handle {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }
</style>
