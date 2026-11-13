<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import Modal from '$lib/components/ui/Modal.svelte';
  import {
    getWebhooks, createWebhook, updateWebhook, deleteWebhook, getWebhookDeliveries,
    type WebhookDelivery
  } from '$lib/api/admin.js';
  import type { Webhook } from '$lib/api/types.js';

  // Fallback if the backend didn't return a known_events list (older
  // deployments / tests). The canonical source is Moderation.known_events/0
  // in the backend; whatever it returns overrides this.
  const FALLBACK_EVENTS = [
    'post.created',
    'post.deleted',
    'user.registered',
    'user.suspended',
    'user.unsuspended',
    'report.filed',
    'report.resolved',
    'appeal.filed',
    'moderation.queued',
    'federation.instance_blocked'
  ];

  let knownEvents: string[] = $state(FALLBACK_EVENTS);
  let webhooks: Webhook[] = $state([]);
  let loading = $state(true);

  // Recent-deliveries drawer
  let deliveriesOpen = $state(false);
  let deliveriesTarget: Webhook | null = $state(null);
  let deliveries: WebhookDelivery[] = $state([]);
  let deliveriesLoading = $state(false);

  // Create form
  let createModalOpen = $state(false);
  let newUrl = $state('');
  let newSecret = $state('');
  let newEnabled = $state(true);
  let newEvents: string[] = $state([]);
  let creating = $state(false);

  // Delete confirmation
  let deleteTarget: Webhook | null = $state(null);
  let deleteModalOpen = $state(false);

  onMount(async () => {
    await loadWebhooks();
  });

  async function loadWebhooks() {
    loading = true;
    try {
      const res = await getWebhooks();
      webhooks = res.data;
      if (res.known_events && res.known_events.length > 0) {
        knownEvents = res.known_events;
      }
    } catch {
      addToast('Failed to load webhooks', 'error');
    } finally {
      loading = false;
    }
  }

  async function openDeliveries(webhook: Webhook) {
    deliveriesTarget = webhook;
    deliveriesOpen = true;
    deliveriesLoading = true;
    deliveries = [];
    try {
      deliveries = await getWebhookDeliveries(webhook.id);
    } catch {
      addToast('Failed to load deliveries', 'error');
    } finally {
      deliveriesLoading = false;
    }
  }

  function openCreateModal() {
    newUrl = '';
    newSecret = '';
    newEnabled = true;
    newEvents = [];
    createModalOpen = true;
  }

  function toggleEvent(event: string) {
    if (newEvents.includes(event)) {
      newEvents = newEvents.filter((e) => e !== event);
    } else {
      newEvents = [...newEvents, event];
    }
  }

  async function handleCreate() {
    if (!newUrl.trim() || newEvents.length === 0) return;
    creating = true;
    try {
      const webhook = await createWebhook({
        url: newUrl,
        events: newEvents,
        secret: newSecret || undefined,
        enabled: newEnabled
      });
      webhooks = [...webhooks, webhook];
      createModalOpen = false;
      addToast('Webhook created', 'success');
    } catch {
      addToast('Failed to create webhook', 'error');
    } finally {
      creating = false;
    }
  }

  async function handleToggleEnabled(webhook: Webhook) {
    try {
      const updated = await updateWebhook(webhook.id, { enabled: !webhook.enabled });
      webhooks = webhooks.map((w) => (w.id === webhook.id ? updated : w));
      addToast(`Webhook ${updated.enabled ? 'enabled' : 'disabled'}`, 'success');
    } catch {
      addToast('Failed to update webhook', 'error');
    }
  }

  function confirmDelete(webhook: Webhook) {
    deleteTarget = webhook;
    deleteModalOpen = true;
  }

  async function handleDelete() {
    if (!deleteTarget) return;
    try {
      await deleteWebhook(deleteTarget.id);
      webhooks = webhooks.filter((w) => w.id !== deleteTarget!.id);
      deleteModalOpen = false;
      addToast('Webhook deleted', 'success');
    } catch {
      addToast('Failed to delete webhook', 'error');
    }
  }

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  }
</script>

<svelte:head>
  <title>Webhooks - Admin</title>
</svelte:head>

