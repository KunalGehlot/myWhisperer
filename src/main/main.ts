/**
 * Main process entry point for myWhisperer.
 * Manages the application lifecycle, IPC handlers, global shortcuts, and tray integration.
 */
import {
  app,
  BrowserWindow,
  ipcMain,
  globalShortcut,
  session,
  systemPreferences,
} from 'electron';
import * as path from 'path';
import * as crypto from 'crypto';
import { SettingsStore, AppSettings } from './settings-store';
import { WhisperService } from './whisper-service';
import { GPTService } from './gpt-service';
import { copyToClipboard, pasteToActiveApp } from './clipboard-manager';
import { TrayManager } from './tray-manager';

let mainWindow: BrowserWindow | null = null;
let trayManager: TrayManager | null = null;
let isQuitting = false;
let isRecording = false;
let currentRegisteredShortcut: string | null = null;

const settingsStore = new SettingsStore();
const whisperService = new WhisperService();
const gptService = new GPTService();

const isDev = !app.isPackaged;

/** Allowed settings keys that can be saved via the settings:save IPC handler. */
const ALLOWED_SETTINGS_KEYS: ReadonlySet<keyof AppSettings> = new Set([
  'apiKey',
  'whisperModel',
  'gptModel',
  'language',
  'hotkey',
  'theme',
  'autoPaste',
  'autoCopy',
  'recordingMode',
  'audioInputDevice',
  'personalDictionary',
  'formatPrompt',
]);

/** Creates the main application window with security-hardened web preferences. */
function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 800,
    height: 600,
    frame: false,
    resizable: true,
    titleBarStyle: 'hidden',
    webPreferences: {
      preload: path.join(__dirname, '..', 'preload', 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    show: false,
  });

  if (isDev) {
    mainWindow.loadURL('http://localhost:5173');
  } else {
    mainWindow.loadFile(path.join(app.getAppPath(), 'dist', 'renderer', 'index.html'));
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

/** Registers all IPC handlers for renderer-to-main communication. */
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
    const sanitized: Record<string, unknown> = {};
    for (const key of Object.keys(partial)) {
      if (ALLOWED_SETTINGS_KEYS.has(key as keyof AppSettings)) {
        sanitized[key] = partial[key];
      }
    }

    const oldSettings = settingsStore.get();
    settingsStore.save(sanitized);
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

  ipcMain.handle('app:platform', () => {
    return process.platform;
  });

  ipcMain.on('window:minimize-to-tray', () => {
    mainWindow?.hide();
  });

  ipcMain.on('app:quit', () => {
    isQuitting = true;
    app.quit();
  });
}

/**
 * Registers a global keyboard shortcut for toggling recording.
 * Unregisters only the previously registered shortcut rather than all shortcuts.
 */
function registerGlobalShortcut(hotkey: string): void {
  if (currentRegisteredShortcut) {
    globalShortcut.unregister(currentRegisteredShortcut);
    currentRegisteredShortcut = null;
  }

  try {
    const registered = globalShortcut.register(hotkey, () => {
      isRecording = !isRecording;
      trayManager?.setRecording(isRecording);
      mainWindow?.webContents.send('recording:toggle');
    });

    if (registered) {
      currentRegisteredShortcut = hotkey;
    } else {
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

  app.whenReady().then(async () => {
    if (process.platform === 'darwin') {
      await systemPreferences.askForMediaAccess('microphone');
    }

    if (!isDev) {
      session.defaultSession.webRequest.onHeadersReceived((details, callback) => {
        callback({
          responseHeaders: {
            ...details.responseHeaders,
            'Content-Security-Policy': ["default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline';"],
          },
        });
      });
    }

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
