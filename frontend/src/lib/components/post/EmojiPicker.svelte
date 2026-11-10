<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client.js';
  import { EMOJI_GROUPS, type EmojiEntry } from '$lib/data/emoji-catalog.js';
  import { t } from '$lib/stores/i18n.js';

  let {
    onselect,
    anchor,
    onclose,
  }: {
    onselect: (text: string) => void;
    anchor?: HTMLElement;
    onclose?: () => void;
  } = $props();

  interface CustomEmoji {
    shortcode: string;
    url: string;
    category: string | null;
  }

  let customEmojis = $state<CustomEmoji[]>([]);
  let loadingCustom = $state(true);
  let activeTab = $state<string>(EMOJI_GROUPS[0].id);
  let query = $state('');

  // The picker lives inside the composer modal, which is position:fixed with a
  // translate() transform (traps position:fixed descendants) AND clips overflow.
  // So portal the picker to <body> to escape both, then anchor it to the trigger
  // button via fixed coords, flipping below when there isn't room above.
  let pickerEl: HTMLDivElement | undefined = $state();
  let posStyle = $state('visibility:hidden;');

  function portal(node: HTMLElement) {
    document.body.appendChild(node);
    return {
      destroy() {
        node.remove();
      }
    };
  }

  function reposition() {
    const el = pickerEl;
    if (!el || !anchor) return;
    const r = anchor.getBoundingClientRect();
    const w = el.offsetWidth || 340;
    const h = el.offsetHeight || 380;
    const gap = 8;
    const margin = 8;
    const left = Math.max(margin, Math.min(r.left, window.innerWidth - w - margin));
    const spaceAbove = r.top - margin;
    const top =
      spaceAbove >= h || spaceAbove >= window.innerHeight - r.bottom
        ? Math.max(margin, r.top - h - gap)
        : Math.min(r.bottom + gap, window.innerHeight - h - margin);
    posStyle = `left:${Math.round(left)}px;top:${Math.round(top)}px;`;
  }

  function onDocMouseDown(e: MouseEvent) {
    const t = e.target as Node;
    if (pickerEl?.contains(t) || anchor?.contains(t)) return;
    onclose?.();
  }

  onMount(() => {
    reposition();
    requestAnimationFrame(reposition);
    const onWin = () => reposition();
    window.addEventListener('resize', onWin);
    window.addEventListener('scroll', onWin, true);
    document.addEventListener('mousedown', onDocMouseDown, true);
    return () => {
      window.removeEventListener('resize', onWin);
      window.removeEventListener('scroll', onWin, true);
      document.removeEventListener('mousedown', onDocMouseDown, true);
    };
  });

  // Custom emojis are folded in as one or more extra tabs grouped by
  // their `category` (Uncategorized when unset). Available to every
  // user — server returns the full catalog regardless of tier.
  let customCategories = $derived.by(() => {
    const cats = new Set<string>();
    for (const ce of customEmojis) cats.add(ce.category || $t('emoji.custom'));
    return Array.from(cats).sort();
  });

  let customByCategory = $derived.by(() => {
    const map = new Map<string, CustomEmoji[]>();
    for (const ce of customEmojis) {
      const key = ce.category || $t('emoji.custom');
      const list = map.get(key) ?? [];
      list.push(ce);
      map.set(key, list);
    }
    return map;
  });

  // One representative glyph per native group — Twemoji-style, so the
  // tab strip fits in the popover without wrapping or hiding the last
  // few categories. Full label still surfaces via the `title` tooltip.
  const TAB_GLYPHS: Record<string, string> = {
    smileys: '\u{1F600}',
    people: '\u{1F44B}',
    animals: '\u{1F436}',
    food: '\u{1F354}',
    activities: '\u{26BD}',
    travel: '\u{1F697}',
    objects: '\u{1F4A1}',
    symbols: '\u{2764}\u{FE0F}',
    flags: '\u{1F3F3}\u{FE0F}',
  };

  // Build a flat searchable list once so the filter can scan both
  // native and custom emojis at the same time without rebuilding
  // structures on every keystroke.
  interface SearchableNative { kind: 'native'; entry: EmojiEntry }
  interface SearchableCustom { kind: 'custom'; entry: CustomEmoji }
  type Searchable = SearchableNative | SearchableCustom;

  let searchIndex = $derived.by<Searchable[]>(() => {
    const out: Searchable[] = [];
    for (const group of EMOJI_GROUPS) {
      for (const entry of group.emojis) out.push({ kind: 'native', entry });
    }
    for (const ce of customEmojis) out.push({ kind: 'custom', entry: ce });
    return out;
  });

  let filteredResults = $derived.by<Searchable[]>(() => {
    const q = query.trim().toLowerCase();
    if (!q) return [];
    const tokens = q.split(/\s+/).filter(Boolean);
    return searchIndex.filter((item) => {
      const haystack =
        item.kind === 'native'
          ? item.entry.name
          : `${item.entry.shortcode} ${item.entry.category ?? ''}`.toLowerCase();
      return tokens.every((t) => haystack.includes(t));
    });
  });

  let activeNativeGroup = $derived(
    EMOJI_GROUPS.find((g) => g.id === activeTab) ?? null,
  );
  let activeCustomList = $derived(
    customByCategory.get(activeTab) ?? null,
  );

  onMount(async () => {
    try {
      customEmojis = await api.get<CustomEmoji[]>('/api/v1/custom_emojis');
    } catch {
      customEmojis = [];
    } finally {
      loadingCustom = false;
    }
  });

  function pickNative(char: string) {
    onselect(char);
  }

  function pickCustom(shortcode: string) {
    onselect(`:${shortcode}:`);
  }
