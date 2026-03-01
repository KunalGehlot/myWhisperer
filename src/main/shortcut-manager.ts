/**
 * Shortcut manager for myWhisperer.
 * Abstracts over Electron's globalShortcut (toggle mode) and uiohook-napi (push-to-talk mode).
 * uiohook-napi is lazy-loaded only when push-to-talk is activated, because it requires
 * macOS Accessibility permissions and will crash the app if loaded without them.
 */
import { globalShortcut } from 'electron';

// Lazy-loaded uiohook references — only populated when push-to-talk is used
let uIOhookModule: typeof import('uiohook-napi') | null = null;

function getUiohook(): typeof import('uiohook-napi') {
  if (!uIOhookModule) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    uIOhookModule = require('uiohook-napi');
  }
  return uIOhookModule!;
}

interface ShortcutCallbacks {
  onRecordingToggle: () => void;
  onRecordingStart: () => void;
  onRecordingStop: () => void;
}

/**
 * Maps an Electron accelerator key name to a uiohook keycode.
 * Supports common keys used in keyboard shortcuts.
 */
function electronKeyToUiohook(key: string): number | null {
  const { UiohookKey } = getUiohook();
  const map: Record<string, number> = {
    space: UiohookKey.Space,
    enter: UiohookKey.Enter,
    tab: UiohookKey.Tab,
    escape: UiohookKey.Escape,
    backspace: UiohookKey.Backspace,
    delete: UiohookKey.Delete,
    insert: UiohookKey.Insert,
    home: UiohookKey.Home,
    end: UiohookKey.End,
    pageup: UiohookKey.PageUp,
    pagedown: UiohookKey.PageDown,
    up: UiohookKey.ArrowUp,
    down: UiohookKey.ArrowDown,
    left: UiohookKey.ArrowLeft,
    right: UiohookKey.ArrowRight,
  };

  // Single letter keys A-Z
  if (key.length === 1 && /[a-z]/i.test(key)) {
    const upper = key.toUpperCase() as keyof typeof UiohookKey;
    if (upper in UiohookKey) {
      return UiohookKey[upper] as number;
    }
  }

  // F-keys
  const fMatch = key.match(/^f(\d+)$/i);
  if (fMatch) {
    const fKey = `F${fMatch[1]}` as keyof typeof UiohookKey;
    if (fKey in UiohookKey) {
      return UiohookKey[fKey] as number;
    }
  }

  return map[key.toLowerCase()] ?? null;
}

/**
 * Parses an Electron accelerator string into modifier flags and a main key.
 * Examples: "Control+Space", "CommandOrControl+Shift+Space", "Alt+F1"
 */
function parseAccelerator(accelerator: string): {
  ctrl: boolean;
  alt: boolean;
  shift: boolean;
  meta: boolean;
  keycode: number | null;
} {
  const parts = accelerator.split('+');
  let ctrl = false;
  let alt = false;
  let shift = false;
  let meta = false;
  let mainKey = '';

  for (const part of parts) {
    const lower = part.toLowerCase().trim();
    switch (lower) {
      case 'control':
      case 'ctrl':
        ctrl = true;
        break;
      case 'commandorcontrol':
      case 'cmdorctrl':
        // On macOS, use Meta (Cmd); on others, use Ctrl
        if (process.platform === 'darwin') {
          meta = true;
        } else {
          ctrl = true;
        }
        break;
      case 'command':
      case 'cmd':
      case 'meta':
      case 'super':
        meta = true;
        break;
      case 'alt':
      case 'option':
        alt = true;
        break;
      case 'shift':
        shift = true;
        break;
      default:
        mainKey = part;
    }
  }

  return {
    ctrl,
    alt,
    shift,
    meta,
    keycode: mainKey ? electronKeyToUiohook(mainKey) : null,
  };
}

// Use a generic type for event handlers since the module is lazy-loaded
type KeyboardEventHandler = (e: { keycode: number; ctrlKey: boolean; altKey: boolean; shiftKey: boolean; metaKey: boolean }) => void;

export class ShortcutManager {
  private callbacks: ShortcutCallbacks;
  private currentHotkey: string | null = null;
  private currentMode: 'toggle' | 'push-to-talk' = 'toggle';
  private uiohookStarted = false;
  private isHeld = false;

