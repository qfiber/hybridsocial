<script lang="ts">
  // Opened from the link emailed to a requested new address. Token-only, so
  // it works on any device whether or not the user is signed in there.
  import { page } from '$app/state';
  import { onMount } from 'svelte';
  import BrandMark from '$lib/components/ui/BrandMark.svelte';
  import { api, ApiError } from '$lib/api/client.js';
  import { instanceName } from '$lib/stores/instance.js';
  import { t } from '$lib/stores/i18n.js';

  const token = $derived(page.url.searchParams.get('token') || '');

  let status = $state<'confirming' | 'done' | 'error'>('confirming');
  let errorKey = $state('');

  const errorCopy: Record<string, string> = {
    'account.email_change_expired': 'settings.email_confirm_expired',
    'account.email_taken': 'settings.email_confirm_taken',
  };

  onMount(async () => {
    if (!token) {
      status = 'error';
      errorKey = 'settings.email_confirm_invalid';
      return;
    }
    try {
      await api.post('/api/v1/auth/confirm_email_change', { token });
      status = 'done';
    } catch (err) {
      status = 'error';
      const code = err instanceof ApiError ? err.body?.error : '';
      errorKey = errorCopy[code ?? ''] ?? 'settings.email_confirm_invalid';
    }
  });
</script>

<svelte:head>
  <title>{$t('settings.email_confirm_title')} - {$instanceName}</title>
</svelte:head>

<div class="auth-card">
  <div class="auth-logo">
    <BrandMark size={40} />
  </div>
  {#if status === 'confirming'}
    <h1 class="auth-title" style="text-align: center;">{$t('settings.email_confirm_title')}</h1>
    <p class="auth-subtitle" style="text-align: center;">
      <span class="auth-spinner auth-spinner-dark" aria-hidden="true"></span>
      {$t('settings.email_confirm_working')}
    </p>
  {:else if status === 'done'}
    <h1 class="auth-title" style="text-align: center;">{$t('settings.email_confirm_done_title')}</h1>
    <p class="auth-subtitle" style="text-align: center;">{$t('settings.email_confirm_done')}</p>
    <a href="/settings/account" class="btn btn-primary" style="display:block;text-align:center;">{$t('settings.email_confirm_to_settings')}</a>
  {:else}
    <h1 class="auth-title" style="text-align: center;">{$t('settings.email_confirm_failed_title')}</h1>
    <p class="auth-subtitle" style="text-align: center;" role="alert">{$t(errorKey)}</p>
    <a href="/settings/account" class="btn btn-secondary" style="display:block;text-align:center;">{$t('settings.email_confirm_to_settings')}</a>
  {/if}
</div>
