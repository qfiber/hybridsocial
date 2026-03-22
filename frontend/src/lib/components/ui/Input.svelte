<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    type = 'text',
    value = $bindable(''),
    label = '',
    placeholder = '',
    error = '',
    disabled = false,
    required = false,
    name = '',
    id = '',
    icon
  }: {
    type?: string;
    value?: string;
    label?: string;
    placeholder?: string;
    error?: string;
    disabled?: boolean;
    required?: boolean;
    name?: string;
    id?: string;
    icon?: Snippet;
  } = $props();

  let inputId = $derived(id || `input-${name}`);
</script>

<div class="input-group" class:has-error={!!error}>
  {#if label}
    <label for={inputId} class="input-label">
      {label}
      {#if required}<span class="required-mark" aria-hidden="true">*</span>{/if}
    </label>
  {/if}

  <div class="input-wrapper" class:has-icon={!!icon}>
    {#if icon}
      <span class="input-icon" aria-hidden="true">
        {@render icon()}
      </span>
    {/if}
    <input
      {type}
      bind:value
      {placeholder}
      {disabled}
      {required}
      {name}
      id={inputId}
      class="input-field"
      aria-invalid={!!error}
      aria-describedby={error ? `${inputId}-error` : undefined}
    />
  </div>

  {#if error}
    <p class="input-error" id="{inputId}-error" role="alert">{error}</p>
  {/if}
</div>

<style>
  .input-group {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .input-label {
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
  }

  .required-mark {
    color: var(--color-danger);
    margin-inline-start: var(--space-1);
  }

  .input-wrapper {
    position: relative;
    display: flex;
    align-items: center;
  }

  .input-icon {
    position: absolute;
    inset-inline-start: var(--space-3);
    color: var(--color-text-tertiary);
    display: flex;
    align-items: center;
    pointer-events: none;
  }

  .input-field {
    width: 100%;
    height: 40px;
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    color: var(--color-text);
    background: var(--color-bg);
    transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
  }

  .has-icon .input-field {
    padding-inline-start: var(--space-10);
  }

  .input-field::placeholder {
    color: var(--color-text-tertiary);
  }

  .input-field:hover:not(:disabled) {
    border-color: var(--color-text-tertiary);
  }

  .input-field:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px var(--color-primary-soft);
  }

  .input-field:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    background: var(--color-surface);
  }

  .has-error .input-field {
    border-color: var(--color-danger);
  }

  .has-error .input-field:focus {
    box-shadow: 0 0 0 3px var(--color-danger-soft);
  }

  .input-error {
    font-size: var(--text-xs);
    color: var(--color-danger);
  }
</style>
