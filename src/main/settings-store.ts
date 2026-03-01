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

const defaultSettings: AppSettings = {
  apiKey: '',
  whisperModel: 'whisper-1',
  gptModel: 'gpt-4',
  language: 'auto',
  hotkey: 'CommandOrControl+Shift+Space',
  theme: 'system',
  autoPaste: true,
  autoCopy: true,
  recordingMode: 'toggle',
  audioInputDevice: 'default',
  personalDictionary: [],
  formatPrompt: '',
};

class SettingsStore {
  private store: any;

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

  get(): AppSettings {
    return this.store.get('settings') as AppSettings;
  }

  save(partial: Partial<AppSettings>): void {
    const current = this.get();
    this.store.set('settings', { ...current, ...partial });
  }

  getHistory(): TranscriptionResult[] {
    return this.store.get('history') as TranscriptionResult[];
  }

  addHistoryItem(item: TranscriptionResult): void {
    const history = this.getHistory();
    history.unshift(item);
    this.store.set('history', history);
  }

  deleteHistoryItem(id: string): void {
    const history = this.getHistory();
    this.store.set(
      'history',
      history.filter((item: TranscriptionResult) => item.id !== id)
    );
  }

  clearHistory(): void {
    this.store.set('history', []);
  }
}

export { SettingsStore, AppSettings, TranscriptionResult };
