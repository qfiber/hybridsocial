<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getTranslationConfig, updateTranslationConfig } from '$lib/api/admin.js';
  import type { TranslationConfig } from '$lib/api/types.js';

  let loading = $state(true);
  let saving = $state(false);

  // Editable fields
  let backend = $state('none');
  let apiUrl = $state('https://libretranslate.com');
  let apiKey = $state('');

  onMount(async () => {
    try {
      const config = await getTranslationConfig();
      backend = config.backend || 'none';
      apiUrl = config.api_url || 'https://libretranslate.com';
      apiKey = config.api_key || '';
    } catch {
      addToast('Failed to load translation settings', 'error');
    } finally {
      loading = false;
    }
  });

  async function handleSave() {
    saving = true;
    try {
      const saved = await updateTranslationConfig({
        backend,
        api_url: apiUrl,
        // Don't resend the masked placeholder — the backend keeps the stored
        // key when it sees "****".
        api_key: apiKey,
      });
      backend = saved.backend;
      apiUrl = saved.api_url;
      apiKey = saved.api_key;
      addToast('Translation settings saved', 'success');
    } catch {
      addToast('Failed to save translation settings', 'error');
    } finally {
      saving = false;
    }
  }
</script>

<svelte:head>
  <title>Translation - Admin</title>
</svelte:head>

<div class="translation-page">
  <h1 class="page-title">Post Translation</h1>

  {#if loading}
    <section class="card">
      {#each Array(3) as _, i (i)}
        <div class="skeleton" style="height: 40px; margin-bottom: 12px"></div>
      {/each}
    </section>
  {:else}
    <section class="card">
      <h2 class="section-title">Translation backend</h2>
      <p class="section-desc">
        Lets members translate posts into their language via a per-post “Translate” action.
        Off by default. <strong>LibreTranslate</strong> is free and self-hostable (no per-character cost,
        and post text never leaves a server you control); <strong>DeepL</strong> offers higher quality
        via a paid API key.
      </p>

      <div class="form-fields">
        <div class="form-field">
          <label for="backend" class="field-label">Provider</label>
          <select id="backend" class="input" bind:value={backend}>
            <option value="none">Disabled</option>
            <option value="libretranslate">LibreTranslate</option>
            <option value="deepl">DeepL</option>
          </select>
        </div>

        {#if backend === 'libretranslate'}
          <div class="form-field">
            <label for="api-url" class="field-label">LibreTranslate URL</label>
            <input
              id="api-url"
              type="url"
              class="input"
              bind:value={apiUrl}
              placeholder="https://libretranslate.com"
            />
            <p class="field-hint">Base URL of your LibreTranslate instance. The service appends <code>/translate</code>.</p>
          </div>
        {/if}

        {#if backend === 'libretranslate' || backend === 'deepl'}
          <div class="form-field">
            <label for="api-key" class="field-label">
              API key {backend === 'libretranslate' ? '(optional for public/self-hosted)' : '(required)'}
            </label>
            <input
              id="api-key"
              type="password"
              class="input"
              bind:value={apiKey}
              autocomplete="off"
              placeholder="••••••••"
            />
            <p class="field-hint">Leave the masked value untouched to keep the stored key.</p>
          </div>
        {/if}
      </div>

      <div class="form-actions">
        <button class="btn btn-primary" type="button" disabled={saving} onclick={handleSave}>
          {saving ? 'Saving...' : 'Save Settings'}
        </button>
      </div>
    </section>
  {/if}
</div>

<style>
  .translation-page {
    max-width: 640px;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin-block-end: var(--space-4);
  }

  .card {
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-6);
  }

  .section-title {
    font-size: var(--text-lg);
    font-weight: 700;
    margin-block-end: var(--space-2);
  }

  .section-desc {
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    line-height: var(--leading-relaxed);
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
    gap: 6px;
  }

  .field-label {
    font-size: var(--text-sm);
    font-weight: 600;
  }

  .field-hint {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary, var(--color-text-secondary));
    margin: 0;
  }

  .form-actions {
    margin-block-start: var(--space-5);
    display: flex;
    justify-content: flex-end;
  }
</style>
