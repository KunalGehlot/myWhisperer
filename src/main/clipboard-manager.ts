import { clipboard } from 'electron';
import { exec } from 'child_process';

function copyToClipboard(text: string): void {
  clipboard.writeText(text);
}

function pasteToActiveApp(text: string): Promise<void> {
  return new Promise((resolve, reject) => {
    clipboard.writeText(text);

    if (process.platform === 'darwin') {
      exec(
        `osascript -e 'tell application "System Events" to keystroke "v" using command down'`,
        (error) => {
          if (error) {
            reject(error);
          } else {
            resolve();
          }
        }
      );
    } else if (process.platform === 'win32') {
      exec(
        'powershell -command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait(\'^v\')"',
        (error) => {
          if (error) {
            reject(error);
          } else {
            resolve();
          }
        }
      );
    } else {
      exec('xdotool key ctrl+v', (error) => {
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
