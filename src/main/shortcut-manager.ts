/**
 * Shortcut manager for myWhisperer.
 * Uses Electron's globalShortcut for both toggle and push-to-talk modes.
 *
 * Push-to-talk works by detecting key-repeat: globalShortcut fires repeatedly
 * while a key is held. A debounce timer detects when the key is released
 * (no callback within 300ms = key released = stop recording).
 */
import { globalShortcut } from 'electron';

interface ShortcutCallbacks {
  onRecordingToggle: () => void;
  onRecordingStart: () => void;
  onRecordingStop: () => void;
}

export class ShortcutManager {
  private callbacks: ShortcutCallbacks;
  private currentHotkey: string | null = null;
  private currentMode: 'toggle' | 'push-to-talk' = 'toggle';
  private isHeld = false;
  private releaseTimer: ReturnType<typeof setTimeout> | null = null;

  /** How long after the last key-repeat before we consider the key released. */
  private static readonly RELEASE_TIMEOUT_MS = 300;

  constructor(callbacks: ShortcutCallbacks) {
    this.callbacks = callbacks;
  }

  /** Registers a hotkey in the specified mode. Unregisters any previous registration first. */
  register(hotkey: string, mode: 'toggle' | 'push-to-talk'): boolean {
    this.unregister();

    this.currentHotkey = hotkey;
    this.currentMode = mode;

    if (mode === 'toggle') {
      return this.registerToggle(hotkey);
    } else {
      return this.registerPushToTalk(hotkey);
    }
  }

  /** Unregisters the current shortcut and cleans up timers. */
  unregister(): void {
    if (this.currentHotkey) {
      try {
        globalShortcut.unregister(this.currentHotkey);
      } catch {
        // Already unregistered
      }
    }

    this.clearReleaseTimer();
    this.currentHotkey = null;
    this.isHeld = false;
  }

  /** Fully destroys the manager. */
  destroy(): void {
    this.unregister();
  }

  private registerToggle(hotkey: string): boolean {
    try {
      const registered = globalShortcut.register(hotkey, () => {
        this.callbacks.onRecordingToggle();
      });
      if (!registered) {
        console.error('Failed to register global shortcut:', hotkey);
      }
      return registered;
    } catch (err) {
      console.error('Error registering global shortcut:', err);
      return false;
    }
  }

  /**
   * Push-to-talk using globalShortcut key-repeat detection.
   *
   * When a key combo is held, the OS fires key-repeat events at ~30-100ms intervals.
   * globalShortcut fires its callback on each repeat. We use a debounce timer:
   * - First fire: start recording
   * - Subsequent fires (key repeats): reset the release timer
   * - Timer expires (no fire for 300ms): key was released → stop recording
   */
  private registerPushToTalk(hotkey: string): boolean {
    try {
      const registered = globalShortcut.register(hotkey, () => {
        this.clearReleaseTimer();

        if (!this.isHeld) {
          // First press — start recording
          this.isHeld = true;
          this.callbacks.onRecordingStart();
        }

        // Reset the release detection timer
        this.releaseTimer = setTimeout(() => {
          if (this.isHeld) {
            this.isHeld = false;
            this.callbacks.onRecordingStop();
          }
        }, ShortcutManager.RELEASE_TIMEOUT_MS);
      });

      if (!registered) {
        console.error('Failed to register global shortcut for push-to-talk:', hotkey);
      }
      return registered;
    } catch (err) {
      console.error('Error registering push-to-talk shortcut:', err);
      return false;
    }
  }

  private clearReleaseTimer(): void {
    if (this.releaseTimer) {
      clearTimeout(this.releaseTimer);
      this.releaseTimer = null;
    }
  }
}
