<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getEmailConfig, updateEmailConfig, sendTestEmail } from '$lib/api/admin.js';
  import type { EmailConfig } from '$lib/api/types.js';

  let config: EmailConfig | null = $state(null);
  let loading = $state(true);
  let saving = $state(false);
  let testAddress = $state('');
  let sendingTest = $state(false);

  // Editable fields
  let provider = $state('smtp');
  let fromAddress = $state('');
  let smtpHost = $state('');
  let smtpPort = $state(587);
  let smtpUsername = $state('');
  let smtpSsl = $state(true);

  onMount(async () => {
    try {
      config = await getEmailConfig();
      provider = config.provider;
      fromAddress = config.from_address;
      smtpHost = config.smtp_host || '';
      smtpPort = config.smtp_port || 587;
      smtpUsername = config.smtp_username || '';
      smtpSsl = config.smtp_ssl;
    } catch {
      addToast('Failed to load email config', 'error');
    } finally {
      loading = false;
    }
  });

  async function handleSave() {
    saving = true;
    try {
      config = await updateEmailConfig({
        provider,
        from_address: fromAddress,
        smtp_host: smtpHost || null,
        smtp_port: smtpPort || null,
        smtp_username: smtpUsername || null,
        smtp_ssl: smtpSsl
      });
      addToast('Email settings saved', 'success');
    } catch {
      addToast('Failed to save email settings', 'error');
    } finally {
      saving = false;
    }
  }

  async function handleSendTest() {
    if (!testAddress.trim()) return;
    sendingTest = true;
    try {
      await sendTestEmail(testAddress);
      addToast(`Test email sent to ${testAddress}`, 'success');
    } catch {
      addToast('Failed to send test email', 'error');
    } finally {
      sendingTest = false;
    }
  }
</script>

<svelte:head>
  <title>Email - Admin</title>
</svelte:head>

<div class="email-page">
  <h1 class="page-title">Email Configuration</h1>

  {#if loading}
    <div class="card">
      {#each Array(4) as _}
        <div class="skeleton" style="height: 40px; margin-bottom: 12px"></div>
      {/each}
    </div>
  {:else}
    <section class="card">
      <h2 class="section-title">SMTP Settings</h2>

      <div class="form-fields">
        <div class="form-field">
          <label for="provider" class="field-label">Provider</label>
          <select id="provider" class="input" bind:value={provider}>
            <option value="smtp">SMTP</option>
            <option value="resend">Resend</option>
          </select>
        </div>

        <div class="form-field">
          <label for="from-address" class="field-label">From Address</label>
          <input id="from-address" type="email" class="input" bind:value={fromAddress} placeholder="noreply@example.com" />
        </div>

        {#if provider === 'smtp'}
          <div class="form-field">
            <label for="smtp-host" class="field-label">SMTP Host</label>
            <input id="smtp-host" type="text" class="input" bind:value={smtpHost} placeholder="smtp.example.com" />
          </div>

          <div class="form-row">
            <div class="form-field">
              <label for="smtp-port" class="field-label">Port</label>
              <input id="smtp-port" type="number" class="input" bind:value={smtpPort} />
            </div>
            <div class="form-field">
              <label for="smtp-username" class="field-label">Username</label>
              <input id="smtp-username" type="text" class="input" bind:value={smtpUsername} />
            </div>
          </div>

          <div class="form-field">
            <label class="toggle-label-row">
              <input type="checkbox" bind:checked={smtpSsl} class="toggle-cb" />
              <span>Use SSL/TLS</span>
            </label>
          </div>
        {/if}
      </div>

      <div class="form-actions">
        <button class="btn btn-primary" type="button" disabled={saving} onclick={handleSave}>
          {saving ? 'Saving...' : 'Save Settings'}
        </button>
      </div>
    </section>

    <section class="card">
      <h2 class="section-title">Test Email</h2>
      <p class="test-description">Send a test email to verify your configuration.</p>
      <form class="test-form" onsubmit={(e) => { e.preventDefault(); handleSendTest(); }}>
        <input type="email" class="input" bind:value={testAddress} placeholder="test@example.com" required />
        <button class="btn btn-outline" type="submit" disabled={sendingTest}>
          {sendingTest ? 'Sending...' : 'Send Test'}
        </button>
      </form>
    </section>
  {/if}
</div>

<style>
  .email-page {
    max-width: 700px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-6);
  }

  .section-title {
    font-size: var(--text-lg);
    font-weight: 600;
    margin-block-end: var(--space-4);
  }

  .form-fields {
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .form-field {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .field-label {
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
  }

  .form-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--space-3);
  }

  .toggle-label-row {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-sm);
    cursor: pointer;
  }

  .toggle-cb {
    accent-color: var(--color-primary);
  }

  .form-actions {
    margin-block-start: var(--space-4);
    padding-block-start: var(--space-3);
    border-block-start: 1px solid var(--color-border);
    display: flex;
    justify-content: flex-end;
  }

  .card + .card {
    margin-block-start: var(--space-4);
  }

  .test-description {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    margin-block-end: var(--space-3);
  }

  .test-form {
    display: flex;
    gap: var(--space-2);
  }

  .test-form .input {
    flex: 1;
  }
</style>
