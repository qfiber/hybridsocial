<script lang="ts">
  let {
    value = $bindable(''),
    label = '',
    placeholder = '',
    error = '',
    disabled = false,
    required = false,
    name = '',
    id = '',
    rows = 3,
    maxlength
  }: {
    value?: string;
    label?: string;
    placeholder?: string;
    error?: string;
    disabled?: boolean;
    required?: boolean;
    name?: string;
    id?: string;
    rows?: number;
    maxlength?: number;
  } = $props();

  let textareaId = $derived(id || `textarea-${name}`);
  let textareaEl: HTMLTextAreaElement | undefined = $state();

  function autoGrow() {
    if (!textareaEl) return;
    textareaEl.style.height = 'auto';
    textareaEl.style.height = textareaEl.scrollHeight + 'px';
  }

  $effect(() => {
    void value;
    autoGrow();
  });
</script>

<div class="textarea-group" class:has-error={!!error}>
  {#if label}
    <label for={textareaId} class="textarea-label">
      {label}
      {#if required}<span class="required-mark" aria-hidden="true">*</span>{/if}
    </label>
  {/if}

  <textarea
    bind:this={textareaEl}
    bind:value
    {placeholder}
    {disabled}
    {required}
    {name}
    {maxlength}
    id={textareaId}
    {rows}
    class="textarea-field"
    aria-invalid={!!error}
    aria-describedby={error ? `${textareaId}-error` : undefined}
    oninput={autoGrow}
  ></textarea>

  {#if error}
    <p class="textarea-error" id="{textareaId}-error" role="alert">{error}</p>
  {/if}
</div>

<style>
  .textarea-group {
    display: flex;
    flex-direction: column;
    gap: var(--space-1);
  }

  .textarea-label {
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--color-text);
  }

  .required-mark {
    color: var(--color-danger);
    margin-inline-start: var(--space-1);
  }

  .textarea-field {
    width: 100%;
    min-height: 80px;
    padding: var(--space-2) var(--space-3);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    font-size: var(--text-sm);
    color: var(--color-text);
    background: var(--color-bg);
    resize: none;
    overflow: hidden;
    transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
    line-height: var(--line-height);
  }

  .textarea-field::placeholder {
    color: var(--color-text-tertiary);
  }

  .textarea-field:hover:not(:disabled) {
    border-color: var(--color-text-tertiary);
  }

  .textarea-field:focus {
    outline: none;
    border-color: var(--color-primary);
    box-shadow: 0 0 0 3px var(--color-primary-soft);
  }

  .textarea-field:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    background: var(--color-surface);
  }

  .has-error .textarea-field {
    border-color: var(--color-danger);
  }

  .has-error .textarea-field:focus {
    box-shadow: 0 0 0 3px var(--color-danger-soft);
  }

  .textarea-error {
    font-size: var(--text-xs);
    color: var(--color-danger);
  }
</style>
