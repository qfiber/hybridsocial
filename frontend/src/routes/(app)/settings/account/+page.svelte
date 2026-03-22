<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { clearAuth } from '$lib/stores/auth.js';
  import Modal from '$lib/components/ui/Modal.svelte';
  import Spinner from '$lib/components/ui/Spinner.svelte';
  import VerifiedBadge from '$lib/components/ui/VerifiedBadge.svelte';

  let showDeleteModal = $state(false);
  let deleteConfirmText = $state('');
  let deleting = $state(false);
  let exporting = $state(false);
  let exportSuccess = $state(false);
  let importFile: HTMLInputElement | undefined = $state();
  let importing = $state(false);
  let importSuccess = $state(false);
  let error: string | null = $state(null);

  // Verification state
  interface VerificationStatus {
    status: 'none' | 'pending' | 'verified' | 'rejected';
    verified_at: string | null;
  }

  let verification = $state<VerificationStatus>({ status: 'none', verified_at: null });
  let verificationLoading = $state(true);
  let showVerificationForm = $state(false);
  let verificationType = $state<'domain' | 'manual'>('domain');
  let verificationSubmitting = $state(false);
  let verificationError = $state('');
  let verificationSuccess = $state('');

  onMount(async () => {
    try {
      verification = await api.get<VerificationStatus>('/api/v1/verification/status');
    } catch {
      verification = { status: 'none', verified_at: null };
    } finally {
      verificationLoading = false;
    }
  });

  async function submitVerification() {
    verificationSubmitting = true;
    verificationError = '';
    verificationSuccess = '';
    try {
      await api.post('/api/v1/verification/apply', {
        type: verificationType,
        metadata: {},
      });
      verification = { status: 'pending', verified_at: null };
      showVerificationForm = false;
      verificationSuccess = 'Your verification application has been submitted.';
      setTimeout(() => { verificationSuccess = ''; }, 5000);
    } catch (e) {
      verificationError = e instanceof Error ? e.message : 'Failed to submit verification application.';
    } finally {
      verificationSubmitting = false;
    }
  }

  let canDelete = $derived(deleteConfirmText === 'DELETE');

  async function handleExport() {
    exporting = true;
    error = null;
    try {
      const data = await api.get<Blob>('/api/v1/accounts/export');
      // Trigger download
      const url = URL.createObjectURL(data as unknown as Blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'hybridsocial-export.json';
      a.click();
      URL.revokeObjectURL(url);
      exportSuccess = true;
      setTimeout(() => { exportSuccess = false; }, 3000);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to export data';
    } finally {
      exporting = false;
    }
  }

  async function handleImport(e: Event) {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    importing = true;
    error = null;
    try {
      await api.upload('/api/v1/accounts/import', file);
      importSuccess = true;
      setTimeout(() => { importSuccess = false; }, 3000);
    } catch (err) {
      error = err instanceof Error ? err.message : 'Failed to import data';
    } finally {
      importing = false;
    }
  }

  async function handleDeleteAccount() {
    if (!canDelete) return;
    deleting = true;
    error = null;
    try {
      await api.delete('/api/v1/accounts');
      clearAuth();
      window.location.href = '/';
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to delete account';
      deleting = false;
    }
  }
</script>

<div class="settings-sections">
  <!-- Verification -->
  <div class="settings-section">
    <h2 class="section-title">Verification</h2>
    <div class="settings-form">
      {#if verificationLoading}
        <div class="verification-loading">
          <Spinner size={16} />
          <span>Checking verification status...</span>
        </div>
      {:else if verification.status === 'verified'}
        <div class="verification-status verification-verified">
          <VerifiedBadge size="md" />
          <div class="verification-info">
            <span class="verification-label">Verified</span>
            {#if verification.verified_at}
              <span class="verification-date">
                Since {new Date(verification.verified_at).toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' })}
              </span>
            {/if}
          </div>
        </div>
      {:else if verification.status === 'pending'}
        <div class="verification-status verification-pending">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--color-warning)" stroke-width="2" aria-hidden="true">
            <circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>
          </svg>
          <div class="verification-info">
            <span class="verification-label">Your verification is under review</span>
            <span class="verification-date">We'll notify you when a decision has been made.</span>
          </div>
        </div>
      {:else}
        <p class="form-description">
          Get a verified badge on your profile to let others know your identity is confirmed.
        </p>

        {#if verificationSuccess}
          <div class="form-success">{verificationSuccess}</div>
        {/if}

        {#if !showVerificationForm}
          <div class="form-actions">
            <button class="btn btn-outline" type="button" onclick={() => { showVerificationForm = true; }}>
              Apply for Verification
            </button>
          </div>
        {:else}
          <div class="verification-form">
            <div class="form-group">
              <label class="form-label" for="verification-type">Verification type</label>
              <select id="verification-type" class="input" bind:value={verificationType}>
                <option value="domain">Domain verification</option>
                <option value="manual">Manual review</option>
              </select>
            </div>

            {#if verificationType === 'domain'}
              <div class="verification-instructions">
                <p class="instruction-text">To verify via domain ownership:</p>
                <ol class="instruction-steps">
                  <li>Add a TXT record to your domain's DNS settings</li>
                  <li>Set the record value to your profile URL</li>
                  <li>Submit your application and we'll check the record</li>
                </ol>
              </div>
            {:else}
              <div class="verification-instructions">
                <p class="instruction-text">Manual verification is reviewed by our team. Approval is based on account activity and identity confirmation.</p>
              </div>
            {/if}

            {#if verificationError}
              <div class="form-error">{verificationError}</div>
            {/if}

            <div class="verification-form-actions">
              <button class="btn btn-ghost" type="button" onclick={() => { showVerificationForm = false; verificationError = ''; }}>
                Cancel
              </button>
              <button class="btn btn-primary" type="button" onclick={submitVerification} disabled={verificationSubmitting}>
                {#if verificationSubmitting}
                  <Spinner size={16} />
                {/if}
                Submit Application
              </button>
            </div>
          </div>
        {/if}
      {/if}
    </div>
  </div>

  <!-- Export / Import -->
  <div class="settings-section">
    <h2 class="section-title">Data</h2>
    <div class="settings-form">
      <div class="data-row">
        <div class="data-info">
          <span class="data-label">Export your data</span>
          <span class="data-description">Download a copy of your posts, follows, and account data</span>
        </div>
        <button class="btn btn-outline" type="button" onclick={handleExport} disabled={exporting}>
          {#if exporting}
            <Spinner size={16} />
          {/if}
          Export
        </button>
      </div>

      {#if exportSuccess}
        <div class="form-success">Export started. Your download will begin shortly.</div>
      {/if}

      <div class="data-divider"></div>

      <div class="data-row">
        <div class="data-info">
          <span class="data-label">Import follows</span>
          <span class="data-description">Upload a CSV file of accounts to follow</span>
        </div>
        <button class="btn btn-outline" type="button" onclick={() => importFile?.click()} disabled={importing}>
          {#if importing}
            <Spinner size={16} />
          {/if}
          Import CSV
        </button>
        <input bind:this={importFile} type="file" accept=".csv" class="visually-hidden" onchange={handleImport} />
      </div>

      {#if importSuccess}
        <div class="form-success">Import successful. Follows are being processed.</div>
      {/if}
    </div>
  </div>

  <!-- Account Migration -->
  <div class="settings-section">
    <h2 class="section-title">Account Migration</h2>
    <div class="settings-form">
      <p class="form-description">
        Account migration lets you move your followers to a new account on a different server.
        This feature is coming soon.
      </p>
    </div>
  </div>

  <!-- Delete Account -->
  <div class="settings-section danger-section">
    <h2 class="section-title section-title-danger">Delete Account</h2>
    <div class="settings-form">
      <p class="form-description">
        Permanently delete your account and all associated data. This action cannot be undone.
      </p>
      <div class="form-actions">
        <button class="btn btn-danger" type="button" onclick={() => { showDeleteModal = true; }}>
          Delete account
        </button>
      </div>

      {#if error}
        <div class="form-error">{error}</div>
      {/if}
    </div>
  </div>
</div>

<Modal bind:open={showDeleteModal} title="Delete Account">
  <div class="delete-modal-content">
    <div class="delete-warning">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--color-danger)" stroke-width="2" aria-hidden="true">
        <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
        <line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>
      </svg>
      <p>
        Your account will be scheduled for deletion in <strong>30 days</strong>.
        During this period, you can log back in to cancel the deletion.
        After 30 days, all your data will be permanently removed.
      </p>
    </div>

    <div class="form-group">
      <label class="form-label" for="delete-confirm">Type <strong>DELETE</strong> to confirm</label>
      <input
        id="delete-confirm"
        type="text"
        class="input"
        bind:value={deleteConfirmText}
        placeholder="DELETE"
      />
    </div>

    <div class="delete-modal-actions">
      <button class="btn btn-ghost" type="button" onclick={() => { showDeleteModal = false; deleteConfirmText = ''; }}>
        Cancel
      </button>
      <button class="btn btn-danger" type="button" onclick={handleDeleteAccount} disabled={!canDelete || deleting}>
        {#if deleting}
          <Spinner size={16} color="#fff" />
        {/if}
        Delete my account
      </button>
    </div>
  </div>
</Modal>

<style>
  .settings-sections {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .settings-section {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    overflow: hidden;
  }

  .danger-section {
    border-color: var(--color-danger-soft);
  }

  .section-title {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--color-text);
    padding: var(--space-4) var(--space-6);
    border-block-end: 1px solid var(--color-border);
  }

  .section-title-danger {
    color: var(--color-danger);
  }

  .settings-form {
    padding: var(--space-6);
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .form-description {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: var(--line-height);
  }

  .data-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space-4);
  }

  .data-info {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .data-label {
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
  }

  .data-description {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .data-divider {
    height: 1px;
    background: var(--color-border);
  }

  .form-group {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .form-label {
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
  }

  .form-error {
    padding: var(--space-3);
    background: var(--color-danger-soft);
    color: var(--color-danger);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  .form-success {
    padding: var(--space-3);
    background: var(--color-success-soft);
    color: var(--color-success);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
  }

  .form-actions {
    display: flex;
    justify-content: flex-end;
  }

  /* Verification */
  .verification-loading {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
  }

  .verification-status {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    padding: var(--space-3);
    border-radius: var(--radius-md);
  }

  .verification-verified {
    background: var(--color-success-soft);
  }

  .verification-pending {
    background: var(--color-warning-light, rgba(234, 179, 8, 0.1));
  }

  .verification-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .verification-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }

  .verification-date {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
  }

  .verification-form {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .verification-instructions {
    padding: var(--space-3);
    background: var(--color-bg-tertiary);
    border-radius: var(--radius-md);
  }

  .instruction-text {
    font-size: var(--text-sm);
    color: var(--color-text);
    margin-block-end: var(--space-2);
  }

  .instruction-steps {
    padding-inline-start: var(--space-5);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .verification-form-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
  }

  /* Delete modal */
  .delete-modal-content {
    display: flex;
    flex-direction: column;
    gap: var(--space-5);
  }

  .delete-warning {
    display: flex;
    gap: var(--space-3);
    padding: var(--space-4);
    background: var(--color-danger-soft);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    color: var(--color-text);
    line-height: var(--line-height);
  }

  .delete-warning svg {
    flex-shrink: 0;
    margin-block-start: 2px;
  }

  .delete-modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-2);
  }
</style>
