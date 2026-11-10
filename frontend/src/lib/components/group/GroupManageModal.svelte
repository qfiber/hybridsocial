<script lang="ts">
  import Modal from '$lib/components/ui/Modal.svelte';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import {
    updateGroup,
    deleteGroup,
    getGroupMembers,
    updateMemberRole,
    banMember,
    restrictMember,
    unrestrictMember,
    getGroupReports,
    escalateReport,
    type GroupReport,
    type GroupRestriction,
    inviteToGroup,
    getGroupApplications,
    approveApplication,
    rejectApplication,
    listGroupInvites,
    cancelGroupInvite,
    type GroupDetail,
    type GroupMember,
    type GroupApplication,
    type GroupInvite,
  } from '$lib/api/groups.js';
  import { search } from '$lib/api/search.js';
  import { uploadMedia } from '$lib/api/media.js';
  import { displayAcct, type Identity } from '$lib/api/types.js';

  let {
    open = $bindable(false),
    group = $bindable(),
    onclose,
    ondeleted,
  }: {
    open?: boolean;
    group: GroupDetail | null;
    onclose?: () => void;
    // Fired after the group is deleted — the parent page typically
    // navigates away (back to /groups) so the now-stale URL doesn't
    // try to refetch a 404.
    ondeleted?: () => void;
  } = $props();

  // Section names mirror the historical /settings tabs but layered as
  // a sidebar so the admin sees every available action at a glance.
  // "general" stays selected on reopen — most edits live there.
  let section = $state<'general' | 'members' | 'applications' | 'invites' | 'reports' | 'danger'>('general');

  // General — form-bound copies of the group fields so cancel-without-save
  // doesn't leak edits back to the parent's `group` prop.
  let name = $state('');
  let description = $state('');
  let visibility = $state<'public' | 'private' | 'local_only'>('public');
  let joinPolicy = $state<'open' | 'screening' | 'approval' | 'invite_only'>('open');
  let avatarUrl = $state('');
  let headerUrl = $state('');
  let saving = $state(false);
  let avatarUploading = $state(false);
  let headerUploading = $state(false);

  // Lazy-loaded section state. Each section's data only fetches the
  // first time the section opens, then refreshes on subsequent opens
  // so a long-running modal stays current without thrashing.
  let members = $state<GroupMember[]>([]);
  let membersLoading = $state(false);
  let applications = $state<GroupApplication[]>([]);
  let applicationsLoading = $state(false);
  let invitesSent = $state<GroupInvite[]>([]);
  let invitesLoading = $state(false);

  // Invite search.
  let inviteQuery = $state('');
  let inviteResults = $state<Identity[]>([]);
  let inviteSearching = $state(false);
  let inviteSendingId = $state<string | null>(null);
  let inviteTimeout: ReturnType<typeof setTimeout> | undefined;

  // Danger Zone — typed-name confirmation prevents accidental deletes.
  let deleteConfirmation = $state('');
  let deleting = $state(false);

  let isOwner = $derived(group?.role === 'owner');
  // Only the group's own owner can delete it here. Instance-staff takedowns
  // go through AdminProfileActions on the group header, not these settings.
  let canDelete = $derived(isOwner);
  let groupId = $derived(group?.id ?? '');
  // Members across the conversation get tagged as "needs reviewing"
  // when applications exist; show the Applications section only if
  // the policy can actually generate them.
  let hasApplications = $derived(
    group?.join_policy === 'approval' || group?.join_policy === 'screening',
  );

  // Repopulate form state every time the parent passes in a fresh
  // group object (initial open, or after a save round-trip).
  $effect(() => {
    if (!group) return;
    name = group.name;
    description = group.description ?? '';
    visibility = group.visibility;
    joinPolicy = group.join_policy;
    avatarUrl = group.avatar_url ?? '';
    headerUrl = group.header_url ?? '';
  });

  // When `open` flips true, default back to General. The previous
  // selection isn't kept — admins rarely want to land back where they
  // left off when they're reopening days later.
  $effect(() => {
    if (open) section = 'general';
  });

  // Lazy-load each section's data. Re-triggers when groupId changes
  // (the modal can be reused across groups in theory).
  $effect(() => {
    if (!open || !groupId) return;
    if (section === 'members') void loadMembers();
    if (section === 'applications') void loadApplications();
    if (section === 'invites') void loadInvites();
    if (section === 'reports') void loadReports();
  });

  // The members + applications endpoints currently return bare arrays
  // server-side while their TypeScript signatures still say
  // `PaginatedResponse<T>` — accept either shape so the modal doesn't
  // explode reading `.data` off an Array. Drop this once the backend
  // wraps these responses.
  function unwrap<T>(value: unknown): T[] {
    if (Array.isArray(value)) return value as T[];
    if (value && typeof value === 'object' && Array.isArray((value as { data?: T[] }).data)) {
      return (value as { data: T[] }).data;
    }
    return [];
  }

  async function loadMembers() {
    membersLoading = true;
    try {
      const result = await getGroupMembers(groupId);
      members = unwrap<GroupMember>(result);
    } catch {
      addToast('Failed to load members', 'error');
    } finally {
      membersLoading = false;
    }
  }

  async function loadApplications() {
    applicationsLoading = true;
    try {
      const result = await getGroupApplications(groupId);
      applications = unwrap<GroupApplication>(result);
    } catch {
      addToast('Failed to load applications', 'error');
    } finally {
      applicationsLoading = false;
    }
  }

  async function loadInvites() {
    invitesLoading = true;
    try {
      invitesSent = await listGroupInvites(groupId);
    } catch {
      addToast('Failed to load invites', 'error');
    } finally {
      invitesLoading = false;
    }
  }

  async function saveGeneral() {
    saving = true;
    try {
      const updated = await updateGroup(groupId, {
        name: name.trim(),
        description: description.trim(),
        visibility,
        join_policy: joinPolicy,
        avatar_url: avatarUrl.trim() || null,
        header_url: headerUrl.trim() || null,
      });
      group = updated;
      addToast('Group updated', 'success');
    } catch (err) {
      const msg = (err as { message?: string })?.message || 'Could not save changes';
      addToast(msg, 'error');
    } finally {
      saving = false;
    }
  }

  async function handleUpload(file: File, target: 'avatar' | 'header') {
    if (target === 'avatar') avatarUploading = true;
    else headerUploading = true;
    try {
      const media = await uploadMedia(file);
      if (target === 'avatar') avatarUrl = media.url;
      else headerUrl = media.url;
    } catch {
      addToast(`Could not upload ${target}`, 'error');
    } finally {
      if (target === 'avatar') avatarUploading = false;
      else headerUploading = false;
    }
  }

  function onPickFile(target: 'avatar' | 'header') {
    return (e: Event) => {
      const input = e.target as HTMLInputElement;
      const f = input.files?.[0];
      input.value = '';
      if (!f) return;
      void handleUpload(f, target);
    };
  }

  async function handleRoleChange(memberId: string, role: GroupMember['role']) {
    try {
      await updateMemberRole(groupId, memberId, role);
      members = members.map((m) => (m.id === memberId ? { ...m, role } : m));
      addToast('Role updated', 'success');
    } catch {
      addToast('Could not change role', 'error');
    }
  }

  // --- Group moderation queue (#86 item 3) ------------------------------
  // Reports routed to this group rather than to instance staff. The site
  // route always exists alongside this one and is never gated on the group
  // agreeing — a group must not be able to funnel complaints about itself
  // into its own queue.
  let reports = $state<GroupReport[]>([]);
  let reportsLoading = $state(false);
  // Mirrors the backend's `group_report_escalation_hours` default; only used
  // for the explanatory copy, not for any decision.
  const reportEscalationHours = 72;

  async function loadReports() {
    reportsLoading = true;
    try {
      reports = await getGroupReports(groupId);
    } catch {
      addToast('Could not load reports', 'error');
    } finally {
      reportsLoading = false;
    }
  }

  async function handleEscalate(reportId: string) {
    try {
      await escalateReport(reportId);
      reports = reports.map((r) =>
        r.id === reportId ? { ...r, escalated_at: new Date().toISOString() } : r,
      );
      addToast('Sent to the site moderators', 'success');
    } catch {
      addToast('Could not send this to the site moderators', 'error');
    }
  }

  // --- Partial / timed bans (#86) ---------------------------------------
  // A full ban removes someone; these withhold specific actions while leaving
  // them in the group, optionally lapsing on their own.
  const RESTRICTABLE: { value: GroupRestriction; label: string }[] = [
    { value: 'post', label: 'Posting' },
    { value: 'comment', label: 'Replying' },
    { value: 'react', label: 'Reacting' },
  ];

  const DURATIONS: { value: string; label: string }[] = [
    { value: '', label: 'Until lifted' },
    { value: '3600', label: '1 hour' },
    { value: '86400', label: '1 day' },
    { value: '604800', label: '1 week' },
    { value: '2592000', label: '30 days' },
  ];

  let restrictOpenFor = $state<string | null>(null);
  let draftRestrictions = $state<GroupRestriction[]>([]);
  let draftDuration = $state('');
  let draftReason = $state('');
  let restrictSaving = $state(false);

  function toggleRestrict(m: GroupMember) {
    if (restrictOpenFor === m.id) {
      restrictOpenFor = null;
      return;
    }
    restrictOpenFor = m.id ?? null;
    draftRestrictions = [...(m.restrictions ?? [])];
    draftDuration = '';
    draftReason = m.restriction_reason ?? '';
  }

  function toggleDraftRestriction(action: GroupRestriction) {
    draftRestrictions = draftRestrictions.includes(action)
      ? draftRestrictions.filter((a) => a !== action)
      : [...draftRestrictions, action];
  }

  // Only ever in force when non-empty. The backend already excludes lapsed
  // sanctions from `restrictions`, so no expiry maths is needed here.
  function activeSanction(m: GroupMember): boolean {
    return (m.restrictions?.length ?? 0) > 0;
  }

  function sanctionLabel(m: GroupMember): string {
    const names = (m.restrictions ?? [])
      .map((r) => RESTRICTABLE.find((a) => a.value === r)?.label ?? r)
      .join(', ');
    const when = m.restricted_until
      ? `until ${new Date(m.restricted_until).toLocaleString()}`
      : 'until lifted';
    return `Restricted: ${names} — ${when}`;
  }

  async function handleRestrict(memberId: string) {
    restrictSaving = true;
    try {
      const until = draftDuration
        ? new Date(Date.now() + Number(draftDuration) * 1000).toISOString()
        : null;

      const updated = await restrictMember(groupId, memberId, {
        restrictions: draftRestrictions,
        until,
        reason: draftReason || undefined,
      });

      members = members.map((m) => (m.id === memberId ? { ...m, ...updated } : m));
      restrictOpenFor = null;
      addToast('Restrictions applied', 'success');
    } catch {
      addToast('Could not apply restrictions', 'error');
    } finally {
      restrictSaving = false;
    }
  }

  async function handleUnrestrict(memberId: string) {
    try {
      const updated = await unrestrictMember(groupId, memberId);
      members = members.map((m) => (m.id === memberId ? { ...m, ...updated } : m));
      addToast('Restrictions lifted', 'success');
    } catch {
      addToast('Could not lift restrictions', 'error');
    }
  }

  async function handleBan(memberId: string) {
    if (!confirm('Remove this member from the group?')) return;
    try {
      await banMember(groupId, memberId);
      members = members.filter((m) => m.id !== memberId);
      if (group) group = { ...group, member_count: Math.max(0, group.member_count - 1) };
    } catch {
      addToast('Could not remove member', 'error');
    }
  }

  async function handleApprove(applicationId: string) {
    try {
      await approveApplication(groupId, applicationId);
      applications = applications.filter((a) => a.id !== applicationId);
      addToast('Application approved', 'success');
    } catch {
      addToast('Could not approve', 'error');
    }
  }

  async function handleReject(applicationId: string) {
    try {
      await rejectApplication(groupId, applicationId);
      applications = applications.filter((a) => a.id !== applicationId);
    } catch {
      addToast('Could not reject', 'error');
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

  async function handleInvite(account: Identity) {
    inviteSendingId = account.id;
    try {
      await inviteToGroup(groupId, account.id);
      // Drop from results so the user can't accidentally re-send.
      inviteResults = inviteResults.filter((a) => a.id !== account.id);
      addToast(`Invited @${displayAcct(account)}`, 'success');
      // Refresh the pending list so the new invite shows up.
      void loadInvites();
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
      inviteSendingId = null;
    }
  }

  async function handleCancelInvite(inviteId: string) {
    try {
      await cancelGroupInvite(groupId, inviteId);
      invitesSent = invitesSent.filter((i) => i.id !== inviteId);
      addToast('Invite cancelled', 'success');
    } catch {
      addToast('Could not cancel invite', 'error');
    }
  }

  async function handleDelete() {
    if (deleteConfirmation !== group?.name) return;
    deleting = true;
    try {
      await deleteGroup(groupId);
      open = false;
      ondeleted?.();
    } catch {
      addToast('Could not delete group', 'error');
      deleting = false;
    }
  }

  function roleLabel(role: string): string {
    switch (role) {
      case 'owner': return 'Owner';
      case 'admin': return 'Admin';
      case 'moderator': return 'Moderator';
      default: return 'Member';
    }
  }
</script>

<Modal bind:open title="Manage group" size="lg" {onclose}>
  <div class="manage-shell">
    <aside class="manage-sidebar" aria-label="Management sections">
      <button
        type="button"
        class="sidebar-item"
        class:sidebar-item-active={section === 'general'}
        onclick={() => (section = 'general')}
      >
        <span class="material-symbols-outlined">tune</span>
        General
      </button>
      <button
        type="button"
        class="sidebar-item"
        class:sidebar-item-active={section === 'members'}
        onclick={() => (section = 'members')}
      >
        <span class="material-symbols-outlined">group</span>
        Members
      </button>
      {#if hasApplications}
        <button
          type="button"
          class="sidebar-item"
          class:sidebar-item-active={section === 'applications'}
          onclick={() => (section = 'applications')}
        >
          <span class="material-symbols-outlined">how_to_reg</span>
          Applications
        </button>
      {/if}
      <button
        type="button"
        class="sidebar-item"
        class:sidebar-item-active={section === 'invites'}
        onclick={() => (section = 'invites')}
      >
        <span class="material-symbols-outlined">person_add</span>
        Invites
      </button>
      <button
        type="button"
        class="sidebar-item"
        class:sidebar-item-active={section === 'reports'}
        onclick={() => (section = 'reports')}
      >
        <span class="material-symbols-outlined">flag</span>
        Reports
      </button>
      {#if canDelete}
        <button
          type="button"
          class="sidebar-item sidebar-item-danger"
          class:sidebar-item-active={section === 'danger'}
          onclick={() => (section = 'danger')}
        >
          <span class="material-symbols-outlined">warning</span>
          Danger zone
        </button>
      {/if}
    </aside>

    <section class="manage-content">
      {#if section === 'general'}
        <h3 class="section-title">General</h3>
        <p class="section-help">Identity and joining behaviour.</p>

        <div class="form-group">
          <span class="form-label">Hero banner</span>
          <div class="media-tile media-tile-wide">
            {#if headerUrl}
              <img src={headerUrl} alt="" class="media-preview" />
            {:else}
              <div class="media-placeholder">No banner</div>
            {/if}
            <label class="media-pick">
              {headerUploading ? 'Uploading…' : 'Choose'}
              <input
                type="file"
                accept="image/*"
                disabled={headerUploading}
                onchange={onPickFile('header')}
              />
            </label>
          </div>
          <input
            type="url"
            class="input"
            placeholder="Or paste an image URL"
            bind:value={headerUrl}
            maxlength="2048"
          />
        </div>

        <div class="form-group">
          <span class="form-label">Avatar</span>
          <div class="media-tile media-tile-square">
            {#if avatarUrl}
              <img src={avatarUrl} alt="" class="media-preview" />
            {:else}
              <div class="media-placeholder">No avatar</div>
            {/if}
            <label class="media-pick">
              {avatarUploading ? 'Uploading…' : 'Choose'}
              <input
                type="file"
                accept="image/*"
                disabled={avatarUploading}
                onchange={onPickFile('avatar')}
              />
            </label>
          </div>
          <input
            type="url"
            class="input"
            placeholder="Or paste an image URL"
            bind:value={avatarUrl}
            maxlength="2048"
          />
        </div>

        <div class="form-group">
          <label for="group-mgr-name" class="form-label">Name</label>
          <input id="group-mgr-name" type="text" class="input" bind:value={name} required />
        </div>

        <div class="form-group">
          <label for="group-mgr-desc" class="form-label">Description</label>
          <textarea
            id="group-mgr-desc"
            class="input"
            rows="3"
            bind:value={description}
          ></textarea>
        </div>

        <div class="form-row">
          <div class="form-group">
            <label for="group-mgr-visibility" class="form-label">Visibility</label>
            <select id="group-mgr-visibility" class="input" bind:value={visibility}>
              <option value="public">Public</option>
              <option value="private">Private</option>
              <option value="local_only">Local only</option>
            </select>
          </div>
          <div class="form-group">
            <label for="group-mgr-policy" class="form-label">Join policy</label>
            <select id="group-mgr-policy" class="input" bind:value={joinPolicy}>
              <option value="open">Open</option>
              <option value="screening">Screening (approval + questions)</option>
              <option value="approval">Requires approval</option>
              <option value="invite_only">Invite only</option>
            </select>
          </div>
        </div>

        <div class="section-actions">
          <button class="btn btn-primary" type="button" disabled={saving} onclick={saveGeneral}>
            {saving ? 'Saving…' : 'Save changes'}
          </button>
        </div>
      {:else if section === 'members'}
        <h3 class="section-title">Members</h3>
        <p class="section-help">Promote, demote, or remove members.</p>

        {#if membersLoading}
          <div class="section-loading"><Spinner /></div>
        {:else if members.length === 0}
          <p class="section-empty">No members.</p>
        {:else}
          <ul class="people-list">
            {#each members as m (m.id || m.account.id)}
              <li class="people-row">
                <Avatar src={m.account.avatar_url} name={m.account.display_name || m.account.handle} size="sm" />
                <div class="people-meta">
                  <span class="people-name">
                    {m.account.display_name || m.account.handle}
                  </span>
                  <span class="people-handle">@{displayAcct(m.account)}</span>
                </div>
                <span class="role-badge role-{m.role}">{roleLabel(m.role)}</span>
                {#if m.role !== 'owner'}
                  <div class="row-actions">
                    <select
                      class="input input-compact"
                      value={m.role}
                      onchange={(e) =>
                        handleRoleChange(
                          m.id!,
                          (e.currentTarget as HTMLSelectElement).value as GroupMember['role'],
                        )}
                    >
                      <option value="member">Member</option>
                      <option value="moderator">Moderator</option>
                      <option value="admin">Admin</option>
                    </select>
                    <button
                      type="button"
                      class="btn btn-sm btn-outline"
                      aria-expanded={restrictOpenFor === m.id}
                      onclick={() => toggleRestrict(m)}
                    >
                      Restrict
                    </button>
                    <button
                      type="button"
                      class="btn btn-sm btn-danger-outline"
                      onclick={() => handleBan(m.id!)}
                    >
                      Remove
                    </button>
                  </div>
                {/if}

                {#if activeSanction(m)}
                  <p class="sanction-note">
                    {sanctionLabel(m)}
                    <button type="button" class="linkbtn" onclick={() => handleUnrestrict(m.id!)}>
                      Lift
                    </button>
                  </p>
                {/if}

                {#if restrictOpenFor === m.id}
                  <div class="restrict-panel">
                    <fieldset class="restrict-actions">
                      <legend class="restrict-legend">Withhold</legend>
                      {#each RESTRICTABLE as action (action.value)}
                        <label class="restrict-check">
                          <input
                            type="checkbox"
                            checked={draftRestrictions.includes(action.value)}
                            onchange={() => toggleDraftRestriction(action.value)}
                          />
                          {action.label}
                        </label>
                      {/each}
                    </fieldset>

                    <label class="restrict-field">
                      <span class="restrict-legend">Duration</span>
                      <select class="input input-compact" bind:value={draftDuration}>
                        {#each DURATIONS as d (d.value)}
                          <option value={d.value}>{d.label}</option>
                        {/each}
                      </select>
                    </label>

                    <input
                      class="input input-compact restrict-reason"
                      placeholder="Reason (optional)"
                      bind:value={draftReason}
                    />

                    <div class="restrict-buttons">
                      <button
                        type="button"
                        class="btn btn-sm btn-primary"
                        disabled={draftRestrictions.length === 0 || restrictSaving}
                        onclick={() => handleRestrict(m.id!)}
                      >
                        Apply
                      </button>
                      <button
                        type="button"
                        class="btn btn-sm btn-ghost"
                        onclick={() => (restrictOpenFor = null)}
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                {/if}
              </li>
            {/each}
          </ul>
        {/if}
      {:else if section === 'applications'}
        <h3 class="section-title">Applications</h3>
        <p class="section-help">People who asked to join.</p>

        {#if applicationsLoading}
          <div class="section-loading"><Spinner /></div>
        {:else if applications.length === 0}
          <p class="section-empty">No pending applications.</p>
        {:else}
          <ul class="people-list">
            {#each applications as a (a.id)}
              <li class="people-row people-row-stacked">
                <div class="people-row-top">
                  <Avatar src={a.account.avatar_url} name={a.account.display_name || a.account.handle} size="sm" />
                  <div class="people-meta">
                    <span class="people-name">{a.account.display_name || a.account.handle}</span>
                    <span class="people-handle">@{displayAcct(a.account)}</span>
                  </div>
                  <div class="row-actions">
                    <button class="btn btn-sm btn-primary" type="button" onclick={() => handleApprove(a.id)}>
                      Approve
                    </button>
                    <button class="btn btn-sm btn-outline" type="button" onclick={() => handleReject(a.id)}>
                      Reject
                    </button>
                  </div>
                </div>
                {#if a.answers && a.answers.length > 0}
                  <div class="application-answers">
                    {#each a.answers as ans}
                      <div class="application-answer">
                        <span class="application-q">{ans.question}</span>
                        <span class="application-a">{ans.answer}</span>
                      </div>
                    {/each}
                  </div>
                {/if}
              </li>
            {/each}
          </ul>
        {/if}
      {:else if section === 'invites'}
        <h3 class="section-title">Invite people</h3>
        <p class="section-help">Search for someone, send them an invite, or cancel a pending one.</p>

        <input
          type="search"
          class="input"
          placeholder="Search by name or @handle"
          bind:value={inviteQuery}
          oninput={handleInviteSearch}
        />
        {#if inviteSearching}
          <div class="section-loading section-loading-compact"><Spinner /></div>
        {:else if inviteResults.length > 0}
          <ul class="people-list">
            {#each inviteResults as account (account.id)}
              <li class="people-row">
                <Avatar src={account.avatar_url} name={account.display_name || account.handle} size="sm" />
                <div class="people-meta">
                  <span class="people-name">{account.display_name || account.handle}</span>
                  <span class="people-handle">@{displayAcct(account)}</span>
                </div>
                <button
                  type="button"
                  class="btn btn-sm btn-primary"
                  disabled={inviteSendingId === account.id}
                  onclick={() => handleInvite(account)}
                >
                  {inviteSendingId === account.id ? 'Sending…' : 'Invite'}
                </button>
              </li>
            {/each}
          </ul>
        {/if}

        <h4 class="subsection-title">Pending invites</h4>
        {#if invitesLoading}
          <div class="section-loading section-loading-compact"><Spinner /></div>
        {:else if invitesSent.length === 0}
          <p class="section-empty">No pending invites.</p>
        {:else}
          <ul class="people-list">
            {#each invitesSent as inv (inv.id)}
              {@const target = inv.invited}
              <li class="people-row">
                <Avatar
                  src={target?.avatar_url || null}
                  name={target?.display_name || target?.handle || 'Invited user'}
                  size="sm"
                />
                <div class="people-meta">
                  <span class="people-name">
                    {target?.display_name || target?.handle || 'Invited user'}
                  </span>
                  {#if target?.handle}
                    <span class="people-handle">@{displayAcct(target)}</span>
                  {/if}
                </div>
                <button
                  type="button"
                  class="btn btn-sm btn-danger-outline"
                  onclick={() => handleCancelInvite(inv.id)}
                >
                  Cancel
                </button>
              </li>
            {/each}
          </ul>
        {/if}
      {:else if section === 'reports'}
        <h3 class="section-title">Reports</h3>
        <p class="section-help">
          Things members reported as breaking this group's rules. Anything reported as breaking
          the site's rules goes to the site moderators instead — and a report left unhandled here
          becomes visible to them after {reportEscalationHours}h.
        </p>

        {#if reportsLoading}
          <div class="section-loading"><Spinner /></div>
        {:else if reports.length === 0}
          <p class="section-empty">No reports.</p>
        {:else}
          <ul class="people-list">
            {#each reports as r (r.id)}
              <li class="people-row report-row">
                <div class="people-meta">
                  <span class="people-name">
                    {r.category}
                    {#if r.escalated_at}
                      <span class="report-flag">with site moderators</span>
                    {/if}
                  </span>
                  {#if r.description}
                    <span class="people-handle">{r.description}</span>
                  {/if}
                  <span class="people-handle">
                    reported by @{r.reporter?.handle ?? 'unknown'} · {new Date(
                      r.created_at,
                    ).toLocaleString()}
                  </span>
                </div>
                {#if !r.escalated_at}
                  <button
                    type="button"
                    class="btn btn-sm btn-outline"
                    onclick={() => handleEscalate(r.id)}
                  >
                    Send to site moderators
                  </button>
                {/if}
              </li>
            {/each}
          </ul>
        {/if}
      {:else if section === 'danger'}
        <h3 class="section-title section-title-danger">Danger zone</h3>
        <p class="section-help">
          Deleting the group removes its posts and memberships. This cannot be undone.
        </p>

        <div class="danger-card">
          <p class="danger-text">
            Type <strong>{group?.name ?? ''}</strong> to confirm.
          </p>
          <input
            type="text"
            class="input"
            placeholder={group?.name ?? ''}
            bind:value={deleteConfirmation}
          />
          <button
            class="btn btn-danger"
            type="button"
            disabled={deleting || deleteConfirmation !== group?.name}
            onclick={handleDelete}
          >
            {deleting ? 'Deleting…' : 'Delete group'}
          </button>
        </div>
      {/if}
    </section>
  </div>
</Modal>

<style>
  .manage-shell {
    display: grid;
    grid-template-columns: 200px 1fr;
    gap: 0;
    min-height: 480px;
    /* The modal-body wrapper applies its own padding; pull it back so
       the sidebar can run flush against the dialog edge. */
    margin: calc(var(--space-6) * -1);
  }

  @media (max-width: 640px) {
    .manage-shell {
      grid-template-columns: 1fr;
      grid-template-rows: auto 1fr;
      min-height: 0;
    }
  }

  .manage-sidebar {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: var(--space-3);
    background: var(--color-surface);
    border-inline-end: 1px solid var(--color-border);
  }

  @media (max-width: 640px) {
    .manage-sidebar {
      flex-direction: row;
      overflow-x: auto;
      border-inline-end: none;
      border-block-end: 1px solid var(--color-border);
    }
  }

  .sidebar-item {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2) var(--space-3);
    border: none;
    background: transparent;
    color: var(--color-text);
    border-radius: var(--radius-md);
    cursor: pointer;
    font: inherit;
    text-align: start;
    white-space: nowrap;
    transition: background var(--transition-fast), color var(--transition-fast);
  }

  .sidebar-item:hover {
    background: var(--color-bg);
  }

  .sidebar-item-active {
    background: var(--color-primary-soft);
    color: var(--color-primary);
    font-weight: 600;
  }

  .sidebar-item-danger {
    color: var(--color-danger);
  }

  .sidebar-item-danger.sidebar-item-active {
    background: color-mix(in srgb, var(--color-danger) 12%, transparent);
    color: var(--color-danger);
  }

  .sidebar-item .material-symbols-outlined {
    font-size: 20px;
  }

  .manage-content {
    padding: var(--space-5) var(--space-6);
    overflow-y: auto;
    max-height: 80vh;
    max-height: 80dvh;
  }

  .section-title {
    margin: 0 0 var(--space-1) 0;
    font-size: var(--text-lg);
    font-weight: 600;
  }

  .section-title-danger {
    color: var(--color-danger);
  }

  .subsection-title {
    margin: var(--space-5) 0 var(--space-2) 0;
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .section-help {
    margin: 0 0 var(--space-4) 0;
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
  }

  .section-loading {
    display: flex;
    justify-content: center;
    padding: var(--space-6);
  }

  .section-loading-compact {
    padding: var(--space-3);
  }

  .section-empty {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    padding: var(--space-3) 0;
  }

  .form-group {
    margin-block-end: var(--space-3);
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .form-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--space-3);
  }

  .form-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .section-actions {
    display: flex;
    justify-content: flex-end;
    margin-block-start: var(--space-4);
  }

  .media-tile {
    position: relative;
    width: 100%;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    overflow: hidden;
    margin-block-end: var(--space-2);
  }

  .media-tile-wide {
    aspect-ratio: 3 / 1;
  }

  .media-tile-square {
    width: 96px;
    height: 96px;
  }

  .media-preview {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .media-placeholder {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
  }

  .media-pick {
    position: absolute;
    inset-block-end: 8px;
    inset-inline-end: 8px;
    padding: 4px 10px;
    background: rgba(0, 0, 0, 0.6);
    color: #fff;
    border-radius: var(--radius-sm);
    font-size: var(--text-xs);
    cursor: pointer;
  }

  .media-pick input {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    opacity: 0;
    pointer-events: none;
  }

  .people-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .people-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-2);
    background: var(--color-surface);
    border-radius: var(--radius-md);
  }

  .people-row-stacked {
    flex-direction: column;
    align-items: stretch;
  }

  .people-row-top {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .people-meta {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-width: 0;
  }

  .people-name {
    font-weight: 600;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .people-handle {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .role-badge {
    padding: 2px 8px;
    border-radius: var(--radius-full);
    font-size: var(--text-xs);
    font-weight: 600;
    background: var(--color-bg);
    color: var(--color-text-secondary);
  }

  .role-owner {
    background: var(--color-primary-soft);
    color: var(--color-primary);
  }

  .role-admin {
    background: color-mix(in srgb, var(--color-primary) 18%, transparent);
    color: var(--color-primary);
  }

  .role-moderator {
    background: color-mix(in srgb, var(--color-text-secondary) 18%, transparent);
  }

  .row-actions {
    display: flex;
    gap: var(--space-2);
    align-items: center;
  }

  /* Partial/timed ban editor. Sits under its member row and spans the grid so
     it doesn't squeeze the row's own columns. */
  .restrict-panel {
    grid-column: 1 / -1;
    display: flex;
    flex-wrap: wrap;
    align-items: flex-end;
    gap: var(--space-3);
    margin-block-start: var(--space-2);
    padding: var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    background: var(--color-surface);
  }

  .restrict-actions {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-3);
    border: none;
    padding: 0;
    margin: 0;
  }

  .restrict-legend {
    display: block;
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
    margin-block-end: 4px;
  }

  .restrict-check {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: var(--text-sm);
    /* Touch targets: the checkbox alone is too small on a phone. */
    min-height: 32px;
  }

  .restrict-field {
    display: flex;
    flex-direction: column;
  }

  .restrict-reason {
    flex: 1 1 12rem;
    min-width: 0;
  }

  .restrict-buttons {
    display: flex;
    gap: var(--space-2);
  }

  .report-row {
    align-items: flex-start;
  }

  .report-flag {
    margin-inline-start: var(--space-2);
    padding: 1px 8px;
    border-radius: var(--radius-full);
    font-size: var(--text-xs);
    font-weight: 600;
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }

  .sanction-note {
    grid-column: 1 / -1;
    margin: 4px 0 0;
    font-size: var(--text-xs);
    color: var(--color-warning, var(--color-text-secondary));
  }

  .linkbtn {
    background: none;
    border: none;
    padding: 0;
    margin-inline-start: var(--space-2);
    color: var(--color-primary);
    font-size: inherit;
    cursor: pointer;
    text-decoration: underline;
  }

  .input-compact {
    padding: 4px 8px;
    font-size: var(--text-sm);
    height: auto;
  }

  .application-answers {
    margin-block-start: var(--space-2);
    padding-block-start: var(--space-2);
    border-block-start: 1px dashed var(--color-border);
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .application-answer {
    display: flex;
    flex-direction: column;
    gap: 2px;
    font-size: var(--text-sm);
  }

  .application-q {
    color: var(--color-text-secondary);
    font-weight: 600;
  }

  .danger-card {
    padding: var(--space-4);
    background: color-mix(in srgb, var(--color-danger) 6%, transparent);
    border: 1px solid color-mix(in srgb, var(--color-danger) 30%, transparent);
    border-radius: var(--radius-md);
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .danger-text {
    margin: 0;
    color: var(--color-text);
    font-size: var(--text-sm);
  }
</style>
