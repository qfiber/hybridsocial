<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import type { Identity } from '$lib/api/types.js';
  import type { GroupDetail, GroupApplication, GroupMember } from '$lib/api/groups.js';
  import {
    getGroup,
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

  const tabs = [
    { id: 'general', label: 'General' },
    { id: 'screening', label: 'Screening' },
    { id: 'applications', label: 'Applications' },
    { id: 'members', label: 'Members' },
    { id: 'invite', label: 'Invite' }
  ];

  onMount(async () => {
    try {
      const g = await getGroup(groupId);
      group = g;
      name = g.name;
      description = g.description ?? '';
      visibility = g.visibility;
      joinPolicy = g.join_policy;

      // Redirect if not admin
      if (g.role !== 'owner' && g.role !== 'admin') {
        goto(`/groups/${groupId}`);
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
      await updateGroup(groupId, {
        screening: {
          questions: screeningQuestions.filter((q) => q.trim()),
          min_account_age_days: minAccountAgeDays,
          require_profile_image: requireProfileImage
        }
      });
    } catch {
      // Error saving
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

  async function handleRoleChange(accountId: string, role: string) {
    try {
      await updateMemberRole(groupId, accountId, role);
      members = members.map((m) =>
        m.account.id === accountId ? { ...m, role: role as GroupMember['role'] } : m
      );
    } catch {
      // Error
    }
  }

  async function handleBan(accountId: string) {
    if (!confirm('Are you sure you want to ban this member?')) return;
    try {
      await banMember(groupId, accountId);
      members = members.filter((m) => m.account.id !== accountId);
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
      inviteResults = inviteResults.filter((a) => a.id !== accountId);
    } catch {
      // Error
    } finally {
      inviting = false;
    }
  }

  function goBack() {
    goto(`/groups/${groupId}`);
  }
</script>

<svelte:head>
  <title>Group Settings - HybridSocial</title>
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
                    <select
                      class="input role-select"
                      value={member.role}
                      onchange={(e) => handleRoleChange(member.account.id, (e.target as HTMLSelectElement).value)}
                    >
                      <option value="member">Member</option>
                      <option value="moderator">Moderator</option>
                      <option value="admin">Admin</option>
                    </select>
                    <button type="button" class="btn btn-danger btn-sm" onclick={() => handleBan(member.account.id)}>
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
