<script lang="ts">
  import Modal from '$lib/components/ui/Modal.svelte';
  import Avatar from '$lib/components/ui/Avatar.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import { addToast } from '$lib/stores/toast.js';
  import {
    updatePage,
    deletePage,
    getPageRoles,
    addPageRole,
    removePageRole,
    invitePageManager,
    listPageInvitesSent,
    cancelPageInvite,
    type PageRole,
    type PageInvite,
  } from '$lib/api/pages.js';
  import { search } from '$lib/api/search.js';
  import { uploadMedia } from '$lib/api/media.js';
  import { displayAcct, type Identity } from '$lib/api/types.js';

  type AssignableRole = 'admin' | 'editor' | 'moderator';

  let {
    open = $bindable(false),
    page = $bindable(),
    onclose,
    ondeleted,
  }: {
    open?: boolean;
    page: Record<string, unknown> | null;
    onclose?: () => void;
    ondeleted?: () => void;
  } = $props();

  let section = $state<'general' | 'managers' | 'invites' | 'danger'>('general');

  // General — local form copies so cancel-without-save is a real cancel.
  let displayName = $state('');
  let bio = $state('');
  let avatarUrl = $state('');
  let headerUrl = $state('');
  let website = $state('');
  let category = $state('');
  let saving = $state(false);
  let avatarUploading = $state(false);
  let headerUploading = $state(false);

  // Managers
  let roles = $state<PageRole[]>([]);
  let rolesLoading = $state(false);
  let pendingInvites = $state<PageInvite[]>([]);
  let invitesLoading = $state(false);

  // Invite search
  let inviteQuery = $state('');
  let inviteResults = $state<Identity[]>([]);
  let inviteSearching = $state(false);
  let inviteSendingId = $state<string | null>(null);
  let inviteTimeout: ReturnType<typeof setTimeout> | undefined;

  // Danger zone
  let deleteConfirmation = $state('');
  let deleting = $state(false);

  let pageId = $derived(
    typeof page?.id === 'string' ? (page!.id as string) : '',
  );
  let pageDisplayName = $derived(
    typeof page?.display_name === 'string' && page!.display_name
      ? (page!.display_name as string)
      : typeof page?.handle === 'string'
        ? (page!.handle as string)
        : '',
  );
  let viewerRole = $derived(
    typeof page?.viewer_role === 'string' ? (page!.viewer_role as string) : '',
  );
  // Only the page's own owner sees Danger Zone. Instance-staff takedowns go
  // through AdminProfileActions on the page header, not this settings modal.
  let isOwner = $derived(viewerRole === 'owner');
  let canDelete = $derived(isOwner);

  $effect(() => {
    if (!page) return;
    displayName = (page.display_name as string) || '';
    bio = (page.bio as string) || '';
    avatarUrl = (page.avatar_url as string) || '';
    headerUrl = (page.header_url as string) || '';
    const org = page.organization as Record<string, unknown> | null;
    website = (org?.website as string) || (page.website as string) || '';
    category = (org?.category as string) || (page.category as string) || '';
  });

  $effect(() => {
    if (open) section = 'general';
  });

  $effect(() => {
    if (!open || !pageId) return;
    if (section === 'managers') {
      void loadRoles();
    }
    if (section === 'invites') {
      void loadRoles();
      void loadInvites();
    }
  });

  async function loadRoles() {
    rolesLoading = true;
    try {
      roles = await getPageRoles(pageId);
    } catch {
      addToast('Failed to load managers', 'error');
    } finally {
      rolesLoading = false;
    }
  }

  async function loadInvites() {
    invitesLoading = true;
    try {
      pendingInvites = await listPageInvitesSent(pageId);
    } catch {
      addToast('Failed to load invites', 'error');
    } finally {
      invitesLoading = false;
    }
  }

  async function saveGeneral() {
    saving = true;
    try {
      const updated = await updatePage(pageId, {
        display_name: displayName.trim() || null,
        bio: bio.trim() || null,
        avatar_url: avatarUrl.trim() || null,
        header_url: headerUrl.trim() || null,
        website: website.trim() || null,
        category: category.trim() || null,
      });
      page = { ...page, ...updated };
      addToast('Page updated', 'success');
    } catch (err) {
      const msg = (err as { body?: { message?: string }; message?: string })?.body?.message
        || (err as { message?: string })?.message
        || 'Could not save changes';
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

  async function handleRoleChange(role: PageRole, newRole: AssignableRole) {
    try {
      // No role-update endpoint — revoke + grant in sequence.
      await removePageRole(pageId, role.id);
      const created = await addPageRole(pageId, role.identity_id, newRole);
      roles = roles.map((r) => (r.id === role.id ? created : r));
      addToast(`Role updated to ${newRole}`, 'success');
    } catch {
      addToast('Failed to update role', 'error');
      void loadRoles();
    }
  }

  async function handleRemoveManager(role: PageRole) {
    if (!confirm('Remove this manager from the page?')) return;
    try {
      await removePageRole(pageId, role.id);
      roles = roles.filter((r) => r.id !== role.id);
      addToast('Manager removed', 'success');
    } catch {
      addToast('Failed to remove manager', 'error');
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
      await invitePageManager(pageId, account.id);
      inviteResults = inviteResults.filter((a) => a.id !== account.id);
      addToast(`Invited @${displayAcct(account)}`, 'success');
      void loadInvites();
    } catch (err) {
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
      await cancelPageInvite(pageId, inviteId);
      pendingInvites = pendingInvites.filter((i) => i.id !== inviteId);
      addToast('Invite cancelled', 'success');
    } catch {
      addToast('Could not cancel invite', 'error');
    }
  }

  async function handleDelete() {
    if (deleteConfirmation !== pageDisplayName) return;
    deleting = true;
    try {
      await deletePage(pageId);
      open = false;
      ondeleted?.();
    } catch {
      addToast('Could not delete page', 'error');
      deleting = false;
    }
  }

  function roleLabel(role: string): string {
    switch (role) {
      case 'owner': return 'Owner';
      case 'admin': return 'Admin';
      case 'editor': return 'Editor';
      case 'moderator': return 'Moderator';
      default: return role;
    }
  }
</script>

<Modal bind:open title="Manage page" size="lg" {onclose}>
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
        class:sidebar-item-active={section === 'managers'}
        onclick={() => (section = 'managers')}
      >
        <span class="material-symbols-outlined">manage_accounts</span>
        Managers
      </button>
      <button
        type="button"
        class="sidebar-item"
        class:sidebar-item-active={section === 'invites'}
        onclick={() => (section = 'invites')}
      >
        <span class="material-symbols-outlined">person_add</span>
        Invites
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
        <p class="section-help">Identity, look, and metadata for this page.</p>

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
          <label for="page-mgr-name" class="form-label">Display name</label>
          <input id="page-mgr-name" type="text" class="input" bind:value={displayName} />
        </div>

        <div class="form-group">
          <label for="page-mgr-bio" class="form-label">Bio</label>
          <textarea id="page-mgr-bio" class="input" rows="3" bind:value={bio}></textarea>
        </div>

        <div class="form-row">
          <div class="form-group">
            <label for="page-mgr-website" class="form-label">Website</label>
            <input id="page-mgr-website" type="url" class="input" bind:value={website} />
          </div>
          <div class="form-group">
            <label for="page-mgr-category" class="form-label">Category</label>
            <input id="page-mgr-category" type="text" class="input" bind:value={category} />
          </div>
        </div>

        <div class="section-actions">
          <button class="btn btn-primary" type="button" disabled={saving} onclick={saveGeneral}>
            {saving ? 'Saving…' : 'Save changes'}
          </button>
        </div>
      {:else if section === 'managers'}
        <h3 class="section-title">Managers</h3>
        <p class="section-help">
          People who can edit this page. Admins can grant roles, editors can publish, moderators can moderate.
        </p>

        {#if rolesLoading}
          <div class="section-loading"><Spinner /></div>
        {:else if roles.length === 0}
          <p class="section-empty">No managers yet. Use the Invites section to add some.</p>
        {:else}
          <ul class="people-list">
            {#each roles as r (r.id)}
              <li class="people-row">
                <Avatar
                  src={r.identity?.avatar_url || null}
                  name={r.identity?.display_name || r.identity?.handle || 'Manager'}
                  size="sm"
                />
                <div class="people-meta">
                  <span class="people-name">
                    {r.identity?.display_name || r.identity?.handle || 'Manager'}
                  </span>
                  {#if r.identity?.handle}
                    <span class="people-handle">@{displayAcct(r.identity)}</span>
                  {/if}
                </div>
                <span class="role-badge role-{r.role}">{roleLabel(r.role)}</span>
                {#if r.role !== 'owner'}
                  <div class="row-actions">
                    <select
                      class="input input-compact"
                      value={r.role}
                      onchange={(e) =>
                        handleRoleChange(
                          r,
                          (e.currentTarget as HTMLSelectElement).value as AssignableRole,
                        )}
                    >
                      <option value="admin">Admin</option>
                      <option value="editor">Editor</option>
                      <option value="moderator">Moderator</option>
                    </select>
                    <button
                      type="button"
                      class="btn btn-sm btn-danger-outline"
                      onclick={() => handleRemoveManager(r)}
                    >
                      Remove
                    </button>
                  </div>
                {/if}
              </li>
            {/each}
          </ul>
        {/if}
      {:else if section === 'invites'}
        <h3 class="section-title">Invite people</h3>
        <p class="section-help">Search for someone, send an invite, or cancel a pending one.</p>

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
        {:else if pendingInvites.length === 0}
          <p class="section-empty">No pending invites.</p>
        {:else}
          <ul class="people-list">
            {#each pendingInvites as inv (inv.id)}
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
      {:else if section === 'danger'}
        <h3 class="section-title section-title-danger">Danger zone</h3>
        <p class="section-help">
          Deleting the page removes its posts, manager assignments, and any pending invites.
          This cannot be undone.
        </p>

        <div class="danger-card">
          <p class="danger-text">
            Type <strong>{pageDisplayName}</strong> to confirm.
          </p>
          <input
            type="text"
            class="input"
            placeholder={pageDisplayName}
            bind:value={deleteConfirmation}
          />
          <button
            class="btn btn-danger"
            type="button"
            disabled={deleting || deleteConfirmation !== pageDisplayName}
            onclick={handleDelete}
          >
            {deleting ? 'Deleting…' : 'Delete page'}
          </button>
        </div>
      {/if}
    </section>
  </div>
</Modal>

<style>
  /* Shared styles with GroupManageModal — kept inline to avoid coupling
     the two components through a shared stylesheet at this stage. If a
     third manage-modal lands, lift these into a shared module. */
  .manage-shell {
    display: grid;
    grid-template-columns: 200px 1fr;
    min-height: 480px;
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
    background: var(--color-success-soft, color-mix(in srgb, var(--color-success) 18%, transparent));
    color: var(--color-success);
  }

  .role-admin {
    background: var(--color-primary-soft);
    color: var(--color-primary);
  }

  .role-editor {
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

  .input-compact {
    padding: 4px 8px;
    font-size: var(--text-sm);
    height: auto;
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
