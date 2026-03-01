/**
 * Persistent settings and history storage for myWhisperer.
 * Uses electron-store for disk persistence and safeStorage for API key encryption.
 */
import { safeStorage } from 'electron';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const Store = require('electron-store');

interface AppSettings {
  apiKey: string;
  whisperModel: string;
  gptModel: string;
  language: string;
  hotkey: string;
  theme: 'light' | 'dark' | 'system';
  autoPaste: boolean;
  autoCopy: boolean;
  recordingMode: 'push-to-talk' | 'toggle';
  audioInputDevice: string;
  personalDictionary: string[];
  formatPrompt: string;
  gptFormattingLevel: number;
}

interface TranscriptionResult {
  id: string;
  rawText: string;
  formattedText: string;
  timestamp: number;
  duration: number;
  language: string;
  model: string;
}

interface StoreSchema {
  settings: AppSettings;
  history: TranscriptionResult[];
}

const MAX_HISTORY_SIZE = 500;

const defaultSettings: AppSettings = {
  apiKey: '',
  whisperModel: 'whisper-1',
  gptModel: 'gpt-4',
  language: 'auto',
  hotkey: 'Control+Space',
  theme: 'system',
  autoPaste: true,
  autoCopy: true,
  recordingMode: 'toggle',
  audioInputDevice: 'default',
  personalDictionary: [],
  formatPrompt: '',
  gptFormattingLevel: 70,
};

/** Manages application settings and transcription history with encrypted API key storage. */
class SettingsStore {
  private store: InstanceType<typeof Store>;

  constructor() {
    const StoreClass = Store.default || Store;
    this.store = new StoreClass({
      name: 'mywhisperer-settings',
      defaults: {
        settings: defaultSettings,
        history: [],
      },
    });
  }

  /** Returns current application settings, decrypting the API key if safeStorage is available. */
  get(): AppSettings {
    const stored = this.store.get('settings') as Partial<StoreSchema['settings']>;
    const settings = { ...defaultSettings, ...stored };
    return {
      ...settings,
      apiKey: this.decryptApiKey(settings.apiKey),
    };
  }

  /** Saves a partial settings update, encrypting the API key if present. */
  save(partial: Partial<AppSettings>): void {
    const current = this.store.get('settings') as StoreSchema['settings'];
    const merged = { ...current, ...partial };

    if (partial.apiKey !== undefined) {
      merged.apiKey = this.encryptApiKey(partial.apiKey);
    }

    this.store.set('settings', merged);
  }

  /** Returns the full transcription history, newest first. */
  getHistory(): TranscriptionResult[] {
    return this.store.get('history') as StoreSchema['history'];
  }

  /** Prepends a transcription result to history, capping at the maximum size. */
  addHistoryItem(item: TranscriptionResult): void {
    const history = this.getHistory();
    history.unshift(item);
    if (history.length > MAX_HISTORY_SIZE) {
      history.length = MAX_HISTORY_SIZE;
    }
    this.store.set('history', history);
  }

  /** Removes a single history item by its unique ID. */
  deleteHistoryItem(id: string): void {
    const history = this.getHistory();
    this.store.set(
      'history',
      history.filter((item: TranscriptionResult) => item.id !== id)
    );
  }

  /** Clears all transcription history. */
  clearHistory(): void {
    this.store.set('history', []);
  }

  /** Encrypts an API key using Electron's safeStorage, falling back to plaintext. */
  private encryptApiKey(apiKey: string): string {
    if (!apiKey) return apiKey;
    try {
      if (safeStorage.isEncryptionAvailable()) {
        return safeStorage.encryptString(apiKey).toString('base64');
      }
    } catch (err) {
      console.warn('safeStorage encryption unavailable, storing API key in plaintext:', err);
    }
    return apiKey;
  }

  /** Decrypts an API key using Electron's safeStorage, falling back to returning as-is. */
  private decryptApiKey(storedValue: string): string {
    if (!storedValue) return storedValue;
    try {
      if (safeStorage.isEncryptionAvailable()) {
        const buffer = Buffer.from(storedValue, 'base64');
        return safeStorage.decryptString(buffer);
      }
    } catch {
      // Value was stored as plaintext (pre-encryption migration) or decryption failed
    }
    return storedValue;
  }
}

export { SettingsStore, AppSettings, TranscriptionResult };
