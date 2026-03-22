<script lang="ts">
  let {
    selected = null,
    onselect,
  }: {
    selected?: string | null;
    onselect: (emoji: string) => void;
  } = $props();

  const reactions = [
    { emoji: '\u{1F600}', label: 'Like' },
    { emoji: '\u{2764}\u{FE0F}', label: 'Love' },
    { emoji: '\u{1F917}', label: 'Care' },
    { emoji: '\u{1F621}', label: 'Angry' },
    { emoji: '\u{1F622}', label: 'Sad' },
    { emoji: '\u{1F602}', label: 'LOL' },
    { emoji: '\u{1F92F}', label: 'WTF' },
  ];

  function handleClick(e: MouseEvent, emoji: string) {
    e.stopPropagation();
    onselect(emoji);
  }

  function handleKeydown(e: KeyboardEvent, emoji: string) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      e.stopPropagation();
      onselect(emoji);
    }
  }
</script>

<div
  class="reaction-picker"
  role="group"
  aria-label="Reactions"
  onclick={(e) => e.stopPropagation()}
>
  {#each reactions as reaction (reaction.emoji)}
    <button
      type="button"
      class="reaction-btn"
      class:reaction-selected={selected === reaction.emoji}
      onclick={(e) => handleClick(e, reaction.emoji)}
      onkeydown={(e) => handleKeydown(e, reaction.emoji)}
      aria-label={reaction.label}
      aria-pressed={selected === reaction.emoji}
    >
      <span class="reaction-emoji">{reaction.emoji}</span>
    </button>
  {/each}
</div>

<style>
  .reaction-picker {
    display: flex;
    align-items: center;
    gap: var(--space-1);
    padding: var(--space-2);
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-full);
    box-shadow: var(--shadow-lg);
    animation: picker-enter 0.2s ease;
  }

  @keyframes picker-enter {
    from {
      opacity: 0;
      transform: translateY(8px) scale(0.95);
    }
    to {
      opacity: 1;
      transform: translateY(0) scale(1);
    }
  }

  .reaction-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    background: transparent;
    border: none;
    border-radius: var(--radius-full);
    cursor: pointer;
    transition: transform var(--transition-fast), background-color var(--transition-fast);
  }

  .reaction-btn:hover {
    transform: scale(1.25);
    background: var(--color-bg-tertiary);
  }

  .reaction-btn:focus-visible {
    outline: 2px solid var(--color-primary);
    outline-offset: 1px;
  }

  .reaction-selected {
    background: var(--color-primary-light);
  }

  .reaction-selected:hover {
    background: var(--color-primary-light);
  }

  .reaction-emoji {
    font-size: 1.25rem;
    line-height: 1;
  }
</style>
