<script lang="ts">
  // One registry setting rendered as the right control for its type, with
  // its unit, default, "changed" state and reset action. The settings page
  // owns the form state; this component only edits `value`.
  import { t } from '$lib/stores/i18n.js';
  import type { ReplacementPair, SettingSchemaEntry, SettingValue } from '$lib/api/types.js';
  import Toggle from '$lib/components/ui/Toggle.svelte';
  import SettingRow from './SettingRow.svelte';
  import StatusPill from './StatusPill.svelte';

  let {
    entry,
    value = $bindable(),
    disabled = false,
    error = null,
    onreset,
  }: {
    entry: SettingSchemaEntry;
    value: SettingValue;
    disabled?: boolean;
    error?: string | null;
    onreset?: () => void;
  } = $props();

  let id = $derived(`setting-${entry.key}`);

  // Translated text, or `fallback` when the locale files have no such key.
  function tr(key: string, fallback: string, params?: Record<string, string | number>): string {
    const out = $t(key, params);
    return out === key ? fallback : out;
  }

  let label = $derived(tr(`admin_settings.${entry.key}`, entry.key));
  let help = $derived(tr(`admin_settings.${entry.key}_help`, ''));

  function optionLabel(option: string): string {
    return tr(`admin_settings.option.${entry.key}.${option}`, option);
  }

  function formatBytes(n: number): string {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    let v = n;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return `${v % 1 === 0 ? v : v.toFixed(1)} ${units[i]}`;
  }

  function formatValue(v: SettingValue): string {
    if (v === null || v === '') return tr('admin_settings.empty', 'empty');
    if (typeof v === 'boolean') return v ? tr('admin_settings.on', 'On') : tr('admin_settings.off', 'Off');
    if (Array.isArray(v)) {
      if (!v.length) return tr('admin_settings.empty', 'empty');
      if (entry.type === 'multi_enum') return (v as string[]).map(optionLabel).join(', ');
      if (entry.type === 'replacement_list')
        return (v as ReplacementPair[]).map((p) => `${p.pattern} → ${p.replacement}`).join(', ');
      return v.join(', ');
    }
    if (entry.type === 'enum') return optionLabel(String(v));
    if (entry.unit === 'bytes' && typeof v === 'number') return formatBytes(v);
    return entry.unit ? `${v} ${unitLabel}` : String(v);
  }

  // Multi-choice: keep the options' own order whatever order they're ticked in.
  function toggleOption(option: string, on: boolean) {
    const current = new Set(Array.isArray(value) ? (value as string[]) : []);
    if (on) current.add(option);
    else current.delete(option);
    value = (entry.options ?? []).filter((o) => current.has(o));
  }

  let pairs = $derived<ReplacementPair[]>(Array.isArray(value) ? (value as ReplacementPair[]) : []);

  function setPair(i: number, field: keyof ReplacementPair, text: string) {
    value = pairs.map((p, j) => (j === i ? { ...p, [field]: text } : p));
  }

  let unitLabel = $derived(entry.unit ? tr(`admin_settings.unit.${entry.unit}`, entry.unit) : '');

  // Byte counts are unreadable as raw numbers; show the human size alongside.
  let byteHint = $derived(
    entry.unit === 'bytes' && typeof value === 'number' && value > 0 ? formatBytes(value) : '',
  );

  // Lists are edited as one item per line.
  let listText = $state(Array.isArray(value) ? value.join('\n') : '');
  $effect(() => {
    // Re-sync when the page discards or reloads (value replaced from outside).
    const incoming = Array.isArray(value) ? value.join('\n') : '';
    const current = listText
      .split('\n')
      .map((s) => s.trim())
      .filter(Boolean)
      .join('\n');
    if (incoming !== current) listText = incoming;
  });

  function onListInput(e: Event) {
    listText = (e.target as HTMLTextAreaElement).value;
    value = listText
      .split('\n')
      .map((s) => s.trim())
      .filter(Boolean);
  }

  function onNumberInput(e: Event) {
    const raw = (e.target as HTMLInputElement).value;
    value = raw === '' ? null : Number(raw);
  }

  let errorText = $derived(
    error
      ? tr(`admin_settings.error.${entry.type === 'replacement_list' && error === 'invalid_list' ? 'invalid_pairs' : error}`, error, {
          min: entry.min ?? '',
          max: entry.max ?? '',
        })
      : '',
  );

  let layout = $derived<'inline' | 'stacked'>(
    entry.type === 'boolean' || entry.type === 'enum' || entry.type === 'integer' || entry.type === 'number'
      ? 'inline'
      : 'stacked',
  );
