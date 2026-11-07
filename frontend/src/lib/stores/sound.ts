/**
 * Plays short notification + message sounds in response to realtime
 * events. Two dials, both stored in localStorage so the user's
 * preference persists across sessions:
 *
 *   - `sound_message_enabled`       — DM arrival sound (default on)
 *   - `sound_notification_enabled`  — bell sound for non-DM notifs (default on)
 *
 * The audio files live at `/sounds/message.mp3` and
 * `/sounds/notification.mp3` (served from `static/`). A missing file just
 * means that sound stays silent.
 *
 * Browsers block audio until the user has interacted with the page, so the
 * first click or key press creates and resumes an AudioContext. Nothing is
 * played to do that. An earlier version unlocked by "silently" playing
 * <audio> elements at volume 0, which could be heard: iOS ignores `volume`, and
 * elsewhere it could let a blip out, so a first click seemed to ring the bell.
 */

import { browser } from '$app/environment';

const MESSAGE_KEY = 'sound_message_enabled';
const NOTIFICATION_KEY = 'sound_notification_enabled';

const SOUND_URLS = {
  message: '/sounds/message.mp3',
  notification: '/sounds/notification.mp3',
} as const;

type SoundName = keyof typeof SOUND_URLS;

// How long a tab keeps the claim on one event. Long enough to cover sibling tabs
// receiving the same event a moment later over their own streams.
const TAB_CLAIM_MS = 3000;

let context: AudioContext | null = null;
const buffers: Partial<Record<SoundName, AudioBuffer>> = {};
let initialized = false;

export function initSound(): void {
  if (!browser || initialized) return;
  initialized = true;

  // These stay on: a browser can suspend the context later (iOS does on an
  // interruption), and the next gesture has to be able to resume it.
  window.addEventListener('click', unlock, { passive: true });
  window.addEventListener('keydown', unlock, { passive: true });
}

function unlock(): void {
  if (context?.state === 'running') return;

  try {
    if (!context) {
      context = new AudioContext();
      for (const name of Object.keys(SOUND_URLS) as SoundName[]) void load(name, context);
    }
    void context.resume().catch(() => {
      // Still blocked. The next gesture tries again.
    });
  } catch {
    // No Web Audio here, so sounds stay off.
  }
}

async function load(name: SoundName, ctx: AudioContext): Promise<void> {
  try {
    const response = await fetch(SOUND_URLS[name]);
    if (!response.ok) return;
    buffers[name] = await ctx.decodeAudioData(await response.arrayBuffer());
  } catch {
    // Missing or undecodable file: this sound stays silent.
  }
}

export function playMessageSound(eventKey?: string): void {
  if (!browser || localStorage.getItem(MESSAGE_KEY) === 'false') return;
  play('message', eventKey);
}

export function playNotificationSound(eventKey?: string): void {
  if (!browser || localStorage.getItem(NOTIFICATION_KEY) === 'false') return;
  play('notification', eventKey);
}

function play(name: SoundName, eventKey?: string): void {
  // A tab that can't make a sound mustn't win the claim below, or it would
  // silence a sibling tab that can.
  if (!context || context.state !== 'running' || !buffers[name]) return;

  if (eventKey && navigator.locks) {
    // Each tab has its own stream, so each gets every event. Only the first to
    // claim this one plays it.
    void navigator.locks
      .request(`hybridsocial:sound:${eventKey}`, { ifAvailable: true }, async (lock) => {
        if (!lock) return;
        start(name);
        await new Promise((resolve) => setTimeout(resolve, TAB_CLAIM_MS));
      })
      .catch(() => start(name));
  } else {
    start(name);
  }
}

function start(name: SoundName): void {
  const buffer = buffers[name];
  if (!context || !buffer) return;

  try {
    const source = context.createBufferSource();
    source.buffer = buffer;
    source.connect(context.destination);
    source.start();
  } catch {
    // Decoder or device trouble: skip this one.
  }
}

export function setMessageSoundEnabled(enabled: boolean): void {
  if (!browser) return;
  localStorage.setItem(MESSAGE_KEY, enabled ? 'true' : 'false');
}

export function setNotificationSoundEnabled(enabled: boolean): void {
  if (!browser) return;
  localStorage.setItem(NOTIFICATION_KEY, enabled ? 'true' : 'false');
}

export function getMessageSoundEnabled(): boolean {
  if (!browser) return true;
  return localStorage.getItem(MESSAGE_KEY) !== 'false';
}

export function getNotificationSoundEnabled(): boolean {
  if (!browser) return true;
  return localStorage.getItem(NOTIFICATION_KEY) !== 'false';
}
