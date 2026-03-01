export interface TranscriptionResult {
  id: string;
  rawText: string;
  formattedText: string;
  timestamp: number;
  duration: number;
  language: string;
  model: string;
}

export interface AppSettings {
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

export interface ProcessingState {
  isProcessing: boolean;
  progress: number;
  statusMessage: string;
}

export type GPTModel =
  | 'gpt-4.1'
  | 'gpt-4.1-mini'
  | 'gpt-4.1-nano'
  | 'gpt-4o'
  | 'gpt-4o-mini'
  | 'o4-mini'
  | 'o3'
  | 'o3-mini'
  | 'o1'
  | 'o1-mini'
  | 'gpt-4-turbo'
  | 'gpt-4';

export interface AudioDevice {
  deviceId: string;
  label: string;
  isDefault: boolean;
}

export interface ElectronAPI {
  sendAudio: (audioBuffer: ArrayBuffer) => Promise<TranscriptionResult>;
  getSettings: () => Promise<AppSettings>;
  saveSettings: (settings: Partial<AppSettings>) => Promise<void>;
  getHistory: () => Promise<TranscriptionResult[]>;
  deleteHistoryItem: (id: string) => Promise<void>;
  clearHistory: () => Promise<void>;
  copyToClipboard: (text: string) => Promise<void>;
  pasteText: (text: string) => Promise<void>;
  onRecordingToggle: (callback: () => void) => () => void;
  onRecordingStart: (callback: () => void) => () => void;
  onRecordingStop: (callback: () => void) => () => void;
  onSettingsChanged: (callback: (settings: AppSettings) => void) => () => void;
  minimizeToTray: () => void;
  quitApp: () => void;
  getAvailableModels: () => Promise<string[]>;
  getPlatform: () => Promise<string>;
}

declare global {
  interface Window {
    electronAPI: ElectronAPI;
  }
}