</script>

<SettingRow {label} {help} labelFor={id} {layout}>
  <div class="field" class:stacked={layout === 'stacked'}>
    {#if entry.secret}
      <div class="secret">
        <input
          {id}
          type="password"
          class="input"
          autocomplete="off"
          placeholder={entry.set ? $t('admin_settings.secret_keep') : $t('admin_settings.secret_enter')}
          value={typeof value === 'string' ? value : ''}
          oninput={(e) => (value = (e.target as HTMLInputElement).value)}
          {disabled}
        />
        <StatusPill
          tone={entry.set ? 'success' : 'neutral'}
          label={entry.set ? $t('admin_settings.secret_set') : $t('admin_settings.secret_unset')}
        />
      </div>
    {:else if entry.type === 'boolean'}
      <Toggle {id} bind:checked={() => value === true, (checked) => (value = checked)} {disabled} />
    {:else if entry.type === 'enum'}
      <select {id} class="input select" value={String(value ?? '')} onchange={(e) => (value = (e.target as HTMLSelectElement).value)} {disabled}>
        {#each entry.options ?? [] as option (option)}
          <option value={option}>{optionLabel(option)}</option>
        {/each}
      </select>
    {:else if entry.type === 'integer' || entry.type === 'number'}
      <div class="number">
        <input
          {id}
          type="number"
          class="input"
          inputmode={entry.type === 'integer' ? 'numeric' : 'decimal'}
          step={entry.type === 'integer' ? 1 : 'any'}
          min={entry.min ?? undefined}
          max={entry.max ?? undefined}
          value={value ?? ''}
          oninput={onNumberInput}
          {disabled}
        />
        {#if unitLabel}<span class="unit">{unitLabel}</span>{/if}
      </div>
    {:else if entry.type === 'multi_enum'}
      <fieldset {id} class="choices" {disabled}>
        <legend class="visually-hidden">{label}</legend>
        {#each entry.options ?? [] as option (option)}
          {@const optionHelp = tr(`admin_settings.option.${entry.key}.${option}_help`, '')}
          <label class="choice">
            <input
              type="checkbox"
              checked={Array.isArray(value) && (value as string[]).includes(option)}
              onchange={(e) => toggleOption(option, (e.target as HTMLInputElement).checked)}
            />
            <span class="choice-text">
              <span class="choice-label">{optionLabel(option)}</span>
              {#if optionHelp}<span class="choice-help">{optionHelp}</span>{/if}
            </span>
          </label>
        {/each}
      </fieldset>
    {:else if entry.type === 'replacement_list'}
      <div {id} class="pairs">
        {#each pairs as pair, i (i)}
          <div class="pair">
            <input
              class="input"
              type="text"
              maxlength="500"
              value={pair.pattern}
              oninput={(e) => setPair(i, 'pattern', (e.target as HTMLInputElement).value)}
              placeholder={$t('admin_settings.pair_pattern')}
              aria-label={$t('admin_settings.pair_pattern')}
              {disabled}
            />
            <span class="pair-arrow" aria-hidden="true">→</span>
            <input
              class="input"
              type="text"
              maxlength="500"
              value={pair.replacement}
              oninput={(e) => setPair(i, 'replacement', (e.target as HTMLInputElement).value)}
              placeholder={$t('admin_settings.pair_replacement')}
              aria-label={$t('admin_settings.pair_replacement')}
              {disabled}
            />
            <button
              type="button"
              class="btn btn-sm btn-ghost"
              onclick={() => (value = pairs.filter((_, j) => j !== i))}
              aria-label={$t('admin_settings.pair_remove')}
              {disabled}
            >
              ✕
            </button>
          </div>
        {/each}
        <button
          type="button"
          class="btn btn-sm btn-outline pair-add"
          onclick={() => (value = [...pairs, { pattern: '', replacement: '' }])}
          {disabled}
        >
          {$t('admin_settings.pair_add')}
        </button>
      </div>
    {:else if entry.type === 'string_list'}
      <textarea
        {id}
        class="textarea"
        rows="4"
        value={listText}
        oninput={onListInput}
        placeholder={$t('admin_settings.list_placeholder')}
        {disabled}
      ></textarea>
    {:else if entry.multiline}
      <textarea
        {id}
        class="textarea"
        rows="4"
        maxlength={entry.max_length ?? undefined}
        value={typeof value === 'string' ? value : ''}
        oninput={(e) => (value = (e.target as HTMLTextAreaElement).value)}
        {disabled}
      ></textarea>
    {:else}
      <input
        {id}
        type="text"
        class="input"
        maxlength={entry.max_length ?? undefined}
        value={typeof value === 'string' ? value : ''}
        oninput={(e) => (value = (e.target as HTMLInputElement).value)}
        {disabled}
      />
    {/if}
  </div>

  {#snippet meta()}
    {#if byteHint}
      <span class="meta-text">≈ {byteHint}</span>
    {/if}
    {#if !entry.secret}
      {#if entry.stored}
        <span class="meta-changed">{$t('admin_settings.changed')}</span>
        <span class="meta-text">{$t('admin_settings.default_is', { value: formatValue(entry.default) })}</span>
        {#if onreset && !disabled}
          <button type="button" class="meta-reset" onclick={onreset}>{$t('admin_settings.reset')}</button>
        {/if}
      {/if}
    {:else if entry.set && onreset && !disabled}
      <button type="button" class="meta-reset" onclick={onreset}>{$t('admin_settings.secret_remove')}</button>
    {/if}
    {#if errorText}
      <span class="meta-error" role="alert">{errorText}</span>
    {/if}
  {/snippet}
</SettingRow>

<style>
  .field {
    display: flex;
    align-items: center;
    justify-content: flex-end;
  }

  .field.stacked {
    width: 100%;
    justify-content: flex-start;
  }

  .field.stacked > :global(*) {
    flex: 1;
    min-width: 0;
  }

  .secret {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    width: 100%;
  }

  .secret .input {
    flex: 1;
    min-width: 0;
  }

  .number {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .number .input {
    width: 140px;
    text-align: end;
    font-variant-numeric: tabular-nums;
  }

  .unit {
    font-size: var(--text-xs);
    color: var(--color-text-secondary);
    white-space: nowrap;
  }

  .choices {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
    margin: 0;
    padding: 0;
    border: 0;
    min-width: 0;
  }

  .choice {
    display: flex;
    align-items: flex-start;
    gap: var(--space-2);
    cursor: pointer;
  }

  .choice input {
    margin-block-start: 3px;
    accent-color: var(--color-primary);
  }

  .choice-text {
    display: flex;
    flex-direction: column;
  }

  .choice-label {
    font-size: var(--text-sm);
    font-weight: 600;
  }

  .choice-help {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .pairs {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }

  .pair {
    display: flex;
    align-items: center;
    gap: var(--space-2);
  }

  .pair .input {
    flex: 1;
    min-width: 0;
  }

  .pair-arrow {
    color: var(--color-text-tertiary);
  }

  :global([dir='rtl']) .pair-arrow {
    transform: scaleX(-1);
  }

  .pair-add {
    align-self: flex-start;
  }

  .visually-hidden {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0 0 0 0);
    white-space: nowrap;
  }

  .select {
    min-width: 180px;
    max-width: 100%;
  }

  .meta-text {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }

  .meta-changed {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-primary);
  }

  .meta-reset {
    padding: 0;
    border: 0;
    background: none;
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-text-link);
    cursor: pointer;
  }

  .meta-reset:hover {
    text-decoration: underline;
  }

  .meta-error {
    flex-basis: 100%;
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--color-danger);
  }

  @media (max-width: 560px) {
    .field,
    .number {
      width: 100%;
      justify-content: flex-start;
    }

    .number .input,
    .select {
      width: 100%;
      flex: 1;
    }
  }
</style>
