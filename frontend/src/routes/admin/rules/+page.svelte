<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { addToast } from '$lib/stores/toast.js';
  import Spinner from '$lib/components/ui/Spinner.svelte';

  interface Rule {
    id: number;
    text: string;
    hint: string;
  }

  let rules = $state<Rule[]>([]);
  let loading = $state(true);
  let newText = $state('');
  let newHint = $state('');
  let adding = $state(false);
  let editingId = $state<number | null>(null);
  let editText = $state('');
  let editHint = $state('');

  onMount(async () => {
    try {
      rules = await api.get<Rule[]>('/api/v1/admin/rules');
    } catch {
      addToast('Failed to load rules', 'error');
    } finally {
      loading = false;
    }
  });

  async function addRule() {
    if (!newText.trim() || adding) return;
    adding = true;
    try {
      const rule = await api.post<Rule>('/api/v1/admin/rules', { text: newText, hint: newHint });
      rules = [...rules, rule];
      newText = '';
      newHint = '';
      addToast('Rule added', 'success');
    } catch {
      addToast('Failed to add rule', 'error');
    } finally { adding = false; }
  }

  function startEdit(rule: Rule) {
    editingId = rule.id;
    editText = rule.text;
    editHint = rule.hint;
  }

  async function saveEdit() {
    if (editingId === null || !editText.trim()) return;
    try {
      const updated = await api.put<Rule>(`/api/v1/admin/rules/${editingId}`, { text: editText, hint: editHint });
      rules = rules.map(r => r.id === editingId ? updated : r);
      editingId = null;
      addToast('Rule updated', 'success');
    } catch {
      addToast('Failed to update rule', 'error');
    }
  }

  async function deleteRule(index: number) {
    try {
      await api.delete(`/api/v1/admin/rules/${index}`);
      // Re-fetch to get correct indices
      rules = await api.get<Rule[]>('/api/v1/admin/rules');
      addToast('Rule deleted', 'success');
    } catch {
      addToast('Failed to delete rule', 'error');
    }
  }
</script>

<svelte:head>
  <title>Instance Rules - Admin</title>
</svelte:head>

<div class="rules-page">
  <div class="page-header">
    <h1 class="page-title">Instance Rules</h1>
    <p class="page-desc">Define the rules for your instance. These are shown to new users during registration and on the about page.</p>
  </div>

  <!-- Add rule -->
  <div class="card add-card">
    <h2 class="card-title">Add Rule</h2>
    <div class="add-form">
      <div class="field">
        <label class="label" for="rule-text">Rule</label>
        <input id="rule-text" type="text" class="input" bind:value={newText} placeholder="e.g. Be respectful to others" />
      </div>
      <div class="field">
        <label class="label" for="rule-hint">Hint (optional)</label>
        <input id="rule-hint" type="text" class="input" bind:value={newHint} placeholder="Additional context or explanation" />
      </div>
      <button class="btn btn-primary" type="button" onclick={addRule} disabled={!newText.trim() || adding}>
        {adding ? 'Adding...' : 'Add Rule'}
      </button>
    </div>
  </div>

  <!-- Rules list -->
  <div class="card">
    <h2 class="card-title">Current Rules</h2>
    {#if loading}
      <div class="loading"><Spinner /></div>
    {:else if rules.length === 0}
      <p class="empty">No rules defined yet. Add your first rule above.</p>
    {:else}
      <div class="rules-list">
        {#each rules as rule, i (rule.id)}
          <div class="rule-item">
            {#if editingId === rule.id}
              <div class="rule-edit">
                <input type="text" class="input" bind:value={editText} placeholder="Rule text" />
                <input type="text" class="input input-sm" bind:value={editHint} placeholder="Hint (optional)" />
                <div class="rule-edit-actions">
                  <button class="btn btn-sm btn-primary" type="button" onclick={saveEdit}>Save</button>
                  <button class="btn btn-sm btn-ghost" type="button" onclick={() => editingId = null}>Cancel</button>
                </div>
              </div>
            {:else}
              <div class="rule-number">{i + 1}</div>
              <div class="rule-content">
                <div class="rule-text">{rule.text}</div>
                {#if rule.hint}
                  <div class="rule-hint">{rule.hint}</div>
                {/if}
              </div>
              <div class="rule-actions">
                <button class="action-btn" type="button" title="Edit" onclick={() => startEdit(rule)}>
                  <span class="material-symbols-outlined" style="font-size: 18px">edit</span>
                </button>
                <button class="action-btn action-danger" type="button" title="Delete" onclick={() => deleteRule(rule.id)}>
                  <span class="material-symbols-outlined" style="font-size: 18px">delete</span>
                </button>
              </div>
            {/if}
          </div>
        {/each}
      </div>
    {/if}
  </div>
</div>

<style>
  .rules-page { max-width: 720px; }
  .page-header { margin-block-end: var(--space-6); }
  .page-title { font-size: var(--text-2xl); font-weight: 700; }
  .page-desc { font-size: var(--text-sm); color: var(--color-text-secondary); margin-block-start: var(--space-1); }

  .card {
    background: var(--color-surface-raised, white);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-xl);
    padding: var(--space-5);
    margin-block-end: var(--space-4);
  }

  .card-title { font-size: var(--text-base); font-weight: 600; margin-block-end: var(--space-4); }

  .add-form { display: flex; flex-direction: column; gap: var(--space-3); }
  .field { display: flex; flex-direction: column; gap: 4px; }
  .label { font-size: 0.75rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: var(--color-text-secondary); }

  .loading { padding: var(--space-8); text-align: center; }
  .empty { font-size: var(--text-sm); color: var(--color-text-tertiary); text-align: center; padding: var(--space-8); }

  .rules-list { display: flex; flex-direction: column; gap: 2px; }

  .rule-item {
    display: flex;
    align-items: flex-start;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-2);
    border-radius: var(--radius-md);
    transition: background 0.15s ease;
  }

  .rule-item:hover { background: var(--color-surface-container-low, #f5f5f5); }

  .rule-number {
    width: 28px;
    height: 28px;
    border-radius: 50%;
    background: var(--color-primary);
    color: var(--color-on-primary);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.75rem;
    font-weight: 700;
    flex-shrink: 0;
  }

  .rule-content { flex: 1; min-width: 0; }
  .rule-text { font-size: var(--text-sm); font-weight: 500; color: var(--color-text); }
  .rule-hint { font-size: 0.75rem; color: var(--color-text-tertiary); margin-block-start: 2px; }

  .rule-actions {
    display: flex;
    gap: 4px;
    flex-shrink: 0;
    opacity: 0;
    transition: opacity 0.15s ease;
  }

  .rule-item:hover .rule-actions { opacity: 1; }

  .action-btn {
    background: none;
    border: none;
    color: var(--color-text-tertiary);
    cursor: pointer;
    padding: 4px;
    border-radius: var(--radius-sm);
    transition: color 0.15s ease, background 0.15s ease;
  }

  .action-btn:hover { color: var(--color-text); background: var(--color-surface-container); }
  .action-danger:hover { color: var(--color-danger); background: var(--color-danger-soft, rgba(239,68,68,0.1)); }

  .rule-edit { flex: 1; display: flex; flex-direction: column; gap: var(--space-2); }
  .rule-edit-actions { display: flex; gap: var(--space-2); }

  .btn-sm { padding: 4px 12px; font-size: 0.75rem; }
  .btn-ghost { background: none; border: none; color: var(--color-text-secondary); cursor: pointer; }
</style>
