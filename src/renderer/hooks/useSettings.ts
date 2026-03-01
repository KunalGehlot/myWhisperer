import { useState, useEffect, useCallback } from 'react';
import type { AppSettings } from '../types';

const defaultSettings: AppSettings = {
  apiKey: '',
  whisperModel: 'whisper-1',
  gptModel: 'gpt-4o-mini',
  language: 'auto',
  hotkey: 'CommandOrControl+Shift+Space',
  theme: 'system',
  autoPaste: false,
  autoCopy: true,
  recordingMode: 'toggle',
  audioInputDevice: 'default',
  personalDictionary: [],
  formatPrompt: '',
};

export function useSettings() {
  const [settings, setSettings] = useState<AppSettings>(defaultSettings);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    window.electronAPI.getSettings().then((s) => {
      setSettings(s);
      setLoaded(true);
    });

    const unsub = window.electronAPI.onSettingsChanged((s) => {
      setSettings(s);
    });

    return unsub;
  }, []);

  const updateSettings = useCallback(async (patch: Partial<AppSettings>) => {
    const next = { ...settings, ...patch };
    setSettings(next);
    await window.electronAPI.saveSettings(patch);
  }, [settings]);

  return { settings, updateSettings, loaded };
}
