import '@testing-library/jest-dom/vitest';

// Mock window.electronAPI for renderer tests
const mockElectronAPI = {
  sendAudio: vi.fn(),
  getSettings: vi.fn().mockResolvedValue({
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
    gptFormattingLevel: 70,
  }),
  saveSettings: vi.fn(),
  getHistory: vi.fn().mockResolvedValue([]),
  deleteHistoryItem: vi.fn(),
  clearHistory: vi.fn(),
  copyToClipboard: vi.fn(),
  pasteText: vi.fn(),
  onRecordingToggle: vi.fn(() => vi.fn()),
  onRecordingStart: vi.fn(() => vi.fn()),
  onRecordingStop: vi.fn(() => vi.fn()),
  onSettingsChanged: vi.fn(() => vi.fn()),
  minimizeToTray: vi.fn(),
  quitApp: vi.fn(),
  getAvailableModels: vi.fn().mockResolvedValue(['gpt-4', 'gpt-4-turbo', 'gpt-4o', 'gpt-4o-mini', 'gpt-3.5-turbo']),
  getPlatform: vi.fn().mockResolvedValue('darwin'),
};

if (typeof window !== 'undefined') {
  Object.defineProperty(window, 'electronAPI', {
    value: mockElectronAPI,
    writable: true,
  });
}
