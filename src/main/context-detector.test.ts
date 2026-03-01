// @vitest-environment node
import { describe, it, expect, vi, beforeEach } from 'vitest';
import * as child_process from 'child_process';
import { getActiveContext } from './context-detector';

vi.mock('child_process');

const mockExecSync = vi.mocked(child_process.execSync);

describe('context-detector', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubGlobal('process', { ...process, platform: 'darwin' });
  });

  it('returns app name and window title on macOS', () => {
    mockExecSync
      .mockReturnValueOnce('Google Chrome\n' as any)
      .mockReturnValueOnce('GitHub - myWhisperer\n' as any);

    const result = getActiveContext();

    expect(result).toEqual({
      appName: 'Google Chrome',
      windowTitle: 'GitHub - myWhisperer',
    });
    expect(mockExecSync).toHaveBeenCalledTimes(2);
  });

  it('returns empty strings on error', () => {
    mockExecSync.mockImplementation(() => {
      throw new Error('Command failed');
    });

    const result = getActiveContext();

    expect(result).toEqual({ appName: '', windowTitle: '' });
  });

  it('handles missing window title gracefully', () => {
    mockExecSync
      .mockReturnValueOnce('Spotlight\n' as any)
      .mockImplementationOnce(() => {
        throw new Error('No window');
      });

    const result = getActiveContext();

    expect(result).toEqual({
      appName: 'Spotlight',
      windowTitle: '',
    });
  });

  it('returns empty strings for unsupported platforms', () => {
    vi.stubGlobal('process', { ...process, platform: 'freebsd' });

    const result = getActiveContext();

    expect(result).toEqual({ appName: '', windowTitle: '' });
    expect(mockExecSync).not.toHaveBeenCalled();
  });
});
