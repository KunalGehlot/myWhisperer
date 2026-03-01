import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('electronAPI', {
  sendAudio: (audioBuffer: ArrayBuffer) =>
    ipcRenderer.invoke('audio:process', audioBuffer),

  getSettings: () => ipcRenderer.invoke('settings:get'),

  saveSettings: (settings: Record<string, unknown>) =>
    ipcRenderer.invoke('settings:save', settings),

  getHistory: () => ipcRenderer.invoke('history:get'),

  deleteHistoryItem: (id: string) =>
    ipcRenderer.invoke('history:delete', id),

  clearHistory: () => ipcRenderer.invoke('history:clear'),

  copyToClipboard: (text: string) =>
    ipcRenderer.invoke('clipboard:copy', text),

  pasteText: (text: string) =>
    ipcRenderer.invoke('clipboard:paste', text),

  onRecordingToggle: (callback: () => void) => {
    const handler = () => callback();
    ipcRenderer.on('recording:toggle', handler);
    return () => ipcRenderer.removeListener('recording:toggle', handler);
  },

  onSettingsChanged: (callback: (settings: unknown) => void) => {
    const handler = (_event: Electron.IpcRendererEvent, settings: unknown) =>
      callback(settings);
    ipcRenderer.on('settings:changed', handler);
    return () => ipcRenderer.removeListener('settings:changed', handler);
  },

  minimizeToTray: () => ipcRenderer.send('window:minimize-to-tray'),

  quitApp: () => ipcRenderer.send('app:quit'),

  getAvailableModels: () => ipcRenderer.invoke('models:get'),

  platform: process.platform,
});
