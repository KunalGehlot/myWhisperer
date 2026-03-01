/**
 * Active window context detector for myWhisperer.
 * Detects the frontmost application and window title to enable context-aware formatting.
 */
import { execSync } from 'child_process';

export interface AppContext {
  appName: string;
  windowTitle: string;
}

/**
 * Detects the currently active application and window title.
 * Uses platform-specific commands: osascript (macOS), PowerShell (Windows), xdotool (Linux).
 */
export function getActiveContext(): AppContext {
  try {
    switch (process.platform) {
      case 'darwin':
        return getActiveContextMacOS();
      case 'win32':
        return getActiveContextWindows();
      case 'linux':
        return getActiveContextLinux();
      default:
        return { appName: '', windowTitle: '' };
    }
  } catch (err) {
    console.error('Failed to detect active window context:', err);
    return { appName: '', windowTitle: '' };
  }
}

function getActiveContextMacOS(): AppContext {
  const appName = execSync(
    `osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true'`,
    { encoding: 'utf-8', timeout: 3000 }
  ).trim();

  let windowTitle = '';
  try {
    windowTitle = execSync(
      `osascript -e 'tell application "System Events" to get title of front window of first application process whose frontmost is true'`,
      { encoding: 'utf-8', timeout: 3000 }
    ).trim();
  } catch {
    // Some apps (e.g. Spotlight) don't expose window titles
  }

  return { appName, windowTitle };
}

function getActiveContextWindows(): AppContext {
  const output = execSync(
    `powershell -Command "(Get-Process | Where-Object {$_.MainWindowHandle -eq (Add-Type -MemberDefinition '[DllImport(\\\"user32.dll\\\")] public static extern IntPtr GetForegroundWindow();' -Name WinAPI -PassThru)::GetForegroundWindow()}).MainWindowTitle"`,
    { encoding: 'utf-8', timeout: 3000 }
  ).trim();

  // On Windows, extract app name from window title (typically "Document - App Name")
  const parts = output.split(' - ');
  const windowTitle = output;
  const appName = parts.length > 1 ? parts[parts.length - 1] : output;

  return { appName, windowTitle };
}

function getActiveContextLinux(): AppContext {
  const windowTitle = execSync(
    'xdotool getactivewindow getwindowname',
    { encoding: 'utf-8', timeout: 3000 }
  ).trim();

  let appName = '';
  try {
    const windowId = execSync('xdotool getactivewindow', {
      encoding: 'utf-8',
      timeout: 3000,
    }).trim();
    const pid = execSync(`xdotool getwindowpid ${windowId}`, {
      encoding: 'utf-8',
      timeout: 3000,
    }).trim();
    appName = execSync(`cat /proc/${pid}/comm`, {
      encoding: 'utf-8',
      timeout: 3000,
    }).trim();
  } catch {
    // Fall back to parsing window title
    const parts = windowTitle.split(' - ');
    appName = parts.length > 1 ? parts[parts.length - 1] : windowTitle;
  }

  return { appName, windowTitle };
}
