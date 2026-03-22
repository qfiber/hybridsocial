<script lang="ts">
  let {
    name = ''
  }: {
    name?: string;
  } = $props();
</script>

<div class="typing-indicator" aria-live="polite" aria-label="{name} is typing">
  <span class="typing-text">{name} is typing</span>
  <span class="typing-dots" aria-hidden="true">
    <span class="dot"></span>
    <span class="dot"></span>
    <span class="dot"></span>
  </span>
</div>

<style>
  .typing-indicator {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    padding: var(--space-1) var(--space-4);
    padding-inline-start: calc(28px + var(--space-2) + var(--space-4));
  }

  .typing-text {
    font-size: var(--text-xs);
    color: var(--color-text-tertiary);
    font-style: italic;
  }

  .typing-dots {
    display: flex;
    gap: 3px;
    align-items: center;
  }

  .dot {
    width: 5px;
    height: 5px;
    border-radius: var(--radius-full);
    background: var(--color-text-tertiary);
    animation: typing-bounce 1.4s ease-in-out infinite;
  }

  .dot:nth-child(2) {
    animation-delay: 0.2s;
  }

  .dot:nth-child(3) {
    animation-delay: 0.4s;
  }

  @keyframes typing-bounce {
    0%, 60%, 100% {
      transform: translateY(0);
      opacity: 0.4;
    }
    30% {
      transform: translateY(-4px);
      opacity: 1;
    }
  }
</style>