<div class="webhooks-page">
  <div class="page-header">
    <h1 class="page-title">Webhooks</h1>
    <button class="btn btn-primary" type="button" onclick={openCreateModal}>
      Add Webhook
    </button>
  </div>

  {#if loading}
    <div class="loading-area">
      <div class="skeleton" style="height: 60px"></div>
      <div class="skeleton" style="height: 60px"></div>
    </div>
  {:else}
    <div class="list-items">
      {#each webhooks as webhook (webhook.id)}
        <div class="list-item card">
          <div class="webhook-info">
            <div class="webhook-url">
              <code>{webhook.url}</code>
              <span class="status-badge" class:status-active={webhook.enabled} class:status-suspended={!webhook.enabled}>
                {webhook.enabled ? 'Enabled' : 'Disabled'}
              </span>
            </div>
            <div class="webhook-events">
              {#each webhook.events as event}
                <span class="badge-type">{event}</span>
              {/each}
            </div>
            <div class="webhook-meta text-secondary">
              Created {formatDate(webhook.created_at)}
            </div>
          </div>
          <div class="action-buttons">
            <button
              class="btn btn-sm btn-outline"
              type="button"
              onclick={() => openDeliveries(webhook)}
            >Deliveries</button>
            <button
              class="btn btn-sm btn-outline"
              type="button"
              onclick={() => handleToggleEnabled(webhook)}
            >
              {webhook.enabled ? 'Disable' : 'Enable'}
            </button>
            <button
              class="btn btn-sm btn-danger"
              type="button"
              onclick={() => confirmDelete(webhook)}
            >Delete</button>
          </div>
        </div>
      {:else}
        <p class="empty-text">No webhooks configured</p>
      {/each}
    </div>
  {/if}
</div>

<Modal bind:open={createModalOpen} title="Create Webhook">
  <form onsubmit={(e) => { e.preventDefault(); handleCreate(); }}>
    <div class="form-group">
      <label class="form-label" for="webhook-url">Endpoint URL</label>
      <input id="webhook-url" class="input" type="url" bind:value={newUrl} placeholder="https://example.com/webhook" required />
    </div>

    <div class="form-group">
      <label class="form-label" for="webhook-secret">Secret (optional)</label>
      <input id="webhook-secret" class="input" type="text" bind:value={newSecret} placeholder="Shared secret for signature verification" />
    </div>

    <div class="form-group">
      <label class="form-label">Events</label>
      <div class="events-grid">
        {#each knownEvents as event}
          <label class="checkbox-label">
            <input
              type="checkbox"
              checked={newEvents.includes(event)}
              onchange={() => toggleEvent(event)}
            />
            <span>{event}</span>
          </label>
        {/each}
      </div>
      <p class="hint-text">Subscribe to at least one event. Leave all unchecked to match nothing (webhook will never fire).</p>
    </div>

    <div class="form-group">
      <label class="checkbox-label">
        <input type="checkbox" bind:checked={newEnabled} />
        <span>Enabled</span>
      </label>
    </div>

    <div class="modal-actions">
      <button class="btn btn-ghost" type="button" onclick={() => (createModalOpen = false)}>Cancel</button>
      <button class="btn btn-primary" type="submit" disabled={creating || !newUrl.trim() || newEvents.length === 0}>
        {creating ? 'Creating...' : 'Create Webhook'}
      </button>
    </div>
  </form>
</Modal>

<Modal bind:open={deliveriesOpen} title="Recent deliveries">
  {#if deliveriesTarget}
    <p class="target-url"><code>{deliveriesTarget.url}</code></p>
  {/if}
  {#if deliveriesLoading}
    <div class="skeleton" style="height: 80px"></div>
  {:else if deliveries.length === 0}
    <p class="empty-text">No deliveries yet.</p>
  {:else}
    <div class="deliveries-list">
      {#each deliveries as d (d.id)}
        <div class="delivery-row">
          <span class="delivery-event">{d.event}</span>
          <span class="delivery-status status-{d.status}">{d.status}</span>
          <span class="delivery-code">
            {d.last_status_code ? `HTTP ${d.last_status_code}` : (d.attempts === 0 ? 'queued' : '—')}
          </span>
          <span class="delivery-attempts">{d.attempts} {d.attempts === 1 ? 'try' : 'tries'}</span>
          <span class="delivery-time">{formatDate(d.created_at)}</span>
          {#if d.last_error}
            <span class="delivery-error" title={d.last_error}>{d.last_error}</span>
          {/if}
        </div>
      {/each}
    </div>
  {/if}
  <div class="modal-actions">
    <button class="btn btn-ghost" type="button" onclick={() => (deliveriesOpen = false)}>Close</button>
  </div>
</Modal>

<Modal bind:open={deleteModalOpen} title="Delete Webhook">
  {#if deleteTarget}
    <p class="confirm-text">Are you sure you want to delete the webhook for <strong>{deleteTarget.url}</strong>?</p>
    <div class="modal-actions">
      <button class="btn btn-ghost" type="button" onclick={() => (deleteModalOpen = false)}>Cancel</button>
      <button class="btn btn-danger" type="button" onclick={handleDelete}>Delete</button>
    </div>
  {/if}
</Modal>

<style>
  .webhooks-page {
    max-width: 1100px;
  }

  .page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-block-end: var(--space-6);
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
  }

  .loading-area {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }

  .list-items {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .list-item {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-3);
  }

  .webhook-info {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    min-width: 0;
  }

  .webhook-url {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    flex-wrap: wrap;
  }

  .webhook-url code {
    font-size: var(--text-sm);
    background: var(--color-surface);
    padding: 2px var(--space-2);
    border-radius: var(--radius-sm);
    word-break: break-all;
  }

  .webhook-events {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-1);
  }

  .webhook-meta {
    font-size: var(--text-xs);
  }

  .status-badge {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    text-transform: capitalize;
  }

  .status-active {
    background: var(--color-success-soft);
    color: var(--color-on-success-soft);
  }

  .status-suspended {
    background: var(--color-surface);
    color: var(--color-text-secondary);
  }

  .badge-type {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 2px var(--space-2);
    border-radius: var(--radius-full);
    background: var(--color-info-soft);
    color: var(--color-on-info-soft);
  }

  .action-buttons {
    display: flex;
    gap: var(--space-2);
    flex-shrink: 0;
  }

  .form-group {
    margin-block-end: var(--space-4);
  }

  .form-label {
    display: block;
    font-size: var(--text-sm);
    font-weight: 600;
    margin-block-end: var(--space-1);
    color: var(--color-text);
  }

  .events-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: var(--space-2);
  }

  .checkbox-label {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    cursor: pointer;
  }

  .modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
    margin-block-start: var(--space-4);
  }

  .confirm-text {
    font-size: var(--text-sm);
    margin-block-end: var(--space-2);
  }

  .empty-text {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    text-align: center;
    padding: var(--space-6) 0;
  }

  .hint-text {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    margin-block-start: var(--space-2);
  }

  .target-url {
    font-size: var(--text-sm);
    margin-block-end: var(--space-3);
    word-break: break-all;
  }

  .deliveries-list {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
    max-height: 360px;
    overflow-y: auto;
  }

  .delivery-row {
    display: grid;
    grid-template-columns: minmax(140px, 1fr) auto auto auto auto;
    gap: var(--space-2);
    align-items: center;
    font-size: var(--text-xs);
    padding: var(--space-2);
    border-radius: var(--radius-sm);
    background: var(--color-surface);
  }

  .delivery-event {
    font-weight: 600;
  }

  .delivery-status {
    font-weight: 600;
    padding: 1px var(--space-2);
    border-radius: var(--radius-full);
    text-transform: capitalize;
  }

  .status-delivered {
    background: var(--color-success-soft);
    color: var(--color-on-success-soft);
  }

  .status-pending {
    background: var(--color-warning-soft);
    color: var(--color-on-warning-soft);
  }

  .status-failed {
    background: var(--color-danger-soft);
    color: var(--color-on-danger-soft);
  }

  .delivery-code,
  .delivery-attempts,
  .delivery-time {
    color: var(--color-text-secondary);
    white-space: nowrap;
  }

  .delivery-error {
    grid-column: 1 / -1;
    color: var(--color-danger);
    font-family: var(--font-mono, monospace);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
