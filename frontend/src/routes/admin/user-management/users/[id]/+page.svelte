<script lang="ts">
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import {
    setUserSearchIndexing,
    getPostLimitDefaults,
    setUserPostLimits,
    type PostLimitDefaults,
    getAdminUser,
    getAdminUserStatuses,
    getAdminUserFollowers,
    removeAdminUserFollower,
    getAdminGroupMembers,
    type AdminGroupMember,
    deleteUser,
    suspendUser,
    unsuspendUser,
    warnUser,
    silenceUser,
    unsilenceUser,
    shadowBanUser,
    unshadowBanUser,
    forceSensitiveUser,
    unforceSensitiveUser,
    revokeAllSessions,
    setTrustLevel,
    getModerationNotes,
    createModerationNote,
    deleteModerationNote,
    resetUserPassword,
    sendUserPasswordResetEmail,
    disableUserTwoFactor,
    changeUserEmail,
    confirmUserEmail,
    changeUserTier,
    verifyUser,
    unverifyUser,
    editUserProfile,
    getRoles,
    getUserRoles,
    assignUserRole,
    revokeUserRole,
    type UserRoleAssignment,
  } from '$lib/api/admin.js';
  import type { AdminUser, ModerationNote, AdminRole, Post } from '$lib/api/types.js';

  let userId = $derived(page.params.id ?? '');

  let user = $state<AdminUser | null>(null);
  let loading = $state(true);
  let error = $state('');
  let busy = $state(''); // key of the in-flight action, to disable its control

  // Editable fields (seeded from the loaded user)
  let warnMessage = $state('');
  let silenceReason = $state('');
  let emailInput = $state('');
  let displayNameInput = $state('');
  let bioInput = $state('');
  let trustInput = $state(0);
  let tierInput = $state('free');
  // Blank means "use the instance default", so these stay strings until saved.
  let limitInputs = $state({ per_minute: '', per_hour: '', per_day: '' });
  let limitDefaults = $state<PostLimitDefaults | null>(null);
  let generatedPassword = $state('');

  let notes = $state<ModerationNote[]>([]);
  let newNote = $state('');
  let showDeleteConfirm = $state(false);
  let allRoles = $state<AdminRole[]>([]);
  let userRoles = $state<UserRoleAssignment[]>([]);

  const tierOptions = [
    // Not a tier: the default limits of an account that hasn't paid for one.
    // Verification is separate (the Verified control beside this).
    { value: 'free', label: 'No tier', description: 'Default limits' },
    { value: 'verified_starter', label: 'Starter (L1)', description: 'Small creators & casual users' },
    { value: 'verified_creator', label: 'Creator (L2)', description: 'Active creators & community builders' },
    { value: 'verified_pro', label: 'Pro (L3)', description: 'Professional accounts, highest limits' },
  ];

  // --- Content tabs (issue #166): the account's own posts / replies / media.
  // Privately-addressed statuses are excluded server-side; see the API comment.
  type ContentTab = 'posts' | 'replies' | 'media';
  const CONTENT_TABS: { value: ContentTab; label: string }[] = [
    { value: 'posts', label: 'Posts' },
    { value: 'replies', label: 'Replies' },
    { value: 'media', label: 'Media' },
  ];
  let contentTab = $state<ContentTab>('posts');
  let content = $state<Post[]>([]);
  let contentLoading = $state(false);
  let contentError = $state('');
  let contentDone = $state(false);

  async function loadContent(append = false) {
    if (!userId) return;
    contentLoading = true;
    if (!append) {
      contentError = '';
      contentDone = false;
    }
    try {
      const params: { type: string; limit: string; max_id?: string } = {
        type: contentTab,
        limit: '20',
      };
      if (append && content.length) params.max_id = content[content.length - 1].id;
      const rows = await getAdminUserStatuses(userId, params);
      const list = Array.isArray(rows) ? rows : [];
      content = append ? [...content, ...list] : list;
      if (list.length < 20) contentDone = true;
    } catch {
      contentError = 'Failed to load content.';
    } finally {
      contentLoading = false;
    }
  }

  function switchContentTab(t: ContentTab) {
    if (t === contentTab) return;
    contentTab = t;
    content = [];
    loadContent();
  }

  // Plain-text preview: the admin list wants a scannable line, not a rendered
  // post. Falls back to the raw content when there's no HTML body (e.g. a
  // media-only post).
  function preview(p: Post): string {
    const raw = (p.content_html || p.content || '').replace(/<[^>]*>/g, ' ');
    const txt = raw.replace(/\s+/g, ' ').trim();
    if (txt) return txt.length > 180 ? txt.slice(0, 180) + '…' : txt;
    return p.media_attachments?.length ? `[${p.media_attachments.length} attachment(s)]` : '—';
  }

  let isLocal = $derived(!!user?.is_local);


  // --- Followers / group members (#167 item 2) --------------------------
  // A page's or group's followers were only ever a number here. These make
  // them visible, and let staff sever a follow (the usual case is cutting a
  // harasser off from someone's posts).
  let followers = $state<AdminUser[]>([]);
  let followersLoading = $state(false);
  let followersLoaded = $state(false);

  let groupMembers = $state<AdminGroupMember[]>([]);
  let groupMembersLoading = $state(false);

  let isGroup = $derived(user?.type === 'group');

  async function loadFollowers() {
    if (followersLoading) return;
    followersLoading = true;
    try {
      followers = (await getAdminUserFollowers(userId, { limit: '100' })).data;
      followersLoaded = true;
    } catch {
      addToast('Could not load followers', 'error');
    } finally {
      followersLoading = false;
    }
  }

  async function handleRemoveFollower(followerId: string, handle: string) {
    if (!confirm(`Remove @${handle} as a follower? They will stop receiving these posts.`)) return;
    try {
      await removeAdminUserFollower(userId, followerId);
      followers = followers.filter((f) => f.id !== followerId);
      if (user) user = { ...user, followers_count: Math.max(0, (user.followers_count ?? 1) - 1) };
      addToast('Follower removed', 'success');
    } catch {
      addToast('Could not remove follower', 'error');
    }
  }

  async function loadGroupMembers() {
    if (groupMembersLoading) return;
    groupMembersLoading = true;
    try {
      groupMembers = (await getAdminGroupMembers(userId)).data;
    } catch {
      addToast('Could not load members', 'error');
    } finally {
      groupMembersLoading = false;
    }
  }

  // Pages, groups and bots are subaccounts: Identity rows with no `users`
  // row, so they own no email, no password and no 2FA — they act under their
  // parent's login. Gating the credential UI on `is_local` alone made every
  // one of them render "Email unverified" plus a password-reset button, which
  // reads as an outstanding action an admin can never resolve.
  //
  // `parent_identity_id` is the reliable marker (a subaccount type always has
  // a parent — see Identity.validate_subaccount_type/1); `type` is belt and
  // braces for payloads that predate it.
  let isSubaccount = $derived(
    !!user?.parent_identity_id || (!!user?.type && user.type !== 'user'),
  );
  let ownsCredentials = $derived(isLocal && !isSubaccount);

  // Where this account's public profile lives: local accounts on this
  // instance, remote ones on their origin server.
  let profileHref = $derived(
    user ? (user.is_local ? `/@${user.handle}` : `/@${user.handle}@${user.domain ?? ''}`) : '',
  );

  onMount(() => {
    load();
    getPostLimitDefaults().then((d) => (limitDefaults = d)).catch(() => {});
  });

  async function load() {
    loading = true;
    error = '';
    try {
      const u = await getAdminUser(userId);
      user = u;
      emailInput = u.email || '';
      displayNameInput = u.display_name || '';
      bioInput = u.bio || '';
      trustInput = u.trust_level ?? 0;
      tierInput = u.verification_tier || 'free';
      limitInputs = {
        per_minute: String(u.post_limits?.per_minute ?? ''),
        per_hour: String(u.post_limits?.per_hour ?? ''),
        per_day: String(u.post_limits?.per_day ?? ''),
      };

      notes = await getModerationNotes(u.id).catch(() => []);
      if (u.is_local) {
        const [roles, assignments] = await Promise.all([
          getRoles().catch(() => []),
          getUserRoles(u.id).catch(() => []),
        ]);
        allRoles = roles;
        userRoles = assignments;
      }
      // Non-blocking: a content failure shouldn't blank the whole page.
      loadContent();
    } catch {
      error = 'Failed to load this user.';
    } finally {
      loading = false;
    }
  }

  async function refresh() {
    try {
      user = await getAdminUser(userId);
    } catch {
      /* keep last-known state */
    }
  }

  // Wrapper for simple actions: run, toast, re-sync the user.
  async function run(key: string, fn: () => Promise<unknown>, ok: string) {
    if (busy) return;
    busy = key;
    try {
      await fn();
      addToast(ok, 'success');
      await refresh();
    } catch {
      addToast('Action failed', 'error');
    } finally {
      busy = '';
    }
  }

  async function handleWarn() {
    if (!user || !warnMessage.trim()) return;
    await run('warn', () => warnUser(user!.id, warnMessage.trim()), 'Warning sent');
    warnMessage = '';
  }

  async function handleSilence() {
    if (!user) return;
    await run(
      'silence',
      () => silenceUser(user!.id, { reason: silenceReason.trim() || undefined }),
      'User silenced',
    );
    silenceReason = '';
  }

  async function handleChangeEmail() {
    if (!user || !emailInput.trim()) return;
    await run('email', () => changeUserEmail(user!.id, emailInput.trim()), 'Email updated');
  }

  async function handleResetPassword() {
    if (!user) return;
    busy = 'resetpw';
    try {
      const res = await resetUserPassword(user.id);
      generatedPassword = res.password;
      addToast('New password generated (shown once below)', 'success');
    } catch {
      addToast('Failed to reset password', 'error');
    } finally {
      busy = '';
    }
  }

  async function handleEditProfile() {
    if (!user) return;
    await run(
      'profile',
      () =>
        editUserProfile(user!.id, {
          display_name: displayNameInput.trim() || null,
          bio: bioInput.trim() || null,
        }),
      'Profile updated',
    );
  }

  async function handleTrust() {
    if (!user) return;
    await run('trust', () => setTrustLevel(user!.id, Number(trustInput)), `Trust level set to ${trustInput}`);
  }

  async function handleTier() {
    if (!user) return;
    await run('tier', () => changeUserTier(user!.id, tierInput), 'Tier updated');
  }

  // Staff verification (#168): the badge and display-name lock, no tier limits.
  let unverifyReason = $state('');
  let showUnverify = $state(false);

  async function handleVerify() {
    if (!user) return;
    await run('verify', () => verifyUser(user!.id), 'Account verified');
  }

  async function handleUnverify() {
    if (!user) return;
    const reason = unverifyReason.trim();
    await run('verify', () => unverifyUser(user!.id, reason || undefined), 'Verification removed');
    showUnverify = false;
    unverifyReason = '';
  }

  const LIMIT_WINDOWS = [
    { key: 'per_minute', window: 'minute', label: 'Per minute' },
    { key: 'per_hour', window: 'hour', label: 'Per hour' },
    { key: 'per_day', window: 'day', label: 'Per day' },
  ] as const;

  function limitDefault(window: 'minute' | 'hour' | 'day'): string {
    if (!limitDefaults || !user) return 'Default';
    const value = limitDefaults[user.is_bot ? 'bot' : 'user'][window];
    return value === 0 ? 'Default: unlimited' : `Default: ${value}`;
  }

  async function handleSearchIndexing(e: Event) {
    if (!user) return;
    const blocked = (e.target as HTMLInputElement).checked;
    await run(
      'indexing',
      () => setUserSearchIndexing(user!.id, blocked),
      blocked ? 'Search engines blocked for this profile' : 'Search engines allowed for this profile',
    );
  }

  async function handlePostLimits() {
    if (!user) return;
    const limits: Record<string, number> = {};
    for (const { key } of LIMIT_WINDOWS) {
      const raw = String(limitInputs[key]).trim();
      if (raw === '') continue;
      const value = Number(raw);
      if (!Number.isInteger(value) || value < 0) {
        addToast('Limits must be whole numbers, 0 or more', 'error');
        return;
      }
      limits[key] = value;
    }
    await run('limits', () => setUserPostLimits(user!.id, limits), 'Posting limits updated');
  }

  async function handleAddNote() {
    if (!user || !newNote.trim()) return;
    busy = 'note';
    try {
      const note = await createModerationNote(user.id, newNote.trim());
      notes = [note, ...notes];
      newNote = '';
      addToast('Note added', 'success');
    } catch {
      addToast('Failed to add note', 'error');
    } finally {
      busy = '';
    }
  }

  async function handleDeleteNote(id: string) {
    busy = 'note:' + id;
    try {
      await deleteModerationNote(id);
      notes = notes.filter((n) => n.id !== id);
    } catch {
      addToast('Failed to delete note', 'error');
    } finally {
      busy = '';
    }
  }

  async function handleDelete() {
    if (!user || busy) return;
    busy = 'delete';
    try {
      const res = await deleteUser(user.id);
      const s = res.data;
      addToast(
        `Account deleted — ${s.posts_deleted} posts, ${s.media_deleted} media removed, ${s.conversations_dropped} conversations dropped`,
        'success',
      );
      showDeleteConfirm = false;
      await goto('/admin/user-management/users');
    } catch {
      addToast('Failed to delete account', 'error');
      busy = '';
    }
  }

  function roleAssignment(role: AdminRole): UserRoleAssignment | undefined {
    return userRoles.find((a) => a.role_id === role.id);
  }

  async function toggleRole(role: AdminRole) {
    if (!user) return;
    busy = 'role:' + role.id;
    try {
      const existing = roleAssignment(role);
      if (existing) {
        await revokeUserRole(user.id, existing.id);
        addToast(`Removed role ${role.name}`, 'success');
      } else {
        await assignUserRole(user.id, role.id);
        addToast(`Granted role ${role.name}`, 'success');
      }
      userRoles = await getUserRoles(user.id).catch(() => userRoles);
    } catch {
      addToast('Failed to update roles', 'error');
    } finally {
      busy = '';
    }
  }

  function fmtDate(s: string | null | undefined): string {
    if (!s) return '—';
    try {
      return new Date(s).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
    } catch {
      return '—';
    }
  }
