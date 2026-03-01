/**
 * Clipboard utilities for myWhisperer.
 * Provides cross-platform copy and paste operations using secure child process execution.
 */
import { clipboard } from 'electron';
import { execFile } from 'child_process';

/** Writes the given text to the system clipboard. */
function copyToClipboard(text: string): void {
  clipboard.writeText(text);
}

/**
 * Pastes text into the currently active application by writing to the clipboard
 * and simulating a platform-specific paste keystroke.
 */
function pasteToActiveApp(text: string): Promise<void> {
  return new Promise((resolve, reject) => {
    clipboard.writeText(text);

    if (process.platform === 'darwin') {
      execFile(
        'osascript',
        ['-e', 'tell application "System Events" to keystroke "v" using command down'],
        (error) => {
          if (error) {
            reject(error);
          } else {
            resolve();
          }
        }
      );
    } else if (process.platform === 'win32') {
      execFile(
        'powershell',
        ['-command', "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^v')"],
        (error) => {
          if (error) {
            reject(error);
          } else {
            resolve();
          }
        }
      );
    } else {
      execFile('xdotool', ['key', 'ctrl+v'], (error) => {
        if (error) {
          reject(error);
        } else {
          resolve();
        }
      });
    }
  });
}

export { copyToClipboard, pasteToActiveApp };
