<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';

  let {
    onselect,
  }: {
    onselect: (text: string) => void;
  } = $props();

  interface CustomEmoji {
    shortcode: string;
    url: string;
    category: string | null;
  }

  let customEmojis = $state<CustomEmoji[]>([]);
  let loading = $state(true);
  let activeTab = $state<string>('quick');

  const quickEmojis = [
    { char: '\u{1F600}', label: 'Grinning' },
    { char: '\u{2764}\u{FE0F}', label: 'Heart' },
    { char: '\u{1F917}', label: 'Hugging' },
    { char: '\u{1F621}', label: 'Angry' },
    { char: '\u{1F622}', label: 'Crying' },
    { char: '\u{1F602}', label: 'Laughing' },
    { char: '\u{1F92F}', label: 'Mind Blown' },
  ];

  let categories = $derived(() => {
    const cats = new Set<string>();
    for (const e of customEmojis) {
      cats.add(e.category || 'Uncategorized');
    }
    return Array.from(cats).sort();
  });

  let filteredEmojis = $derived(() => {
    if (activeTab === 'quick') return [];
    return customEmojis.filter(
      (e) => (e.category || 'Uncategorized') === activeTab
    );
  });

  let tabs = $derived(() => {
    const result: string[] = ['quick'];
    if (customEmojis.length > 0) {
      result.push(...categories());
    }
    return result;
  });

  onMount(async () => {
    try {
      customEmojis = await api.get<CustomEmoji[]>('/api/v1/custom_emojis');
    } catch {
      customEmojis = [];
    } finally {
      loading = false;
    }
  });

  function handleQuickSelect(char: string) {
    onselect(char);
  }

  function handleCustomSelect(shortcode: string) {
    onselect(`:${shortcode}:`);
  }
</script>

<div class="emoji-picker" onclick={(e) => e.stopPropagation()} role="dialog" aria-label="Emoji picker">
  <div class="emoji-tabs">
    {#each tabs() as tab (tab)}
      <button
        type="button"
        class="emoji-tab"
        class:emoji-tab-active={activeTab === tab}
        onclick={() => { activeTab = tab; }}
      >
        {tab === 'quick' ? 'Quick' : tab}
      </button>
    {/each}
  </div>

  <div class="emoji-grid-container">
    {#if activeTab === 'quick'}
      <div class="emoji-grid">
        {#each quickEmojis as emoji (emoji.char)}
          <button
            type="button"
            class="emoji-item"
            onclick={() => handleQuickSelect(emoji.char)}
            title={emoji.label}
            aria-label={emoji.label}
          >
            {emoji.char}
          </button>
        {/each}
      </div>
    {:else if loading}
      <div class="emoji-loading">Loading...</div>
    {:else}
      <div class="emoji-grid">
        {#each filteredEmojis() as emoji (emoji.shortcode)}
          <button
            type="button"
            class="emoji-item emoji-item-custom"
            onclick={() => handleCustomSelect(emoji.shortcode)}
            title=":{emoji.shortcode}:"
            aria-label={emoji.shortcode}
          >
            <img src={emoji.url} alt=":{emoji.shortcode}:" class="emoji-img" loading="lazy" />
          </button>
        {/each}
        {#if filteredEmojis().length === 0}
          <p class="emoji-empty">No emojis in this category.</p>
        {/if}
      </div>
    {/if}
  </div>
</div>

<style>
  .emoji-picker {
    position: absolute;
    inset-block-end: 100%;
    inset-inline-start: 0;
    margin-block-end: var(--space-2);
    width: 280px;
    max-height: 300px;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-lg);
    display: flex;
    flex-direction: column;
    z-index: var(--z-popover, 30);
    animation: picker-in 0.15s ease;
  }

  @keyframes picker-in {
    from {
      opacity: 0;
      transform: translateY(4px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .emoji-tabs {
    display: flex;
    overflow-x: auto;
    border-block-end: 1px solid var(--color-border);
    padding: var(--space-1);
    gap: var(--space-1);
    scrollbar-width: none;
  }

  .emoji-tabs::-webkit-scrollbar {
    display: none;
  }

  .emoji-tab {
    flex-shrink: 0;
    padding: var(--space-1) var(--space-2);
    border: none;
    background: transparent;
    color: var(--color-text-secondary);
    font-size: var(--text-xs);
    font-weight: 500;
    cursor: pointer;
    border-radius: var(--radius-sm);
    white-space: nowrap;
    transition: background-color 0.15s ease, color 0.15s ease;
  }

  .emoji-tab:hover {
    background: var(--color-bg-tertiary);
  }

  .emoji-tab-active {
    background: var(--color-primary-soft);
    color: var(--color-primary);
  }

  .emoji-grid-container {
    overflow-y: auto;
    flex: 1;
    padding: var(--space-2);
  }

  .emoji-grid {
    display: grid;
    grid-template-columns: repeat(7, 1fr);
    gap: var(--space-1);
  }

  .emoji-item {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 34px;
    height: 34px;
    border: none;
    background: transparent;
    border-radius: var(--radius-md);
    cursor: pointer;
    font-size: 1.25rem;
    line-height: 1;
    transition: background-color 0.1s ease, transform 0.1s ease;
  }

  .emoji-item:hover {
    background: var(--color-bg-tertiary);
    transform: scale(1.15);
  }

  .emoji-item-custom {
    padding: 2px;
  }

  .emoji-img {
    width: 24px;
    height: 24px;
    object-fit: contain;
  }

  .emoji-loading,
  .emoji-empty {
    text-align: center;
    padding: var(--space-4);
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
  }
</style>
