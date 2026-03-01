import {
  app,
  BrowserWindow,
  ipcMain,
  globalShortcut,
} from 'electron';
import * as path from 'path';
import * as crypto from 'crypto';
import { SettingsStore } from './settings-store';
import { WhisperService } from './whisper-service';
import { GPTService } from './gpt-service';
import { copyToClipboard, pasteToActiveApp } from './clipboard-manager';
import { TrayManager } from './tray-manager';

let mainWindow: BrowserWindow | null = null;
let trayManager: TrayManager | null = null;
let isQuitting = false;

const settingsStore = new SettingsStore();
const whisperService = new WhisperService();
const gptService = new GPTService();

const isDev = !app.isPackaged;

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 800,
    height: 600,
    frame: false,
    resizable: true,
    titleBarStyle: 'hidden',
    webPreferences: {
      preload: path.join(__dirname, 'preload', 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    show: false,
  });

  if (isDev) {
    mainWindow.loadURL('http://localhost:5173');
  } else {
    mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));
  }

  mainWindow.once('ready-to-show', () => {
    mainWindow?.show();
  });

  mainWindow.on('close', (event) => {
    if (!isQuitting) {
      event.preventDefault();
      mainWindow?.hide();
    }
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

function registerIpcHandlers(): void {
  ipcMain.handle('audio:process', async (_event, audioBuffer: ArrayBuffer) => {
    const settings = settingsStore.get();
    if (!settings.apiKey) {
      throw new Error('API key not configured. Please set your OpenAI API key in Settings.');
    }

    const buffer = Buffer.from(audioBuffer);

    const transcription = await whisperService.transcribe(buffer, {
      apiKey: settings.apiKey,
      model: settings.whisperModel,
      language: settings.language,
    });

    let formattedText = transcription.text;
    try {
      formattedText = await gptService.formatText(transcription.text, {
        apiKey: settings.apiKey,
        model: settings.gptModel,
        personalDictionary: settings.personalDictionary,
        formatPrompt: settings.formatPrompt,
      });
    } catch (err) {
      console.error('GPT formatting failed, using raw text:', err);
    }

    const result = {
      id: crypto.randomUUID(),
      rawText: transcription.text,
      formattedText,
      timestamp: Date.now(),
      duration: transcription.duration,
      language: transcription.language,
      model: settings.whisperModel,
    };

    settingsStore.addHistoryItem(result);

    if (settings.autoCopy) {
      copyToClipboard(formattedText);
    }

    if (settings.autoPaste) {
      try {
        await pasteToActiveApp(formattedText);
      } catch (err) {
        console.error('Auto-paste failed:', err);
      }
    }

    return result;
  });

  ipcMain.handle('settings:get', () => {
    return settingsStore.get();
  });

  ipcMain.handle('settings:save', (_event, partial: Record<string, unknown>) => {
    const oldSettings = settingsStore.get();
    settingsStore.save(partial);
    const newSettings = settingsStore.get();

    if (oldSettings.hotkey !== newSettings.hotkey) {
      registerGlobalShortcut(newSettings.hotkey);
    }

    mainWindow?.webContents.send('settings:changed', newSettings);
  });

  ipcMain.handle('history:get', () => {
    return settingsStore.getHistory();
  });

  ipcMain.handle('history:delete', (_event, id: string) => {
    settingsStore.deleteHistoryItem(id);
  });

  ipcMain.handle('history:clear', () => {
    settingsStore.clearHistory();
  });

  ipcMain.handle('clipboard:copy', (_event, text: string) => {
    copyToClipboard(text);
  });

  ipcMain.handle('clipboard:paste', async (_event, text: string) => {
    await pasteToActiveApp(text);
  });

  ipcMain.handle('models:get', () => {
    return ['gpt-4', 'gpt-4-turbo', 'gpt-4o', 'gpt-4o-mini', 'gpt-3.5-turbo'];
  });

  ipcMain.on('window:minimize-to-tray', () => {
    mainWindow?.hide();
  });

  ipcMain.on('app:quit', () => {
    isQuitting = true;
    app.quit();
  });
}

function registerGlobalShortcut(hotkey: string): void {
  globalShortcut.unregisterAll();

  try {
    const registered = globalShortcut.register(hotkey, () => {
      mainWindow?.webContents.send('recording:toggle');
      trayManager?.setRecording(true);
    });

    if (!registered) {
      console.error('Failed to register global shortcut:', hotkey);
    }
  } catch (err) {
    console.error('Error registering global shortcut:', err);
  }
}

const gotLock = app.requestSingleInstanceLock();

if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.show();
      mainWindow.focus();
    }
  });

  app.on('ready', () => {
    createWindow();
    registerIpcHandlers();

    if (mainWindow) {
      trayManager = new TrayManager(mainWindow);
      trayManager.create();
    }

    const settings = settingsStore.get();
    registerGlobalShortcut(settings.hotkey);
  });

  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') {
      app.quit();
    }
  });

  app.on('activate', () => {
    if (mainWindow === null) {
      createWindow();
    } else {
      mainWindow.show();
    }
  });

  app.on('before-quit', () => {
    isQuitting = true;
  });

  app.on('will-quit', () => {
    globalShortcut.unregisterAll();
    trayManager?.destroy();
  });
}