</script>

<svelte:head>
  <title>{user ? '@' + user.handle : 'User'} - Admin</title>
</svelte:head>

<div class="user-detail">
  <a href="/admin/user-management/users" class="back-link">
    <span class="material-symbols-outlined" aria-hidden="true">arrow_back</span> Back to users
  </a>

  {#if loading}
    <div class="skeleton" style="height: 120px; border-radius: 16px;"></div>
  {:else if error || !user}
    <div class="detail-error">{error || 'User not found.'}</div>
  {:else}
    <!-- Overview -->
    <section class="overview card">
      <Avatar src={user.avatar_url} name={user.display_name || user.handle} size="lg" />
      <div class="overview-main">
        <h1 class="overview-name">{user.display_name || user.handle}</h1>
        <p class="overview-handle">@{user.handle}{#if user.domain}<span class="ov-domain">@{user.domain}</span>{/if}</p>
        <div class="pills">
          {#if user.is_local}<span class="pill pill-neutral">Local</span>{:else}<span class="pill pill-neutral">Remote</span>{/if}
          {#if user.is_admin}<span class="pill pill-info">Admin</span>{/if}
          {#if user.is_bot}<span class="pill pill-neutral">Bot</span>{/if}
          {#if user.is_suspended}<span class="pill pill-danger">Suspended</span>{/if}
          {#if user.is_silenced}<span class="pill pill-warn">Silenced</span>{/if}
          {#if user.is_shadow_banned}<span class="pill pill-warn">Shadow-banned</span>{/if}
          {#if user.force_sensitive}<span class="pill pill-warn">Force-sensitive</span>{/if}
          {#if ownsCredentials}
            {#if user.email_confirmed || user.confirmed_at}<span class="pill pill-ok">Email verified</span>
            {:else}<span class="pill pill-warn">Email unverified</span>{/if}
          {:else if isSubaccount}
            <span class="pill pill-neutral">Subaccount</span>
          {/if}
        </div>
        {#if isSubaccount && user.parent_identity_id}
          <p class="overview-parent">
            Acts under
            <a href="/admin/user-management/users/{user.parent_identity_id}">its owner's account</a>,
            which holds the email, password and 2FA.
          </p>
        {/if}
        <a
          class="btn btn-sm btn-outline visit-profile"
          href={profileHref}
          target={isLocal ? undefined : '_blank'}
          rel={isLocal ? undefined : 'noopener noreferrer'}
        >
          <span class="material-symbols-outlined" aria-hidden="true">open_in_new</span>
          Visit profile
        </a>
      </div>
      <div class="overview-stats">
        <div><span class="stat-n">{user.post_count ?? 0}</span><span class="stat-l">posts</span></div>
        <div><span class="stat-n">{user.reply_count ?? 0}</span><span class="stat-l">replies</span></div>
        <div><span class="stat-n">{user.media_count ?? 0}</span><span class="stat-l">media</span></div>
        <div><span class="stat-n">{user.followers_count ?? 0}</span><span class="stat-l">followers</span></div>
        <div><span class="stat-n">TL {user.trust_level}</span><span class="stat-l">trust</span></div>
        <div><span class="stat-n">{fmtDate(user.created_at)}</span><span class="stat-l">joined</span></div>
        <div><span class="stat-n">{fmtDate(user.last_active_at)}</span><span class="stat-l">last active</span></div>
      </div>
    </section>

    <!-- Followers (#167 item 2). Previously just a number on the stat row,
         with no way to see who they were or act on one. -->
    <section class="card sect">
      <h2 class="sect-title">Followers <span class="sect-count">{user.followers_count ?? 0}</span></h2>

      {#if !followersLoaded}
        <button class="btn btn-secondary" disabled={followersLoading} onclick={loadFollowers}>
          {followersLoading ? 'Loading…' : 'Show followers'}
        </button>
      {:else if followers.length === 0}
        <p class="muted">No followers.</p>
      {:else}
        <ul class="admin-people">
          {#each followers as f (f.id)}
            <li class="admin-person">
              <Avatar src={f.avatar_url} name={f.display_name || f.handle} size="sm" />
              <div class="admin-person-meta">
                <a class="admin-person-name" href="/admin/user-management/users/{f.id}">
                  {f.display_name || f.handle}
                </a>
                <span class="admin-person-handle">@{f.handle}</span>
              </div>
              <button
                class="btn btn-sm btn-danger-outline"
                onclick={() => handleRemoveFollower(f.id, f.handle)}
              >
                Remove
              </button>
            </li>
          {/each}
        </ul>
      {/if}
    </section>

    {#if isGroup}
      <!-- Group members. Read-only on purpose: changing roles is in-group
           governance, which instance staff deliberately don't get. Staff
           moderate the group as an entity; they don't run it. -->
      <section class="card sect">
        <h2 class="sect-title">Group members</h2>
        <p class="muted sect-help">
          Read-only. Roles are the group's own governance — staff can suspend, silence or take
          down the group, but not run it.
        </p>

        {#if groupMembers.length === 0 && !groupMembersLoading}
          <button class="btn btn-secondary" onclick={loadGroupMembers}>Show members</button>
        {:else if groupMembersLoading}
          <p class="muted">Loading…</p>
        {:else}
          <ul class="admin-people">
            {#each groupMembers as m (m.id)}
              <li class="admin-person">
                <Avatar
                  src={m.account?.avatar_url}
                  name={m.account?.display_name || m.account?.handle || '?'}
                  size="sm"
                />
                <div class="admin-person-meta">
                  {#if m.account}
                    <a class="admin-person-name" href="/admin/user-management/users/{m.account.id}">
                      {m.account.display_name || m.account.handle}
                    </a>
                    <span class="admin-person-handle">@{m.account.handle}</span>
                  {:else}
                    <span class="admin-person-name">Unknown account</span>
                  {/if}
                </div>
                <span class="pill pill-neutral">{m.role}</span>
              </li>
            {/each}
          </ul>
        {/if}
      </section>
    {/if}

    <!-- Content (issue #166): what this account has posted -->
    <section class="card sect">
      <h2 class="sect-title">Content</h2>
      <div class="content-tabs" role="tablist">
        {#each CONTENT_TABS as t (t.value)}
          <button
            type="button"
            role="tab"
            class="content-tab"
            class:on={contentTab === t.value}
            aria-selected={contentTab === t.value}
            onclick={() => switchContentTab(t.value)}
          >
            {t.label}
            <span class="content-tab-n">
              {t.value === 'posts'
                ? (user.post_count ?? 0)
                : t.value === 'replies'
                  ? (user.reply_count ?? 0)
                  : (user.media_count ?? 0)}
            </span>
          </button>
        {/each}
      </div>

      {#if contentError}
        <div class="detail-error">{contentError}</div>
      {:else if contentLoading && content.length === 0}
        <div class="skeleton" style="height: 72px; border-radius: 12px;"></div>
      {:else if content.length === 0}
        <p class="content-empty">Nothing here.</p>
      {:else}
        <ul class="content-list">
          {#each content as p (p.id)}
            <li class="content-row">
              <a class="content-link" href={`/admin/posts/${p.id}`}>
                <span class="content-text">{preview(p)}</span>
              </a>
              <span class="content-meta">
                {#if p.media_attachments?.length}
                  <span class="material-symbols-outlined content-ic" aria-label="has media">image</span>
                {/if}
                {#if p.visibility && p.visibility !== 'public'}
                  <span class="pill pill-neutral content-vis">{p.visibility}</span>
                {/if}
                <span class="content-date">{fmtDate(p.created_at)}</span>
              </span>
            </li>
          {/each}
        </ul>
        {#if !contentDone}
          <button
            type="button"
            class="btn btn-sm btn-outline"
            disabled={contentLoading}
            onclick={() => loadContent(true)}
          >
            {contentLoading ? 'Loading…' : 'Load more'}
          </button>
        {/if}
      {/if}
      <p class="content-note">
        Privately-addressed statuses (direct messages) are never listed here.
      </p>
    </section>

    <!-- Moderation -->
    {#if user.is_local}
      <section class="card sect">
        <h2 class="sect-title">Search engines</h2>
        <p class="muted">
          Blocking asks search engines not to index this profile and its posts, and removes
          them from the sitemap. The page can still be viewed without logging in.
        </p>
        <label class="inline-row">
          <input
            type="checkbox"
            checked={user.search_indexing_blocked ?? false}
            disabled={busy === 'indexing'}
            onchange={handleSearchIndexing}
          />
          <span>Block search engines from this profile</span>
        </label>
      </section>

      <section class="card sect">
        <h2 class="sect-title">Posting limits</h2>
        <p class="muted">
          Leave blank to use the instance default. 0 means unlimited. Posts over the limit are
          refused, and the person is told when they can post again.
        </p>
        <div class="access-grid">
          {#each LIMIT_WINDOWS as limit (limit.key)}
            <div class="inline-form">
              <label class="field-label" for="limit-{limit.key}">{limit.label}</label>
              <input
                id="limit-{limit.key}"
                class="input limit-input"
                type="number"
                min="0"
                step="1"
                inputmode="numeric"
                placeholder={limitDefault(limit.window)}
                bind:value={limitInputs[limit.key]}
              />
            </div>
          {/each}
        </div>
        <div>
          <button class="btn btn-secondary" disabled={busy === 'limits'} onclick={handlePostLimits}>
            Save limits
          </button>
        </div>
      </section>
    {/if}

    <section class="card sect">
      <h2 class="sect-title">Moderation</h2>
      <div class="btn-row">
        {#if user.is_suspended}
          <button class="btn btn-secondary" disabled={busy === 'suspend'} onclick={() => run('suspend', () => unsuspendUser(user!.id), 'Unsuspended')}>Unsuspend</button>
        {:else}
          <button class="btn btn-danger" disabled={busy === 'suspend'} onclick={() => run('suspend', () => suspendUser(user!.id), 'Suspended')}>Suspend</button>
        {/if}
        {#if user.is_silenced}
          <button class="btn btn-secondary" disabled={busy === 'silence'} onclick={() => run('silence', () => unsilenceUser(user!.id), 'Unsilenced')}>Unsilence</button>
        {/if}
        {#if user.is_shadow_banned}
          <button class="btn btn-secondary" disabled={busy === 'shadow'} onclick={() => run('shadow', () => unshadowBanUser(user!.id), 'Unshadow-banned')}>Un-shadow-ban</button>
        {:else}
          <button class="btn btn-secondary" disabled={busy === 'shadow'} onclick={() => run('shadow', () => shadowBanUser(user!.id), 'Shadow-banned')}>Shadow-ban</button>
        {/if}
        {#if user.force_sensitive}
          <button class="btn btn-secondary" disabled={busy === 'sensitive'} onclick={() => run('sensitive', () => unforceSensitiveUser(user!.id), 'Cleared force-sensitive')}>Clear force-sensitive</button>
        {:else}
          <button class="btn btn-secondary" disabled={busy === 'sensitive'} onclick={() => run('sensitive', () => forceSensitiveUser(user!.id), 'Force-sensitive set')}>Force-sensitive</button>
        {/if}
        {#if user.is_local}
          <button class="btn btn-secondary" disabled={busy === 'sessions'} onclick={() => run('sessions', () => revokeAllSessions(user!.id), 'Sessions revoked')}>Revoke sessions</button>
        {/if}
      </div>

      <div class="inline-form">
        <label class="field-label" for="warn">Warn user</label>
        <div class="inline-row">
          <input id="warn" class="input" placeholder="Message shown to the user" bind:value={warnMessage} />
          <button class="btn btn-primary" disabled={!warnMessage.trim() || busy === 'warn'} onclick={handleWarn}>Send</button>
        </div>
      </div>

      {#if !user.is_silenced}
        <div class="inline-form">
          <label class="field-label" for="silence-reason">Silence (optional reason)</label>
          <div class="inline-row">
            <input id="silence-reason" class="input" placeholder="Reason (internal)" bind:value={silenceReason} />
            <button class="btn btn-secondary" disabled={busy === 'silence'} onclick={handleSilence}>Silence</button>
          </div>
        </div>
      {/if}
    </section>

    {#if user.is_local}
      <!-- Danger zone -->
      <section class="card sect danger-zone">
        <h2 class="sect-title">Danger zone</h2>
        <div class="danger-body">
          <div class="danger-copy">
            <strong>Delete this account</strong>
            <p>
              Permanently removes the account and purges its posts, replies, and media.
              Direct messages are kept for the other person (this user shows as
              <em>Deleted User</em>), and dropped only when the other participant is also
              deleted. This cannot be undone.
            </p>
          </div>
          <button
            class="btn btn-danger"
            disabled={busy === 'delete'}
            onclick={() => (showDeleteConfirm = true)}
          >
            Delete user
          </button>
        </div>
      </section>
    {/if}

    {#if ownsCredentials}
      <!-- Account & security. Subaccounts are excluded: they have no `users`
           row, so email / password / 2FA all belong to the parent account. -->
      <section class="card sect">
        <h2 class="sect-title">Account &amp; security</h2>
        <div class="inline-form">
          <label class="field-label" for="email">Email address</label>
          <div class="inline-row">
            <input id="email" type="email" class="input" bind:value={emailInput} />
            <button class="btn btn-secondary" disabled={!emailInput.trim() || busy === 'email'} onclick={handleChangeEmail}>Change</button>
          </div>
        </div>

        <div class="btn-row">
          {#if !(user.email_confirmed || user.confirmed_at)}
            <button class="btn btn-secondary" disabled={busy === 'confirm'} onclick={() => run('confirm', () => confirmUserEmail(user!.id), 'Email marked verified')}>Mark email verified</button>
          {/if}
          <button class="btn btn-secondary" disabled={busy === 'sendreset'} onclick={() => run('sendreset', () => sendUserPasswordResetEmail(user!.id), 'Password-reset email sent')}>Send password-reset email</button>
          <button class="btn btn-secondary" disabled={busy === 'resetpw'} onclick={handleResetPassword}>Generate new password</button>
          {#if user.two_factor_enabled}
            <button class="btn btn-danger" disabled={busy === '2fa'} onclick={() => run('2fa', () => disableUserTwoFactor(user!.id), '2FA disabled')}>Disable 2FA</button>
          {/if}
        </div>

        {#if generatedPassword}
          <div class="pw-box">
            <span class="field-label">New password (copy it now, shown once)</span>
            <code class="pw-code">{generatedPassword}</code>
            <button class="btn btn-secondary btn-sm" onclick={() => { navigator.clipboard?.writeText(generatedPassword); addToast('Copied', 'success'); }}>Copy</button>
          </div>
        {/if}

        <div class="inline-form">
          <label class="field-label" for="dn">Display name</label>
          <input id="dn" class="input" bind:value={displayNameInput} />
          <label class="field-label" for="bio" style="margin-top:10px;">Bio</label>
          <textarea id="bio" class="textarea" rows="3" bind:value={bioInput}></textarea>
          <div style="margin-top:10px;">
            <button class="btn btn-primary" disabled={busy === 'profile'} onclick={handleEditProfile}>Save profile</button>
          </div>
        </div>
      </section>

      <!-- Access -->
      <section class="card sect">
        <h2 class="sect-title">Access</h2>
        <div class="access-grid">
          <div class="inline-form">
            <label class="field-label" for="trust">Trust level</label>
            <div class="inline-row">
              <select id="trust" class="input access-select" bind:value={trustInput}>
                {#each [0, 1, 2, 3, 4] as l (l)}<option value={l}>{l}</option>{/each}
              </select>
              <button class="btn btn-secondary" disabled={busy === 'trust'} onclick={handleTrust}>Set</button>
            </div>
          </div>
          <div class="inline-form">
            <label class="field-label" for="tier">Tier</label>
            <div class="inline-row">
              <select id="tier" class="input access-select" bind:value={tierInput}>
                {#each tierOptions as t (t.value)}<option value={t.value}>{t.label}</option>{/each}
              </select>
              <button class="btn btn-secondary" disabled={busy === 'tier'} onclick={handleTier}>Set</button>
            </div>
          </div>
          <div class="inline-form">
            <span class="field-label">Verified</span>
            {#if user.verified_at}
              {#if showUnverify}
                <form class="inline-row" onsubmit={(e) => { e.preventDefault(); handleUnverify(); }}>
                  <input
                    class="input"
                    type="text"
                    bind:value={unverifyReason}
                    placeholder="Reason, sent to the owner (optional)"
                    aria-label="Reason for removing verification"
                  />
                  <button class="btn btn-danger" type="submit" disabled={busy === 'verify'}>Remove</button>
                  <button class="btn btn-ghost" type="button" onclick={() => { showUnverify = false; unverifyReason = ''; }}>Cancel</button>
                </form>
              {:else}
                <div class="inline-row">
                  <span>Since {new Date(user.verified_at).toLocaleDateString()}</span>
                  <button class="btn btn-secondary" type="button" onclick={() => (showUnverify = true)}>Remove</button>
                </div>
              {/if}
            {:else}
              <div class="inline-row">
                <span>{user.is_verified ? 'Through a paid tier' : 'No'}</span>
                <button class="btn btn-secondary" type="button" disabled={busy === 'verify'} onclick={handleVerify}>Verify</button>
              </div>
            {/if}
          </div>
        </div>

        <div class="roles">
          <span class="field-label">Roles</span>
          <div class="roles-list">
            {#each allRoles as role (role.id)}
              {@const assigned = !!roleAssignment(role)}
              <label class="role-chip" class:role-chip-on={assigned}>
                <input
                  type="checkbox"
                  checked={assigned}
                  disabled={busy === 'role:' + role.id}
                  onchange={() => toggleRole(role)}
                />
                <span>{role.name}{#if role.is_system}<span class="role-sys">system</span>{/if}</span>
              </label>
            {/each}
            {#if allRoles.length === 0}<span class="muted">No roles defined.</span>{/if}
          </div>
        </div>
      </section>
    {:else}
      <section class="card sect">
        <p class="muted">This is a remote account. Only the moderation actions above apply; account, security, and access settings are managed by its home instance.</p>
      </section>
    {/if}

    <!-- Notes -->
    <section class="card sect">
      <h2 class="sect-title">Moderation notes</h2>
      <div class="inline-row">
        <input class="input" placeholder="Add an internal note" bind:value={newNote} />
        <button class="btn btn-primary" disabled={!newNote.trim() || busy === 'note'} onclick={handleAddNote}>Add</button>
      </div>
      <ul class="notes-list">
        {#each notes as note (note.id)}
          <li class="note">
            <div class="note-body">
              <span class="note-content">{note.content}</span>
              <span class="note-meta">{note.author?.handle ? '@' + note.author.handle : 'staff'} · {fmtDate(note.created_at)}</span>
            </div>
            <button class="note-del" title="Delete note" disabled={busy === 'note:' + note.id} onclick={() => handleDeleteNote(note.id)}>
              <span class="material-symbols-outlined">close</span>
            </button>
          </li>
        {/each}
        {#if notes.length === 0}<li class="muted">No notes yet.</li>{/if}
      </ul>
    </section>
  {/if}
</div>

{#if showDeleteConfirm && user}
  <div
    class="modal-backdrop"
    role="button"
    tabindex="0"
    onclick={() => (showDeleteConfirm = false)}
    onkeydown={(e) => e.key === 'Escape' && (showDeleteConfirm = false)}
  >
    <div class="modal" role="dialog" aria-modal="true" onclick={(e) => e.stopPropagation()} onkeydown={() => {}} tabindex="-1">
      <h3 class="modal-title">Delete @{user.handle}?</h3>
      <p class="modal-text">
        This permanently deletes the account and purges all of its posts, replies, and media.
        Direct messages stay with the other person and show this user as <em>Deleted User</em>;
        a conversation is dropped only if the other participant is also deleted.
      </p>
      <p class="modal-warn">This action cannot be undone.</p>
      <div class="modal-actions">
        <button class="btn btn-secondary" disabled={busy === 'delete'} onclick={() => (showDeleteConfirm = false)}>Cancel</button>
        <button class="btn btn-danger" disabled={busy === 'delete'} onclick={handleDelete}>
          {busy === 'delete' ? 'Deleting…' : 'Delete permanently'}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .user-detail {
    max-width: 860px;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .back-link {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    text-decoration: none;
    width: fit-content;
  }
  .back-link:hover { color: var(--color-text); }
  .back-link .material-symbols-outlined { font-size: 18px; }

  .detail-error {
    color: var(--color-danger);
    background: var(--color-danger-soft);
    padding: 16px;
    border-radius: 12px;
  }

  .overview {
    display: flex;
    align-items: flex-start;
    gap: var(--space-4);
    padding: var(--space-5);
    flex-wrap: wrap;
  }
  .overview-main { flex: 1; min-width: 200px; }
  .overview-name { margin: 0; font-size: var(--text-xl); font-weight: 700; }
  .overview-handle { margin: 2px 0 10px; color: var(--color-text-secondary); font-size: var(--text-sm); }
  .admin-people {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .admin-person {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
  }

  .admin-person-meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
  }

  .admin-person-name {
    font-weight: 600;
    font-size: var(--text-sm);
    color: var(--color-text);
    text-decoration: none;
  }

  .admin-person-name:hover {
    text-decoration: underline;
  }

  .admin-person-handle {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .sect-count {
    font-weight: 500;
    color: var(--color-text-secondary);
    font-size: var(--text-sm);
  }

  .overview-parent {
    margin: 6px 0 0;
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .ov-domain { color: var(--color-text-tertiary); }

  .pills { display: flex; flex-wrap: wrap; gap: 6px; }
  .pill {
    font-size: 0.7rem; font-weight: 700; padding: 2px 8px; border-radius: 9999px;
    text-transform: uppercase; letter-spacing: 0.03em;
  }
  .pill-neutral { background: var(--color-surface-container-high, rgba(0,0,0,0.06)); color: var(--color-text-secondary); }
  .pill-info { background: var(--color-primary-soft); color: var(--color-primary); }
  .pill-ok { background: var(--color-success-soft); color: var(--color-success); }
  .pill-warn { background: var(--color-warning-soft); color: var(--color-on-warning-soft, var(--color-warning)); }
  .pill-danger { background: var(--color-danger-soft); color: var(--color-danger); }

  .overview-stats {
    display: flex; flex-wrap: wrap; gap: var(--space-4);
    align-content: flex-start;
  }
  .overview-stats > div { display: flex; flex-direction: column; }
  .stat-n { font-weight: 700; font-variant-numeric: tabular-nums; font-size: var(--text-sm); }
  .stat-l { font-size: var(--text-xs); color: var(--color-text-tertiary); }

  .sect { padding: var(--space-5); display: flex; flex-direction: column; gap: var(--space-4); }
  .sect-title { margin: 0; font-size: var(--text-base); font-weight: 700; }

  .btn-row { display: flex; flex-wrap: wrap; gap: 8px; }

  .inline-form { display: flex; flex-direction: column; gap: 6px; }
  .inline-row { display: flex; gap: 8px; align-items: center; }
  .inline-row .input { flex: 1; }
  .field-label { font-size: var(--text-sm); font-weight: 600; color: var(--color-text); }

  .btn-sm { padding: 4px 10px; font-size: var(--text-xs); }

  .pw-box {
    display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
    background: var(--color-surface-container-low, rgba(0,0,0,0.03));
    border: 1px dashed var(--color-border); border-radius: 10px; padding: 12px;
  }
  .pw-code { font-family: ui-monospace, Menlo, monospace; font-size: var(--text-sm); word-break: break-all; }

  .limit-input { width: 170px; max-width: 100%; }
  .access-grid { display: flex; flex-wrap: wrap; gap: var(--space-5); }
  .access-select { min-width: 160px; }

  .roles { display: flex; flex-direction: column; gap: 8px; }
  .roles-list { display: flex; flex-wrap: wrap; gap: 8px; }
  .role-chip {
    display: inline-flex; align-items: center; gap: 6px;
    padding: 6px 12px; border: 1px solid var(--color-border); border-radius: 9999px;
    font-size: var(--text-sm); cursor: pointer;
  }
  .role-chip-on { background: var(--color-primary-soft); border-color: var(--color-primary); color: var(--color-primary); }
  .role-sys { margin-left: 6px; font-size: 0.65rem; color: var(--color-text-tertiary); text-transform: uppercase; }

  .notes-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 8px; }
  .note {
    display: flex; align-items: flex-start; justify-content: space-between; gap: 12px;
    padding: 10px 12px; background: var(--color-surface-container-low, rgba(0,0,0,0.03)); border-radius: 10px;
  }
  .note-body { display: flex; flex-direction: column; gap: 2px; }
  .note-content { font-size: var(--text-sm); }
  .note-meta { font-size: var(--text-xs); color: var(--color-text-tertiary); }
  .note-del { background: transparent; border: none; color: var(--color-text-tertiary); cursor: pointer; }
  .note-del:hover { color: var(--color-danger); }
  .note-del .material-symbols-outlined { font-size: 18px; }

  .muted { color: var(--color-text-tertiary); font-size: var(--text-sm); }

  /* Danger zone */
  .danger-zone { border: 1px solid var(--color-danger); }
  .danger-zone .sect-title { color: var(--color-danger); }
  .danger-body {
    display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap;
  }
  .danger-copy { flex: 1; min-width: 220px; }
  .danger-copy strong { display: block; margin-bottom: 4px; }
  .danger-copy p { margin: 0; font-size: var(--text-sm); color: var(--color-text-secondary); }
  .danger-body .btn-danger { flex-shrink: 0; }

  /* Confirm modal */
  .modal-backdrop {
    position: fixed; inset: 0; z-index: 1000;
    background: rgba(0, 0, 0, 0.5);
    display: flex; align-items: center; justify-content: center; padding: 16px;
  }
  .modal {
    background: var(--color-surface, #fff); border-radius: 14px; padding: 22px;
    max-width: 440px; width: 100%; box-shadow: 0 20px 50px rgba(0, 0, 0, 0.3);
  }
  .modal-title { margin: 0 0 10px; font-size: var(--text-lg); font-weight: 700; }
  .modal-text { margin: 0 0 10px; font-size: var(--text-sm); color: var(--color-text-secondary); }
  .modal-warn { margin: 0 0 18px; font-size: var(--text-sm); font-weight: 600; color: var(--color-danger); }
  .modal-actions { display: flex; justify-content: flex-end; gap: 10px; }

  .visit-profile {
    align-self: flex-start;
    margin-block-start: var(--space-2);
    display: inline-flex;
    align-items: center;
    gap: 6px;
    text-decoration: none;
  }

  .visit-profile .material-symbols-outlined {
    font-size: 16px;
  }

  .content-tabs {
    display: flex;
    gap: var(--space-2);
    flex-wrap: wrap;
    margin-block-end: var(--space-3);
  }

  .content-tab {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 4px 12px;
    border-radius: var(--radius-full, 999px);
    border: 1px solid var(--color-border);
    background: transparent;
    color: var(--color-text-secondary);
    font-size: var(--text-sm, 0.875rem);
    font-weight: 600;
    cursor: pointer;
  }

  .content-tab.on {
    background: var(--color-primary);
    border-color: var(--color-primary);
    color: var(--color-on-primary, #fff);
  }

  .content-tab-n {
    font-variant-numeric: tabular-nums;
    opacity: 0.75;
    font-size: 0.8em;
  }

  .content-list {
    list-style: none;
    margin: 0 0 var(--space-3);
    padding: 0;
    display: flex;
    flex-direction: column;
  }

  .content-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-3);
    padding-block: var(--space-2);
    border-block-end: 1px solid var(--color-border);
  }

  .content-row:last-child {
    border-block-end: none;
  }

  .content-link {
    color: var(--color-text);
    text-decoration: none;
    min-width: 0;
    flex: 1;
  }

  .content-link:hover .content-text {
    text-decoration: underline;
  }

  .content-text {
    display: block;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .content-meta {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    flex-shrink: 0;
    color: var(--color-text-secondary);
    font-size: var(--text-sm, 0.875rem);
  }

  .content-ic {
    font-size: 16px;
  }

  .content-vis {
    text-transform: capitalize;
  }

  .content-date {
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  .content-empty {
    color: var(--color-text-secondary);
    margin: 0 0 var(--space-3);
  }

  .content-note {
    color: var(--color-text-secondary);
    font-size: var(--text-sm, 0.875rem);
    margin: 0;
  }
</style>
