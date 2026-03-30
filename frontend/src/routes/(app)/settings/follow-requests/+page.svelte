<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface FollowRequest {
    id: string;
    handle: string;
    display_name: string;
    avatar_url: string | null;
    created_at: string;
  }

  let requests: FollowRequest[] = $state([]);
  let loading = $state(true);
  let processingId: string | null = $state(null);

  onMount(async () => {
    try {
      const res = await api.get<{ data: FollowRequest[] }>('/api/v1/accounts/follow_requests');
      requests = res.data;
    } catch {
      addToast('Failed to load follow requests', 'error');
    } finally {
      loading = false;
    }
  });

  async function handleApprove(request: FollowRequest) {
    processingId = request.id;
    try {
      await api.post(`/api/v1/follow_requests/${request.id}/authorize`);
      requests = requests.filter(r => r.id !== request.id);
      addToast(`Approved @${request.handle}`, 'success');
    } catch {
      addToast('Failed to approve follow request', 'error');
    } finally {
      processingId = null;
    }
  }

  async function handleReject(request: FollowRequest) {
    processingId = request.id;
    try {
      await api.post(`/api/v1/follow_requests/${request.id}/reject`);
      requests = requests.filter(r => r.id !== request.id);
      addToast(`Rejected @${request.handle}`, 'success');
    } catch {
      addToast('Failed to reject follow request', 'error');
    } finally {
      processingId = null;
    }
  }

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    });
  }
</script>

<div class="stitch-settings">
  <div class="stitch-settings-header">
    <h1 class="stitch-settings-title">Follow Requests</h1>
    <p class="stitch-settings-subtitle">Approve or reject pending follow requests</p>
  </div>

  <section class="stitch-section">
    <div class="stitch-section-heading">
      <span class="stitch-section-icon" aria-hidden="true">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="8.5" cy="7" r="4"/><polyline points="17 11 19 13 23 9"/>
        </svg>
      </span>
      <h2 class="stitch-section-title">Pending Requests</h2>
    </div>

    <div class="stitch-section-content">
      <div class="stitch-form">
        <p class="stitch-description">
          These people have requested to follow your account. Approve to let them see your posts, or reject to deny the request.
        </p>

        {#if loading}
          <div class="stitch-loading"><Spinner size={20} /> Loading follow requests...</div>
        {:else if requests.length === 0}
          <p class="stitch-description">No pending follow requests.</p>
        {:else}
          <div class="stitch-list">
            {#each requests as request (request.id)}
              <div class="stitch-list-item">
                <div class="stitch-list-avatar">
                  {#if request.avatar_url}
                    <img src={request.avatar_url} alt="" class="stitch-avatar-img" />
                  {:else}
                    <div class="stitch-avatar-placeholder">
                      {(request.display_name || request.handle).charAt(0).toUpperCase()}
                    </div>
                  {/if}
                </div>
                <div class="stitch-list-info">
                  <div class="stitch-list-name">{request.display_name || request.handle}</div>
                  <div class="stitch-list-meta">
                    <span class="stitch-list-handle">@{request.handle}</span>
                    <span class="stitch-list-dot">&middot;</span>
                    <span>{formatDate(request.created_at)}</span>
                  </div>
                </div>
                <div class="stitch-request-actions">
                  <button
                    class="stitch-btn-approve"
                    onclick={() => handleApprove(request)}
                    disabled={processingId === request.id}
                    title="Approve"
                  >
                    {#if processingId === request.id}
                      <Spinner size={14} color="#fff" />
                    {:else}
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                        <polyline points="20 6 9 17 4 12"/>
                      </svg>
                    {/if}
                  </button>
                  <button
                    class="stitch-btn-reject"
                    onclick={() => handleReject(request)}
                    disabled={processingId === request.id}
                    title="Reject"
                  >
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                      <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
                    </svg>
                  </button>
                </div>
              </div>
            {/each}
          </div>
        {/if}
      </div>
    </div>
  </section>
</div>

<style>
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

  .stitch-section-content {
    background: #f2f4f5;
    border-radius: 16px;
    overflow: hidden;
  }

  .stitch-form {
    padding: 24px 32px 32px;
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .stitch-description {
    font-size: 0.875rem;
    color: #6b7280;
    line-height: 1.5;
  }

  .stitch-loading {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 0.875rem;
    color: #6b7280;
  }

  .stitch-list {
    display: flex;
    flex-direction: column;
    gap: 1px;
    background: rgba(0, 0, 0, 0.06);
    border-radius: 12px;
    overflow: hidden;
  }

  .stitch-list-item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 16px;
    background: #e6e8e9;
  }

  .stitch-list-avatar {
    flex-shrink: 0;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    overflow: hidden;
  }

  .stitch-avatar-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .stitch-avatar-placeholder {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--color-primary);
    color: white;
    font-weight: 700;
    font-size: 1rem;
  }

  .stitch-list-info {
    flex: 1;
    min-width: 0;
  }

  .stitch-list-name {
    font-size: 0.875rem;
    font-weight: 500;
    color: var(--color-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .stitch-list-meta {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: 0.75rem;
    color: #9ca3af;
  }

  .stitch-list-handle {
    font-size: 0.75rem;
    color: #9ca3af;
  }

  .stitch-list-dot {
    font-size: 0.75rem;
  }

  .stitch-request-actions {
    display: flex;
    gap: 8px;
    flex-shrink: 0;
  }

  .stitch-btn-approve {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    background: #16a34a;
    color: white;
    border: none;
    border-radius: 50%;
    cursor: pointer;
    transition: background-color 0.15s ease, transform 0.1s ease;
  }

  .stitch-btn-approve:hover:not(:disabled) {
    background: #15803d;
    transform: scale(1.05);
  }

  .stitch-btn-approve:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .stitch-btn-reject {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    background: #dc2626;
    color: white;
    border: none;
    border-radius: 50%;
    cursor: pointer;
    transition: background-color 0.15s ease, transform 0.1s ease;
  }

  .stitch-btn-reject:hover:not(:disabled) {
    background: #b91c1c;
    transform: scale(1.05);
  }

  .stitch-btn-reject:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  @media (max-width: 640px) {
    .stitch-settings-title {
      font-size: 1.5rem;
    }

    .stitch-form {
      padding: 20px;
    }
  }
</style>
