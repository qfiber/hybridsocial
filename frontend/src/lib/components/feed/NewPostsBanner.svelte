<script lang="ts">
  import { fly } from 'svelte/transition';
  import { cubicOut } from 'svelte/easing';
  import { t } from '$lib/stores/i18n.js';

  // Floating "N new posts" pill. Click → scroll to top + flush queue.

  let {
    count = 0,
    onclick
  }: {
    count: number;
    onclick?: () => void;
  } = $props();

  let display = $derived(count >= 10 ? '10+' : String(count));
  // Noun phrase only ("new posts"); the count sits in its own animated slot.
  // Grammatical agreement still keys off `count` via the plural resolver.
  let label = $derived($t('feed.new_posts', { count }));
</script>

{#if count > 0}
  <div
    class="npb-floater"
    in:fly={{ y: -24, duration: 280, easing: cubicOut }}
    out:fly={{ y: -24, duration: 180, easing: cubicOut }}
  >
    <button type="button" class="npb" onclick={() => onclick?.()} aria-label={$t('feed.new_posts_aria', { count, display })}>
      {#key count}
        <span class="npb-ripple" aria-hidden="true"></span>
      {/key}

      <span class="material-symbols-outlined npb-arrow" aria-hidden="true">arrow_upward</span>

      <span class="npb-num-slot" aria-hidden="true">
        {#key display}
          <span
            class="npb-num"
            in:fly={{ y: 14, duration: 260, easing: cubicOut }}
            out:fly={{ y: -14, duration: 260, easing: cubicOut }}
          >{display}</span>
        {/key}
      </span>

      <span class="npb-label">{label}</span>
    </button>
  </div>
{/if}

<style>
  .npb-floater {
    position: fixed;
    inset-block-start: calc(var(--header-height) + 12px);
    /* Physical `left`: centering is direction-neutral, and with
       `inset-inline-start` an RTL page anchors from the right while
       translateX(-50%) still shifts left — a full width off-center. */
    left: 50%;
    transform: translateX(-50%);
    z-index: 50;
    pointer-events: none;
  }

  .npb {
    pointer-events: auto;
    position: relative;
    overflow: hidden;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 10px 22px;
    background: var(--color-primary);
    color: var(--color-on-primary, #fff);
    border: none;
    border-radius: 9999px;
    font-size: var(--text-sm, 0.9rem);
    font-weight: 700;
    line-height: 1;
    cursor: pointer;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.22), 0 2px 6px rgba(0, 0, 0, 0.12);
    transition: transform 160ms ease, box-shadow 160ms ease;
  }

  .npb:hover {
    transform: translateY(-1px);
    box-shadow: 0 14px 34px rgba(0, 0, 0, 0.26), 0 3px 8px rgba(0, 0, 0, 0.14);
  }

  .npb:active {
    transform: translateY(0);
  }

  .npb-arrow {
    font-size: 18px;
    position: relative;
    z-index: 1;
  }

  /* Grid-based slot so the in/out digits overlap during the transition
     instead of nudging the siblings sideways. */
  .npb-num-slot {
    position: relative;
    display: inline-grid;
    grid-template-areas: 'n';
    min-width: 2.2ch;
    text-align: center;
    z-index: 1;
  }

  .npb-num {
    grid-area: n;
    font-variant-numeric: tabular-nums;
  }

  .npb-label {
    position: relative;
    z-index: 1;
  }

  .npb-ripple {
    position: absolute;
    inset: 50% 50% auto auto;
    width: 40px;
    height: 40px;
    margin: -20px -20px 0 0;
    border-radius: 50%;
    background: radial-gradient(
      circle,
      rgba(255, 255, 255, 0.6) 0%,
      rgba(255, 255, 255, 0.3) 40%,
      rgba(255, 255, 255, 0) 75%
    );
    pointer-events: none;
    transform-origin: center;
    animation: npb-ripple 700ms cubic-bezier(0.22, 0.8, 0.36, 1) forwards;
    z-index: 0;
  }

  @keyframes npb-ripple {
    0%   { transform: scale(0);   opacity: 0.9; }
    60%  { opacity: 0.6; }
    100% { transform: scale(9);   opacity: 0; }
  }

  @media (prefers-reduced-motion: reduce) {
    .npb,
    .npb-ripple,
    .npb-num {
      animation: none !important;
      transition: none !important;
    }
  }
</style>
