<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getAnnouncements, createAnnouncement, deleteAnnouncement } from '$lib/api/admin.js';
  import type { Announcement } from '$lib/api/types.js';

  let announcements: Announcement[] = $state([]);
  let loading = $state(true);
  let creating = $state(false);

  let newContent = $state('');
  let newStartsAt = $state('');
  let newEndsAt = $state('');

  onMount(async () => {
    try {
      announcements = await getAnnouncements();
    } catch {
      addToast('Failed to load announcements', 'error');
    } finally {
      loading = false;
    }
  });

  async function handleCreate() {
    if (!newContent.trim()) return;
    creating = true;
    try {
      const announcement = await createAnnouncement({
        content: newContent,
        starts_at: newStartsAt || undefined,
        ends_at: newEndsAt || undefined
      });
      announcements = [announcement, ...announcements];
      newContent = '';
      newStartsAt = '';
      newEndsAt = '';
      addToast('Announcement created', 'success');
    } catch {
      addToast('Failed to create announcement', 'error');
    } finally {
      creating = false;
    }
  }

  async function handleDelete(id: string) {
    try {
      await deleteAnnouncement(id);
      announcements = announcements.filter((a) => a.id !== id);
      addToast('Announcement deleted', 'success');
    } catch {
      addToast('Failed to delete announcement', 'error');
    }
  }

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  }

  function isActive(a: Announcement): boolean {
    const now = new Date();
    if (a.starts_at && new Date(a.starts_at) > now) return false;
    if (a.ends_at && new Date(a.ends_at) < now) return false;
    return a.published;
  }
</script>

<svelte:head>
  <title>Announcements - Admin</title>
</svelte:head>

<div class="announcements-page">
  <h1 class="page-title">Announcements</h1>

  <section class="card create-section">
    <h2 class="section-title">Create Announcement</h2>
    <form class="create-form" onsubmit={(e) => { e.preventDefault(); handleCreate(); }}>
      <div class="form-field">
        <label for="content" class="field-label">Content</label>
        <textarea
          id="content"
          class="textarea"
          rows="4"
          bind:value={newContent}
          placeholder="Write your announcement..."
          required
        ></textarea>
      </div>
      <div class="date-row">
        <div class="form-field">
          <label for="starts-at" class="field-label">Start Date (optional)</label>
          <input id="starts-at" type="datetime-local" class="input" bind:value={newStartsAt} />
        </div>
        <div class="form-field">
          <label for="ends-at" class="field-label">End Date (optional)</label>
          <input id="ends-at" type="datetime-local" class="input" bind:value={newEndsAt} />
        </div>
      </div>
      <button class="btn btn-primary" type="submit" disabled={creating || !newContent.trim()}>
        {creating ? 'Creating...' : 'Create Announcement'}
      </button>
    </form>
  </section>

  <section class="card">
    <h2 class="section-title">All Announcements</h2>

    {#if loading}
      {#each Array(3) as _}
        <div class="skeleton" style="height: 80px; margin-bottom: 8px"></div>
      {/each}
    {:else if announcements.length === 0}
      <p class="empty-text">No announcements</p>
    {:else}
      <div class="announcement-list">
        {#each announcements as announcement (announcement.id)}
          <div class="announcement-item" class:active={isActive(announcement)}>
            <div class="announcement-content">
              <p class="announcement-text">{announcement.content}</p>
              <div class="announcement-meta">
                <span class="announcement-status" class:status-active={isActive(announcement)} class:status-inactive={!isActive(announcement)}>
                  {isActive(announcement) ? 'Active' : 'Inactive'}
                </span>
                <span class="announcement-date">Created {formatDate(announcement.created_at)}</span>
                {#if announcement.starts_at}
                  <span class="announcement-date">Starts {formatDate(announcement.starts_at)}</span>
                {/if}
                {#if announcement.ends_at}
                  <span class="announcement-date">Ends {formatDate(announcement.ends_at)}</span>
                {/if}
              </div>
            </div>
            <button
              class="btn btn-sm btn-danger"
              type="button"
              onclick={() => handleDelete(announcement.id)}
            >Delete</button>
          </div>
        {/each}
      </div>
    {/if}
  </section>
</div>

<style>
  .announcements-page {
    max-width: 800px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-6);
  }

  .section-title {
    font-size: var(--text-lg);
    font-weight: 600;
    margin-block-end: var(--space-3);
  }

  .create-section {
    margin-block-end: var(--space-4);
  }

  .create-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    align-items: flex-start;
  }

  .form-field {
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .field-label {
    font-size: var(--text-sm);
    font-weight: 500;
  }

  .date-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--space-3);
    width: 100%;
  }

  .announcement-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .announcement-item {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-3);
    padding: var(--space-4);
    background: var(--color-surface);
    border-radius: var(--radius-md);
    border-inline-start: 3px solid var(--color-border);
  }

  .announcement-item.active {
    border-inline-start-color: var(--color-primary);
  }

  .announcement-content {
    flex: 1;
    min-width: 0;
  }

  .announcement-text {
    font-size: var(--text-sm);
    line-height: 1.6;
    margin-block-end: var(--space-2);
  }

  .announcement-meta {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    flex-wrap: wrap;
  }

  .announcement-status {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
  }

  .status-active {
    background: var(--color-success-soft);
    color: #166534;
  }

  .status-inactive {
    background: var(--color-surface);
    color: var(--color-text-secondary);
    border: 1px solid var(--color-border);
  }

  .announcement-date {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .empty-text {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    text-align: center;
    padding: var(--space-6) 0;
  }

  @media (max-width: 768px) {
    .date-row {
      grid-template-columns: 1fr;
    }
  }
</style>
