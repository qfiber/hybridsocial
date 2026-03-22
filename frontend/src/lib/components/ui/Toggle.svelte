<script lang="ts">
  let {
    checked = $bindable(false),
    label = '',
    disabled = false,
    id = '',
    name = ''
  }: {
    checked?: boolean;
    label?: string;
    disabled?: boolean;
    id?: string;
    name?: string;
  } = $props();

  let toggleId = $derived(id || `toggle-${name || Math.random().toString(36).slice(2)}`);
</script>

<label class="toggle-wrapper" class:disabled for={toggleId}>
  <input
    type="checkbox"
    bind:checked
    {disabled}
    {name}
    id={toggleId}
    class="toggle-input"
    role="switch"
    aria-checked={checked}
  />
  <span class="toggle-track">
    <span class="toggle-thumb"></span>
  </span>
  {#if label}
    <span class="toggle-label">{label}</span>
  {/if}
</label>

<style>
  .toggle-wrapper {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    cursor: pointer;
    user-select: none;
  }

  .toggle-wrapper.disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .toggle-input {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
  }

  .toggle-track {
    position: relative;
    width: 44px;
    height: 24px;
    background: var(--color-border);
    border-radius: var(--radius-full);
    transition: background var(--transition-fast);
    flex-shrink: 0;
  }

  .toggle-input:checked + .toggle-track {
    background: var(--color-primary);
  }

  .toggle-input:focus-visible + .toggle-track {
    outline: 2px solid var(--color-primary);
    outline-offset: 2px;
  }

  .toggle-thumb {
    position: absolute;
    top: 2px;
    inset-inline-start: 2px;
    width: 20px;
    height: 20px;
    background: white;
    border-radius: var(--radius-full);
    box-shadow: var(--shadow-sm);
    transition: transform var(--transition-fast);
  }

  .toggle-input:checked + .toggle-track .toggle-thumb {
    transform: translateX(20px);
  }

  :global([dir='rtl']) .toggle-input:checked + .toggle-track .toggle-thumb {
    transform: translateX(-20px);
  }

  .toggle-label {
    font-size: var(--text-sm);
    color: var(--color-text);
  }
</style>
