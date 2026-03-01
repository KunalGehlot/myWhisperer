/**
 * Main process entry point for myWhisperer.
 * Manages the application lifecycle, IPC handlers, global shortcuts, and tray integration.
 */
import {
  app,
  BrowserWindow,
  ipcMain,
  session,
  systemPreferences,
} from 'electron';
import * as path from 'path';
import * as crypto from 'crypto';
import { SettingsStore, AppSettings } from './settings-store';
import { WhisperService } from './whisper-service';
import { GPTService } from './gpt-service';
import { copyToClipboard, pasteToActiveApp } from './clipboard-manager';
import { getActiveContext } from './context-detector';
import { ShortcutManager } from './shortcut-manager';
import { TrayManager } from './tray-manager';

let mainWindow: BrowserWindow | null = null;
let trayManager: TrayManager | null = null;
let isQuitting = false;
let isRecording = false;
let shortcutManager: ShortcutManager | null = null;

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
  'gptFormattingLevel',
]);

/** Creates the main application window with security-hardened web preferences. */
function createWindow(): void {
  const isMac = process.platform === 'darwin';
  mainWindow = new BrowserWindow({
    width: 800,
    height: 600,
    resizable: true,
    ...(isMac
      ? { titleBarStyle: 'hiddenInset' as const, trafficLightPosition: { x: 16, y: 13 } }
      : {}),
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

    // Detect active window context for context-aware formatting
    const appContext = getActiveContext();

    const formattingLevel = settings.gptFormattingLevel ?? 70;
    let formattedText = transcription.text;
    try {
      formattedText = await gptService.formatText(transcription.text, {
        apiKey: settings.apiKey,
        model: settings.gptModel,
        personalDictionary: settings.personalDictionary,
        formatPrompt: settings.formatPrompt,
        formattingLevel,
        appContext,
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

    // Validate gptFormattingLevel range
    if (typeof sanitized.gptFormattingLevel === 'number') {
      sanitized.gptFormattingLevel = Math.max(0, Math.min(100, Math.round(sanitized.gptFormattingLevel)));
    }

    const oldSettings = settingsStore.get();
    settingsStore.save(sanitized);
    const newSettings = settingsStore.get();

    if (
      oldSettings.hotkey !== newSettings.hotkey ||
      oldSettings.recordingMode !== newSettings.recordingMode
    ) {
      registerShortcut(newSettings);
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
    return [
      'gpt-4.1',
      'gpt-4.1-mini',
      'gpt-4.1-nano',
      'gpt-4o',
      'gpt-4o-mini',
      'o4-mini',
      'o3',
      'o3-mini',
      'o1',
      'o1-mini',
      'gpt-4-turbo',
      'gpt-4',
    ];
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
 * Registers the global shortcut using the ShortcutManager.
 * Supports both toggle mode (press to start/stop) and push-to-talk (hold to record).
 */
function registerShortcut(settings: AppSettings): void {
  if (!shortcutManager) {
    shortcutManager = new ShortcutManager({
      onRecordingToggle: () => {
        isRecording = !isRecording;
        trayManager?.setRecording(isRecording);
        mainWindow?.webContents.send('recording:toggle');
      },
      onRecordingStart: () => {
        if (isRecording) return; // Already recording
        isRecording = true;
        trayManager?.setRecording(true);
        mainWindow?.webContents.send('recording:start');
      },
      onRecordingStop: () => {
        if (!isRecording) return; // Not recording
        isRecording = false;
        trayManager?.setRecording(false);
        mainWindow?.webContents.send('recording:stop');
      },
    });
  }

  shortcutManager.register(settings.hotkey, settings.recordingMode);
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
    registerShortcut(settings);
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
    shortcutManager?.destroy();
    trayManager?.destroy();
  });
}
