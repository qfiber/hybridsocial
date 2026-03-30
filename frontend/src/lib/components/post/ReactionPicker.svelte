<script lang="ts">
  let {
    selected = null,
    onselect,
  }: {
    selected?: string | null;
    onselect: (emoji: string) => void;
  } = $props();

  const reactions = [
    { emoji: '\u{1F600}', type: 'like', label: 'Like' },
    { emoji: '\u{2764}\u{FE0F}', type: 'love', label: 'Love' },
    { emoji: '\u{1F917}', type: 'care', label: 'Care' },
    { emoji: '\u{1F621}', type: 'angry', label: 'Angry' },
    { emoji: '\u{1F622}', type: 'sad', label: 'Sad' },
    { emoji: '\u{1F602}', type: 'lol', label: 'LOL' },
    { emoji: '\u{1F92F}', type: 'wow', label: 'Wow' },
  ];

  function handleClick(e: MouseEvent, type: string) {
    e.stopPropagation();
    onselect(type);
  }

  function handleKeydown(e: KeyboardEvent, type: string) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      e.stopPropagation();
      onselect(type);
    }
  }
</script>

<div
  class="reaction-picker"
  role="group"
  aria-label="Reactions"
  onclick={(e) => e.stopPropagation()}
>
  {#each reactions as reaction, i (reaction.type)}
    <button
      type="button"
      class="reaction-btn"
      class:reaction-selected={selected === reaction.type}
      style="animation-delay: {80 + i * 40}ms"
      onclick={(e) => handleClick(e, reaction.type)}
      onkeydown={(e) => handleKeydown(e, reaction.type)}
      aria-label={reaction.label}
      aria-pressed={selected === reaction.type}
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
    transform-origin: bottom center;
    animation: picker-unfold 0.25s cubic-bezier(0.22, 1, 0.36, 1) forwards;
  }

  @keyframes picker-unfold {
    0% {
      opacity: 0;
      transform: scaleX(0.3) scaleY(0.6);
    }
    100% {
      opacity: 1;
      transform: scaleX(1) scaleY(1);
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
    transition: transform 150ms cubic-bezier(0.34, 1.56, 0.64, 1), background-color 150ms ease;
    opacity: 0;
    transform: scale(0) translateY(8px);
    animation: emoji-pop 0.35s cubic-bezier(0.34, 1.56, 0.64, 1) forwards;
  }

  @keyframes emoji-pop {
    0% {
      opacity: 0;
      transform: scale(0) translateY(8px);
    }
    60% {
      opacity: 1;
      transform: scale(1.2) translateY(-2px);
    }
    100% {
      opacity: 1;
      transform: scale(1) translateY(0);
    }
  }

  .reaction-btn:hover {
    transform: scale(1.3) translateY(-4px);
    background: var(--color-bg-tertiary);
  }

  .reaction-btn:hover .reaction-emoji {
    animation: emoji-wiggle 0.5s ease;
  }

  @keyframes emoji-wiggle {
    0% { transform: rotate(0deg); }
    20% { transform: rotate(-12deg) scale(1.1); }
    40% { transform: rotate(10deg) scale(1.1); }
    60% { transform: rotate(-6deg); }
    80% { transform: rotate(4deg); }
    100% { transform: rotate(0deg); }
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
