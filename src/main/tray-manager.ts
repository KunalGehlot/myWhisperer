/**
 * Tray icon manager for myWhisperer.
 * Provides system tray integration with context menu for quick access to app functions.
 */
import { Tray, Menu, nativeImage, BrowserWindow, app } from 'electron';

const TRAY_ICON_DATA =
  'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAA' +
  'mElEQVQ4y2NgGAUkAkYo+z8DAwMDEwMDA8P/////MzIyMjD8//+fAZcBTFANIP5/' +
  'BgYGBhYGBgaG////MzAxMDAwEGsAM1QDWPF/BgYGRgYGBob///8zsTAwMDAQawAL' +
  'VDFYMQMjIyMDsQYwQxWDBf9nYGBgYmBgYPj//z8TCwMDA8OoAQMOWBgZGRn+MzAw' +
  'MAAAAP//AwBXCi4x2mfsbQAAAABJRU5ErkJggg==';

/** Manages the system tray icon, tooltip, and context menu for the application. */
class TrayManager {
  private tray: Tray | null = null;
  private mainWindow: BrowserWindow;
  private isRecording = false;

  constructor(mainWindow: BrowserWindow) {
    this.mainWindow = mainWindow;
  }

  /** Creates the tray icon and sets up click behavior. */
  create(): void {
    const icon = nativeImage.createFromDataURL(TRAY_ICON_DATA);
    this.tray = new Tray(icon.resize({ width: 16, height: 16 }));
    this.tray.setToolTip('myWhisperer');
    this.updateContextMenu();

    this.tray.on('click', () => {
      this.updateContextMenu();
      if (this.mainWindow.isVisible()) {
        this.mainWindow.hide();
      } else {
        this.mainWindow.show();
        this.mainWindow.focus();
      }
    });
  }

  /** Updates the recording state and refreshes the context menu to reflect it. */
  setRecording(recording: boolean): void {
    this.isRecording = recording;
    this.updateContextMenu();
  }

  /** Rebuilds the context menu with current window visibility and recording state. */
  private updateContextMenu(): void {
    if (!this.tray) return;

    const menu = Menu.buildFromTemplate([
      {
        label: this.mainWindow.isVisible() ? 'Hide Window' : 'Show Window',
        click: () => {
          if (this.mainWindow.isVisible()) {
            this.mainWindow.hide();
          } else {
            this.mainWindow.show();
            this.mainWindow.focus();
          }
        },
      },
      {
        label: this.isRecording ? 'Stop Recording' : 'Start Recording',
        click: () => {
          this.mainWindow.webContents.send('recording:toggle');
        },
      },
      {
        label: 'Settings',
        click: () => {
          this.mainWindow.show();
          this.mainWindow.focus();
        },
      },
      { type: 'separator' },
      {
        label: 'Quit',
        click: () => {
          app.quit();
        },
      },
    ]);

    this.tray.setContextMenu(menu);
  }

  /** Destroys the tray icon and frees associated resources. */
  destroy(): void {
    if (this.tray) {
      this.tray.destroy();
      this.tray = null;
    }
  }
}

export { TrayManager };