</script>

<div use:portal bind:this={pickerEl} class="emoji-picker" style={posStyle} onclick={(e) => e.stopPropagation()} role="dialog" aria-label={$t('emoji.picker')}>
  <div class="emoji-search">
    <span class="material-symbols-outlined emoji-search-icon" aria-hidden="true">search</span>
    <input
      type="search"
      class="emoji-search-input"
      bind:value={query}
      placeholder={$t('emoji.search')}
      aria-label={$t('emoji.search')}
    />
  </div>

  {#if !query}
    <div class="emoji-tabs" role="tablist">
      {#each EMOJI_GROUPS as group (group.id)}
        <button
          type="button"
          class="emoji-tab emoji-tab-icon"
          class:emoji-tab-active={activeTab === group.id}
          onclick={() => { activeTab = group.id; }}
          role="tab"
          aria-selected={activeTab === group.id}
          aria-label={group.label}
          title={group.label}
        >
          {TAB_GLYPHS[group.id] ?? group.label.charAt(0)}
        </button>
      {/each}
      {#each customCategories as cat (cat)}
        <button
          type="button"
          class="emoji-tab"
          class:emoji-tab-active={activeTab === cat}
          onclick={() => { activeTab = cat; }}
          role="tab"
          aria-selected={activeTab === cat}
          title={cat}
        >
          {cat}
        </button>
      {/each}
    </div>
  {/if}

  <div class="emoji-grid-container">
    {#if query}
      {#if filteredResults.length === 0}
        <p class="emoji-empty">{$t('emoji.no_matches')}</p>
      {:else}
        <div class="emoji-grid">
          {#each filteredResults as item (item.kind === 'native' ? item.entry.char : item.entry.shortcode)}
            {#if item.kind === 'native'}
              <button
                type="button"
                class="emoji-item"
                onclick={() => pickNative(item.entry.char)}
                title={item.entry.name}
                aria-label={item.entry.name}
              >
                {item.entry.char}
              </button>
            {:else}
              <button
                type="button"
                class="emoji-item emoji-item-custom"
                onclick={() => pickCustom(item.entry.shortcode)}
                title={`:${item.entry.shortcode}:`}
                aria-label={item.entry.shortcode}
              >
                <img src={item.entry.url} alt={`:${item.entry.shortcode}:`} class="emoji-img" loading="lazy" />
              </button>
            {/if}
          {/each}
        </div>
      {/if}
    {:else if activeNativeGroup}
      <div class="emoji-grid">
        {#each activeNativeGroup.emojis as entry (entry.char)}
          <button
            type="button"
            class="emoji-item"
            onclick={() => pickNative(entry.char)}
            title={entry.name}
            aria-label={entry.name}
          >
            {entry.char}
          </button>
        {/each}
      </div>
    {:else if loadingCustom}
      <div class="emoji-loading">{$t('common.loading')}</div>
    {:else if activeCustomList && activeCustomList.length > 0}
      <div class="emoji-grid">
        {#each activeCustomList as ce (ce.shortcode)}
          <button
            type="button"
            class="emoji-item emoji-item-custom"
            onclick={() => pickCustom(ce.shortcode)}
            title={`:${ce.shortcode}:`}
            aria-label={ce.shortcode}
          >
            <img src={ce.url} alt={`:${ce.shortcode}:`} class="emoji-img" loading="lazy" />
          </button>
        {/each}
      </div>
    {:else}
      <p class="emoji-empty">{$t('emoji.no_category')}</p>
    {/if}
  </div>
</div>

<style>
  .emoji-picker {
    /* position:fixed + JS-computed left/top (see reposition()) so the modal's
       overflow can't crop it; left/top come in via the inline style. */
    position: fixed;
    width: min(340px, calc(100vw - 32px));
    /* Clamp height to viewport so a tall picker can't pop off the top
       of the screen — symptom from the field report was the search
       bar's top edge clipped because 380px didn't fit above the
       composer toolbar. */
    max-height: min(380px, calc(100vh - 96px));
    max-height: min(380px, calc(100dvh - 96px));
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-lg);
    display: flex;
    flex-direction: column;
    /* Without overflow:hidden, child sections (search bar, tabs)
       paint their own backgrounds past the picker's rounded
       corners — looks like a stripe of "wrong colour" at the top
       edge in the report screenshot. Clip to the rounded shell. */
    overflow: hidden;
    /* Portaled to <body> and must sit ABOVE the composer modal (--z-modal: 40)
       and its backdrop so the picker covers the post body instead of being
       painted over by it. */
    z-index: 1000;
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

  .emoji-search {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 8px 10px;
    border-block-end: 1px solid var(--color-border);
    flex-shrink: 0;
  }

  .emoji-search-icon {
    font-size: 18px;
    color: var(--color-text-tertiary);
    flex-shrink: 0;
  }

  .emoji-search-input {
    flex: 1;
    min-width: 0;
    border: 0;
    background: transparent;
    color: var(--color-text);
    font: inherit;
    font-size: 0.85rem;
    outline: none;
  }

  .emoji-search-input::-webkit-search-cancel-button {
    cursor: pointer;
  }

  .emoji-tabs {
    display: flex;
    overflow-x: auto;
    border-block-end: 1px solid var(--color-border);
    padding: var(--space-1);
    gap: var(--space-1);
    scrollbar-width: none;
    /* Keep the tab row at full height; only the grid should flex/scroll,
       otherwise the category icons get squeezed and clipped. */
    flex-shrink: 0;
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

  /* Native-category tabs are rendered as a single representative
     glyph so all 9 fit horizontally in a 340px popover without the
     last few categories sliding off-edge. Custom-category tabs keep
     their text label (those are user-defined names, not stable
     glyphs we can pick for them). */
  .emoji-tab-icon {
    font-size: 18px;
    line-height: 1;
    padding: 4px 8px;
  }

  .emoji-grid-container {
    overflow-y: auto;
    flex: 1;
    /* Without min-height:0 a flex child won't shrink below its content
       height, so the grid overflows the picker's max-height and gets
       clipped (a half-row at the edge) instead of scrolling internally. */
    min-height: 0;
    padding: var(--space-2);
  }

  .emoji-grid {
    display: grid;
    grid-template-columns: repeat(8, 1fr);
    gap: var(--space-1);
  }

  .emoji-item {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 100%;
    height: 34px;
    border: none;
    background: transparent;
    border-radius: var(--radius-md);
    cursor: pointer;
    font-size: 1.35rem;
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
