/**
 * Preload script for myWhisperer.
 * Exposes a secure, minimal API surface from the main process to the renderer
 * via Electron's contextBridge, keeping nodeIntegration disabled.
 */
import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('electronAPI', {
  /** Sends an audio buffer to the main process for Whisper transcription and GPT formatting. */
  sendAudio: (audioBuffer: ArrayBuffer) =>
    ipcRenderer.invoke('audio:process', audioBuffer),

  /** Retrieves the current application settings. */
  getSettings: () => ipcRenderer.invoke('settings:get'),

  /** Saves a partial settings update. */
  saveSettings: (settings: Record<string, unknown>) =>
    ipcRenderer.invoke('settings:save', settings),

  /** Retrieves the full transcription history. */
  getHistory: () => ipcRenderer.invoke('history:get'),

  /** Deletes a single history item by ID. */
  deleteHistoryItem: (id: string) =>
    ipcRenderer.invoke('history:delete', id),

  /** Clears all transcription history. */
  clearHistory: () => ipcRenderer.invoke('history:clear'),

  /** Copies text to the system clipboard. */
  copyToClipboard: (text: string) =>
    ipcRenderer.invoke('clipboard:copy', text),

  /** Pastes text into the currently active application. */
  pasteText: (text: string) =>
    ipcRenderer.invoke('clipboard:paste', text),

  /** Registers a callback for global hotkey recording toggle events. Returns an unsubscribe function. */
  onRecordingToggle: (callback: () => void) => {
    const handler = () => callback();
    ipcRenderer.on('recording:toggle', handler);
    return () => ipcRenderer.removeListener('recording:toggle', handler);
  },

  /** Registers a callback for push-to-talk recording start (keydown). Returns an unsubscribe function. */
  onRecordingStart: (callback: () => void) => {
    const handler = () => callback();
    ipcRenderer.on('recording:start', handler);
    return () => ipcRenderer.removeListener('recording:start', handler);
  },

  /** Registers a callback for push-to-talk recording stop (keyup). Returns an unsubscribe function. */
  onRecordingStop: (callback: () => void) => {
    const handler = () => callback();
    ipcRenderer.on('recording:stop', handler);
    return () => ipcRenderer.removeListener('recording:stop', handler);
  },

  /** Registers a callback for settings change events. Returns an unsubscribe function. */
  onSettingsChanged: (callback: (settings: unknown) => void) => {
    const handler = (_event: Electron.IpcRendererEvent, settings: unknown) =>
      callback(settings);
    ipcRenderer.on('settings:changed', handler);
    return () => ipcRenderer.removeListener('settings:changed', handler);
  },

  /** Minimizes the app window to the system tray. */
  minimizeToTray: () => ipcRenderer.send('window:minimize-to-tray'),

  /** Quits the application. */
  quitApp: () => ipcRenderer.send('app:quit'),

  /** Returns the list of available GPT models. */
  getAvailableModels: () => ipcRenderer.invoke('models:get'),

  /** Returns the current platform identifier (e.g. 'darwin', 'win32', 'linux'). */
  getPlatform: () => ipcRenderer.invoke('app:platform'),
});
