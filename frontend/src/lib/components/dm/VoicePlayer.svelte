<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { t } from '$lib/stores/i18n.js';

  // A compact voice-note player for DM audio attachments (and the composer
  // preview). The native <audio controls> collapsed to nothing inside a
  // shrink-to-fit bubble on phones, looks different in every browser, and
  // can't show the length of a MediaRecorder WebM clip (its duration is
  // Infinity until the file has been scanned).
  let { src }: { src: string } = $props();

  let audio = $state<HTMLAudioElement | null>(null);
  let playing = $state(false);
  let current = $state(0);
  let duration = $state(0);
  let failed = $state(false);

  // Only one voice note plays at a time across the page.
  const PLAY_EVENT = 'hs-voice-play';

  function onOtherPlay(e: Event) {
    if ((e as CustomEvent).detail !== audio && audio && !audio.paused) audio.pause();
  }

  onMount(() => window.addEventListener(PLAY_EVENT, onOtherPlay));
  onDestroy(() => {
    if (typeof window !== 'undefined') window.removeEventListener(PLAY_EVENT, onOtherPlay);
    audio?.pause();
  });

  function fmt(s: number): string {
    if (!Number.isFinite(s) || s < 0) s = 0;
    const total = Math.floor(s);
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
  }

  // Chrome writes MediaRecorder WebM without a duration, so the element
  // reports Infinity. Seeking past the end forces a scan; the real duration
  // is known on the next timeupdate, then we rewind.
  let probing = false;
  function onLoadedMetadata() {
    if (!audio) return;
    if (Number.isFinite(audio.duration)) {
      duration = audio.duration;
      return;
    }
    probing = true;
    audio.currentTime = 1e101;
  }

  function onTimeUpdate() {
    if (!audio) return;
    if (probing) {
      probing = false;
      if (Number.isFinite(audio.duration)) duration = audio.duration;
      audio.currentTime = 0;
      current = 0;
      return;
    }
    current = audio.currentTime;
  }

  function onDurationChange() {
    if (audio && Number.isFinite(audio.duration)) duration = audio.duration;
  }

  async function toggle() {
    if (!audio) return;
    if (audio.paused) {
      window.dispatchEvent(new CustomEvent(PLAY_EVENT, { detail: audio }));
      try {
        await audio.play();
      } catch {
        failed = true;
      }
    } else {
      audio.pause();
    }
  }

  function seek(e: Event) {
    if (!audio || !duration) return;
    const v = Number((e.currentTarget as HTMLInputElement).value);
    audio.currentTime = v;
    current = v;
  }

  let progress = $derived(duration > 0 ? Math.min(100, (current / duration) * 100) : 0);
</script>

<!-- Media transport reads left→right in every locale (like the Streams
     player clock), so the row is pinned LTR. -->
<div class="voice-player" dir="ltr">
  <audio
    bind:this={audio}
    {src}
    preload="metadata"
    onloadedmetadata={onLoadedMetadata}
    ondurationchange={onDurationChange}
    ontimeupdate={onTimeUpdate}
    onplay={() => (playing = true)}
    onpause={() => (playing = false)}
    onended={() => {
      playing = false;
      current = 0;
    }}
    onerror={() => (failed = true)}
  ></audio>

  {#if failed}
    <a class="voice-fallback" href={src} target="_blank" rel="noopener noreferrer">
      <span class="material-symbols-outlined" aria-hidden="true">download</span>
      {$t('dm.voice_unavailable')}
    </a>
  {:else}
    <button
      type="button"
      class="voice-toggle"
      onclick={toggle}
      aria-label={playing ? $t('dm.voice_pause') : $t('dm.voice_play')}
    >
      <span class="material-symbols-outlined" aria-hidden="true">{playing ? 'pause' : 'play_arrow'}</span>
    </button>
    <input
      class="voice-seek"
      type="range"
      min="0"
      max={duration || 0}
      step="0.1"
      value={current}
      oninput={seek}
      disabled={!duration}
      style="--voice-progress: {progress}%"
      aria-label={$t('dm.voice_seek')}
    />
    <span class="voice-time">{fmt(playing || current > 0 ? current : duration)}</span>
  {/if}
</div>

<style>
  .voice-player {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    /* A definite width (not a percentage) so a shrink-to-fit bubble sizes
       around the player instead of collapsing it. */
    width: 240px;
    max-width: 100%;
    color: inherit;
  }

  .voice-player audio {
    display: none;
  }

  .voice-toggle {
    flex-shrink: 0;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    padding: 0;
    border: none;
    border-radius: 50%;
    background: rgba(127, 127, 127, 0.22);
    color: inherit;
    cursor: pointer;
  }

  .voice-toggle .material-symbols-outlined {
    font-size: 22px;
  }

  @media (pointer: coarse) {
    .voice-toggle {
      width: 44px;
      height: 44px;
    }
  }

  .voice-seek {
    flex: 1;
    min-width: 0;
    height: 4px;
    margin: 0;
    appearance: none;
    -webkit-appearance: none;
    border-radius: 999px;
    background: linear-gradient(
      to right,
      currentColor var(--voice-progress, 0%),
      rgba(127, 127, 127, 0.35) var(--voice-progress, 0%)
    );
    cursor: pointer;
  }

  .voice-seek:disabled {
    cursor: default;
  }

  .voice-seek::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: currentColor;
  }

  .voice-seek::-moz-range-thumb {
    width: 12px;
    height: 12px;
    border: none;
    border-radius: 50%;
    background: currentColor;
  }

  .voice-time {
    flex-shrink: 0;
    min-width: 3ch;
    font-size: var(--text-xs);
    font-variant-numeric: tabular-nums;
    opacity: 0.85;
  }

  .voice-fallback {
    display: inline-flex;
    align-items: center;
    gap: var(--space-1);
    color: inherit;
    font-size: var(--text-sm);
  }
</style>
