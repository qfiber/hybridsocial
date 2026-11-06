<script lang="ts">
  import { onMount } from 'svelte';
  import { addToast } from '$lib/stores/toast.js';
  import { getPostLimitDefaults, updateAdminSettings } from '$lib/api/admin.js';

  const KINDS = [
    { id: 'user', title: 'People' },
    { id: 'bot', title: 'Bots' },
  ] as const;
  const WINDOWS = [
    { id: 'minute', label: 'Per minute' },
    { id: 'hour', label: 'Per hour' },
    { id: 'day', label: 'Per day' },
  ] as const;

  let values = $state({
    user: { minute: 0, hour: 0, day: 0 },
    bot: { minute: 0, hour: 0, day: 0 },
  });
  let loading = $state(true);
  let saving = $state(false);

  async function load() {
    try {
      values = await getPostLimitDefaults();
    } catch {
      addToast('Failed to load posting limits', 'error');
    } finally {
      loading = false;
    }
  }

  async function handleSave() {
    const settings = KINDS.flatMap((kind) =>
      WINDOWS.map((window) => ({
        key: `${kind.id}_posts_per_${window.id}`,
        value: Number(values[kind.id][window.id]),
      })),
    );
    if (settings.some((s) => !Number.isInteger(s.value) || s.value < 0)) {
      addToast('Limits must be whole numbers, 0 or more', 'error');
      return;
    }

    saving = true;
    try {
      await updateAdminSettings(settings);
      addToast('Posting limits saved', 'success');
    } catch {
      addToast('Failed to save posting limits', 'error');
    } finally {
      saving = false;
    }
  }

  onMount(load);
</script>

<svelte:head>
  <title>Posting limits - Admin</title>
</svelte:head>

<div class="limits-page">
  <div class="limits-header">
    <div>
      <h1 class="page-title">Posting limits</h1>
      <p class="limits-subtitle">
        How many posts each account can create. Replies and scheduled posts count. Posts over a
        limit are refused, and the person is told when they can post again. 0 means unlimited.
        To set different limits for one account, open it under Users and use its Posting limits
        section.
      </p>
    </div>
    <button class="btn btn-primary" onclick={handleSave} disabled={saving || loading}>
      {saving ? 'Saving…' : 'Save changes'}
    </button>
  </div>

  {#if loading}
    <div class="limits-loading">Loading…</div>
  {:else}
    {#each KINDS as kind (kind.id)}
      <section class="limits-card card">
        <h2 class="limits-title">{kind.title}</h2>
        <div class="limits-grid">
          {#each WINDOWS as window (window.id)}
            <div class="limits-field">
              <label class="field-label" for="{kind.id}-{window.id}">{window.label}</label>
              <input
                id="{kind.id}-{window.id}"
                class="input"
                type="number"
                min="0"
                step="1"
                inputmode="numeric"
                bind:value={values[kind.id][window.id]}
              />
            </div>
          {/each}
        </div>
      </section>
    {/each}
  {/if}
</div>

<style>
  .limits-page {
    max-width: 720px;
    display: flex;
    flex-direction: column;
    gap: var(--space-4);
  }

  .limits-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--space-4);
    flex-wrap: wrap;
  }

  .page-title {
    font-size: var(--text-2xl);
    font-weight: 700;
    margin: 0 0 4px;
    color: var(--color-text);
  }

  .limits-subtitle {
    margin: 0;
    font-size: var(--text-sm);
    color: var(--color-text-secondary);
    max-width: 52ch;
    line-height: 1.5;
  }

  .limits-loading {
    color: var(--color-text-tertiary);
    font-size: var(--text-sm);
    padding: var(--space-6) 0;
  }

  .limits-card {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    padding: var(--space-5);
  }

  .limits-title {
    margin: 0;
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--color-text);
  }

  .limits-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
    gap: var(--space-4);
  }

  .limits-field {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .limits-field .input {
    width: 100%;
  }

  .field-label {
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--color-text);
  }
</style>