  private keydownHandler: KeyboardEventHandler | null = null;
  private keyupHandler: KeyboardEventHandler | null = null;

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

  /** Unregisters the current shortcut and cleans up listeners. */
  unregister(): void {
    if (this.currentMode === 'toggle' && this.currentHotkey) {
      try {
        globalShortcut.unregister(this.currentHotkey);
      } catch {
        // Already unregistered
      }
    }

    this.removeUiohookListeners();
    this.currentHotkey = null;
    this.isHeld = false;
  }

  /** Fully destroys the manager, stopping uiohook and unregistering all shortcuts. */
  destroy(): void {
    this.unregister();
    this.stopUiohook();
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

  private registerPushToTalk(hotkey: string): boolean {
    try {
      const parsed = parseAccelerator(hotkey);
      if (parsed.keycode === null) {
        console.error('Could not parse hotkey for push-to-talk:', hotkey);
        return false;
      }

      const { uIOhook } = getUiohook();

      this.keydownHandler = (e) => {
        if (this.isHeld) return; // Prevent repeat keydown events
        if (this.matchesHotkey(e, parsed)) {
          this.isHeld = true;
          this.callbacks.onRecordingStart();
        }
      };

      this.keyupHandler = (e) => {
        if (!this.isHeld) return;
        // Stop when the main key is released, or when a required modifier is released
        if (this.isReleaseEvent(e, parsed)) {
          this.isHeld = false;
          this.callbacks.onRecordingStop();
        }
      };

      uIOhook.on('keydown', this.keydownHandler);
      uIOhook.on('keyup', this.keyupHandler);
      this.startUiohook();

      return true;
    } catch (err) {
      console.error(
        'Failed to initialize push-to-talk. On macOS, ensure Accessibility permissions are granted in System Settings > Privacy & Security > Accessibility.',
        err
      );
      // Fall back to toggle mode so the app remains usable
      console.warn('Falling back to toggle mode.');
      this.currentMode = 'toggle';
      return this.registerToggle(hotkey);
    }
  }

  /** Checks if a keyboard event matches the configured hotkey (modifiers + main key). */
  private matchesHotkey(
    e: { keycode: number; ctrlKey: boolean; altKey: boolean; shiftKey: boolean; metaKey: boolean },
    parsed: ReturnType<typeof parseAccelerator>
  ): boolean {
    return (
      e.keycode === parsed.keycode &&
      e.ctrlKey === parsed.ctrl &&
      e.altKey === parsed.alt &&
      e.shiftKey === parsed.shift &&
      e.metaKey === parsed.meta
    );
  }

  /** Checks if a keyup event means the hotkey combo is no longer held. */
  private isReleaseEvent(
    e: { keycode: number; ctrlKey: boolean; altKey: boolean; shiftKey: boolean; metaKey: boolean },
    parsed: ReturnType<typeof parseAccelerator>
  ): boolean {
    // Main key released
    if (e.keycode === parsed.keycode) return true;
    // Any required modifier released
    if (parsed.ctrl && !e.ctrlKey) return true;
    if (parsed.alt && !e.altKey) return true;
    if (parsed.shift && !e.shiftKey) return true;
    if (parsed.meta && !e.metaKey) return true;
    return false;
  }

  private removeUiohookListeners(): void {
    if (uIOhookModule && (this.keydownHandler || this.keyupHandler)) {
      const { uIOhook } = uIOhookModule;
      if (this.keydownHandler) {
        uIOhook.removeListener('keydown', this.keydownHandler);
        this.keydownHandler = null;
      }
      if (this.keyupHandler) {
        uIOhook.removeListener('keyup', this.keyupHandler);
        this.keyupHandler = null;
      }
    }
  }

  private startUiohook(): void {
    if (!this.uiohookStarted && uIOhookModule) {
      try {
        uIOhookModule.uIOhook.start();
        this.uiohookStarted = true;
      } catch (err) {
        console.error('Failed to start uiohook:', err);
      }
    }
  }

  private stopUiohook(): void {
    if (this.uiohookStarted && uIOhookModule) {
      try {
        uIOhookModule.uIOhook.stop();
      } catch {
        // May already be stopped
      }
      this.uiohookStarted = false;
    }
  }
}
