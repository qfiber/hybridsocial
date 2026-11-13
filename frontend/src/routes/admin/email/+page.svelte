<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import {
    getEmailConfig,
    updateEmailConfig,
    sendTestEmail,
    getAdminSettings,
    updateAdminSettings
  } from '$lib/api/admin.js';
  import { t } from '$lib/stores/i18n.js';
  import type { EmailConfig } from '$lib/api/types.js';
  import Tabs from '$lib/components/ui/Tabs.svelte';
  import EmailTemplatesPanel from '$lib/components/admin/EmailTemplatesPanel.svelte';

  // Two related concerns lived on separate routes (/admin/email and
  // /admin/email-templates) — fold them into one tabbed Email Settings
  // page so the SMTP config and the per-message templates aren't a
  // sidebar click apart.
  const tabs = [
    { id: 'server', label: 'Server' },
    { id: 'templates', label: 'Templates' }
  ];
  let activeTab = $state('server');

  let config: EmailConfig | null = $state(null);
  let loading = $state(true);
  let saving = $state(false);
  let testAddress = $state('');
  let sendingTest = $state(false);

  // Instance-wide switch for emailing staff about new reports.
  let reportEmailsEnabled = $state(false);
  let reportEmailThrottle = $state(60);
  let reportEmailsLoaded = $state(false);
  let savingReportEmails = $state(false);

  async function loadReportEmailSettings() {
    try {
      const byKey = new Map((await getAdminSettings()).map((r) => [r.key, r.value as unknown]));
      const enabled = byKey.get('report_email_notifications_enabled');
      reportEmailsEnabled = enabled === true || enabled === 'true';
      const throttle = Number(byKey.get('report_email_throttle_seconds') ?? 60);
      reportEmailThrottle = Number.isFinite(throttle) && throttle >= 0 ? throttle : 60;
      reportEmailsLoaded = true;
    } catch {
      addToast($t('admin.email.report_emails.load_failed'), 'error');
    }
  }

  async function saveReportEmailSettings() {
    if (savingReportEmails) return;
    savingReportEmails = true;
    try {
      await updateAdminSettings([
        { key: 'report_email_notifications_enabled', value: reportEmailsEnabled },
        { key: 'report_email_throttle_seconds', value: Math.max(0, Math.round(reportEmailThrottle)) }
      ]);
      addToast($t('admin.email.report_emails.saved'), 'success');
    } catch {
      addToast($t('admin.email.report_emails.save_failed'), 'error');
    } finally {
      savingReportEmails = false;
    }
  }

  // Editable fields
  let provider = $state('smtp');
  let fromAddress = $state('');
  let smtpHost = $state('');
  let smtpPort = $state(587);
  let smtpUsername = $state('');
  let smtpSsl = $state(true);

  // When the transport is pinned by the server environment (RESEND_API_KEY
  // / SMTP_* in .env), the provider + connection fields are read-only —
  // the backend ignores DB values in that case.
  let envOverride = $state(false);
  let envProvider = $state<string | null>(null);

  const providerLabel = (p: string | null | undefined) =>
    p === 'resend' ? 'Resend' : p === 'smtp' ? 'SMTP' : (p ?? 'unknown');

  onMount(async () => {
    loadReportEmailSettings();
    try {
      config = await getEmailConfig();
      provider = config.provider;
      fromAddress = config.from_address;
      smtpHost = config.smtp_host || '';
      smtpPort = config.smtp_port || 587;
      smtpUsername = config.smtp_username || '';
      smtpSsl = config.smtp_ssl;
      envOverride = config.env_override ?? false;
      envProvider = config.env_provider ?? null;
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
  <title>Email Settings - Admin</title>
</svelte:head>

<div class="email-page">
  <h1 class="page-title">Email Settings</h1>

  <Tabs {tabs} bind:active={activeTab}>
    {#if activeTab === 'server'}
      <div class="server-tab">
      {#if loading}
        <div class="card">
          {#each Array(4) as _}
            <div class="skeleton" style="height: 40px; margin-bottom: 12px"></div>
          {/each}
        </div>
      {:else}
    <section class="card">
      <h2 class="section-title">SMTP Settings</h2>

      {#if envOverride}
        <div class="env-notice" role="status">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <rect x="3" y="11" width="18" height="11" rx="2" ry="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
          <div>
            <strong>Managed by the server environment.</strong>
            Email is sent via <strong>{providerLabel(envProvider)}</strong>, configured through your server's
            environment variables ({envProvider === 'resend' ? 'RESEND_API_KEY' : 'SMTP_*'} in <code>.env</code>).
            The provider and connection settings below are read-only and can't be changed here.
            Update your <code>.env</code> and restart to change the transport. The From address and templates
            are still editable.
          </div>
        </div>
      {/if}

      <div class="form-fields">
        <div class="form-field">
          <label for="provider" class="field-label">Provider</label>
          <select id="provider" class="input" bind:value={provider} disabled={envOverride}>
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
            <input id="smtp-host" type="text" class="input" bind:value={smtpHost} placeholder="smtp.example.com" disabled={envOverride} />
          </div>

          <div class="form-row">
            <div class="form-field">
              <label for="smtp-port" class="field-label">Port</label>
              <input id="smtp-port" type="number" class="input" bind:value={smtpPort} disabled={envOverride} />
            </div>
            <div class="form-field">
              <label for="smtp-username" class="field-label">Username</label>
              <input id="smtp-username" type="text" class="input" bind:value={smtpUsername} disabled={envOverride} />
            </div>
          </div>

          <div class="form-field">
            <label class="toggle-label-row">
              <input type="checkbox" bind:checked={smtpSsl} class="toggle-cb" disabled={envOverride} />
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

    {#if reportEmailsLoaded}
      <section class="card">
        <h2 class="section-title">{$t('admin.email.report_emails.title')}</h2>
        <form class="form-fields" onsubmit={(e) => { e.preventDefault(); saveReportEmailSettings(); }}>
          <div class="form-field">
            <label class="toggle-label-row">
              <input type="checkbox" bind:checked={reportEmailsEnabled} class="toggle-cb" />
              <span>{$t('admin.email.report_emails.toggle')}</span>
            </label>
            <p class="field-hint">{$t('admin.email.report_emails.toggle_hint')}</p>
          </div>
          <div class="form-field">
            <label for="report-email-throttle" class="field-label">{$t('admin.email.report_emails.throttle')}</label>
            <input
              id="report-email-throttle"
              class="input"
              type="number"
              min="0"
              step="1"
              bind:value={reportEmailThrottle}
              disabled={!reportEmailsEnabled}
            />
            <p class="field-hint">{$t('admin.email.report_emails.throttle_hint')}</p>
          </div>
          <button class="btn btn-primary" type="submit" disabled={savingReportEmails}>
            {$t('admin.email.report_emails.save')}
          </button>
        </form>
      </section>
    {/if}

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
    {:else if activeTab === 'templates'}
      <EmailTemplatesPanel />
    {/if}
  </Tabs>
</div>

<style>
  /* Drop the page-level max-width so the Templates tab (which wants
     to lay out a 240/1fr/420 grid) can actually use the column. The
     Server tab's narrow form re-applies a max-width on its own
     section so it doesn't stretch into a single 1400px-wide row. */
  .email-page {
    width: 100%;
  }

  .server-tab {
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

  .env-notice {
    display: flex;
    gap: var(--space-3);
    align-items: flex-start;
    padding: var(--space-3) var(--space-4);
    margin-block-end: var(--space-4);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg, 0.75rem);
    background: var(--color-surface-container-low);
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: var(--line-height, 1.5);
  }

  .env-notice svg {
    flex-shrink: 0;
    margin-block-start: 2px;
    color: var(--color-primary);
  }

  .env-notice strong {
    color: var(--color-text);
    font-weight: 600;
  }

  .env-notice code {
    font-family: var(--font-mono, monospace);
    font-size: 0.85em;
    background: var(--color-surface-container-high);
    padding: 1px 5px;
    border-radius: 4px;
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

  .field-hint {
    margin-block-start: var(--space-1);
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
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
