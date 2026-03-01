/** Settings panel for configuring API keys, models, recording, formatting, and appearance. */
import React, { useState, useEffect } from 'react';
import type { AppSettings, AudioDevice } from '../types';
import { EyeIcon, EyeOffIcon, XIcon, SunIcon, MoonIcon } from './Icons';
import { useToast } from './Toast';

interface SettingsPanelProps {
  settings: AppSettings;
  onSave: (patch: Partial<AppSettings>) => Promise<void>;
}

const LANGUAGES = [
  { value: 'auto', label: 'Auto-detect' },
  { value: 'en', label: 'English' },
  { value: 'es', label: 'Spanish' },
  { value: 'fr', label: 'French' },
  { value: 'de', label: 'German' },
  { value: 'it', label: 'Italian' },
  { value: 'pt', label: 'Portuguese' },
  { value: 'nl', label: 'Dutch' },
  { value: 'ru', label: 'Russian' },
  { value: 'zh', label: 'Chinese' },
  { value: 'ja', label: 'Japanese' },
  { value: 'ko', label: 'Korean' },
  { value: 'ar', label: 'Arabic' },
  { value: 'hi', label: 'Hindi' },
  { value: 'pl', label: 'Polish' },
  { value: 'tr', label: 'Turkish' },
  { value: 'sv', label: 'Swedish' },
  { value: 'da', label: 'Danish' },
  { value: 'fi', label: 'Finnish' },
  { value: 'uk', label: 'Ukrainian' },
];

const GPT_MODELS = [
  'gpt-4',
  'gpt-4-turbo',
  'gpt-4o',
  'gpt-4o-mini',
  'gpt-3.5-turbo',
];

const inputClass =
  'w-full px-3 py-2 rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 text-sm focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent transition-colors';

const selectClass =
  'w-full px-3 py-2 rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 text-sm focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent transition-colors appearance-none';

const SectionTitle: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <h3 className="text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 mb-3">
    {children}
  </h3>
);

const Label: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
    {children}
  </label>
);

export const SettingsPanel: React.FC<SettingsPanelProps> = ({ settings, onSave }) => {
  const [local, setLocal] = useState<AppSettings>(settings);
  const [showKey, setShowKey] = useState(false);
  const [devices, setDevices] = useState<AudioDevice[]>([]);
  const [dictWord, setDictWord] = useState('');
  const [saving, setSaving] = useState(false);
  const [customModel, setCustomModel] = useState('');
  const [useCustomModel, setUseCustomModel] = useState(false);
  const { showToast } = useToast();

  useEffect(() => {
    setLocal(settings);
    if (!GPT_MODELS.includes(settings.gptModel)) {
      setUseCustomModel(true);
      setCustomModel(settings.gptModel);
    }
  }, [settings]);

  useEffect(() => {
    navigator.mediaDevices.enumerateDevices().then((all) => {
      const audioInputs: AudioDevice[] = all
        .filter((d) => d.kind === 'audioinput')
        .map((d, i) => ({
          deviceId: d.deviceId,
          label: d.label || `Microphone ${i + 1}`,
          isDefault: d.deviceId === 'default',
        }));
      setDevices(audioInputs);
    });
  }, []);

  const update = (patch: Partial<AppSettings>) => {
    setLocal((prev) => ({ ...prev, ...patch }));
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      const toSave = { ...local };
      if (useCustomModel && customModel.trim()) {
        toSave.gptModel = customModel.trim();
      }
      await onSave(toSave);
      showToast('Settings saved', 'success');
    } catch {
      showToast('Failed to save settings', 'error');
    } finally {
      setSaving(false);
    }
  };

  const addDictWord = () => {
    const word = dictWord.trim();
    if (word && !local.personalDictionary.includes(word)) {
      update({ personalDictionary: [...local.personalDictionary, word] });
      setDictWord('');
    }
  };

  const removeDictWord = (word: string) => {
    update({ personalDictionary: local.personalDictionary.filter((w) => w !== word) });
  };

  return (
    <div className="h-full overflow-y-auto px-4 py-4 space-y-6">
      {/* API Configuration */}
      <section>
        <SectionTitle>API Configuration</SectionTitle>
        <div className="space-y-3">
          <div>
            <Label>OpenAI API Key</Label>
            <div className="relative">
              <input
                type={showKey ? 'text' : 'password'}
                value={local.apiKey}
                onChange={(e) => update({ apiKey: e.target.value })}
                placeholder="sk-..."
                className={inputClass + ' pr-10'}
              />
              <button
                onClick={() => setShowKey(!showKey)}
                className="absolute right-2 top-1/2 -translate-y-1/2 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300 transition-colors"
                type="button"
                aria-label={showKey ? 'Hide API key' : 'Show API key'}
              >
                {showKey ? <EyeOffIcon /> : <EyeIcon />}
              </button>
            </div>
          </div>
        </div>
      </section>

      {/* Models */}
      <section>
        <SectionTitle>Models</SectionTitle>
        <div className="space-y-3">
          <div>
            <Label>Whisper Model</Label>
            <input
              type="text"
              value={local.whisperModel}
              readOnly
              className={inputClass + ' bg-surface-50 dark:bg-surface-700 cursor-not-allowed'}
            />
            <p className="text-xs text-surface-400 mt-1">Currently the only model available via the OpenAI API</p>
          </div>
          <div>
            <Label>GPT Model</Label>
            {!useCustomModel ? (
              <div className="space-y-2">
                <select
                  value={local.gptModel}
                  onChange={(e) => update({ gptModel: e.target.value })}
                  className={selectClass}
                >
                  {GPT_MODELS.map((m) => (
                    <option key={m} value={m}>{m}</option>
                  ))}
                </select>
                <button
                  onClick={() => setUseCustomModel(true)}
                  className="text-xs text-primary-600 dark:text-primary-400 hover:underline"
                  type="button"
                >
                  Use custom model
                </button>
              </div>
            ) : (
              <div className="space-y-2">
                <input
                  type="text"
                  value={customModel}
                  onChange={(e) => setCustomModel(e.target.value)}
                  placeholder="e.g. gpt-4o-2024-05-13"
                  className={inputClass}
                />
                <button
                  onClick={() => {
                    setUseCustomModel(false);
                    setCustomModel('');
                    if (!GPT_MODELS.includes(local.gptModel)) {
                      update({ gptModel: 'gpt-4' });
                    }
                  }}
                  className="text-xs text-primary-600 dark:text-primary-400 hover:underline"
                  type="button"
                >
                  Use preset model
                </button>
              </div>
            )}
          </div>
        </div>
      </section>

      {/* Recording */}
      <section>
        <SectionTitle>Recording</SectionTitle>
        <div className="space-y-3">
          <div>
            <Label>Recording Mode</Label>
            <div className="flex gap-2">
              <button
                className="flex-1 px-3 py-2 text-sm rounded-lg border transition-colors border-primary-500 bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300 font-medium"
                type="button"
              >
                Toggle
              </button>
              <button
                disabled
                className="flex-1 px-3 py-2 text-sm rounded-lg border transition-colors border-surface-300 dark:border-surface-600 text-surface-400 dark:text-surface-500 cursor-not-allowed opacity-60"
                type="button"
                title="Push-to-talk requires key-up events which are not yet supported"
              >
                Push to Talk (Coming soon)
              </button>
            </div>
          </div>
          <div>
            <Label>Hotkey</Label>
            <input
              type="text"
              value={local.hotkey}
              readOnly
              className={inputClass + ' bg-surface-50 dark:bg-surface-700 cursor-not-allowed'}
            />
            <p className="text-xs text-surface-400 mt-1">Default: Cmd+Shift+Space. To change, edit the configuration file.</p>
          </div>
          <div>
            <Label>Audio Input Device</Label>
            <select
              value={local.audioInputDevice}
              onChange={(e) => update({ audioInputDevice: e.target.value })}
              className={selectClass}
            >
              <option value="default">System Default</option>
              {devices.map((d) => (
                <option key={d.deviceId} value={d.deviceId}>{d.label}</option>
              ))}
            </select>
          </div>
        </div>
      </section>

      {/* Language */}
      <section>
        <SectionTitle>Language</SectionTitle>
        <div>
          <Label>Transcription Language</Label>
          <select
            value={local.language}
            onChange={(e) => update({ language: e.target.value })}
            className={selectClass}
          >
            {LANGUAGES.map((l) => (
              <option key={l.value} value={l.value}>{l.label}</option>
            ))}
          </select>
        </div>
      </section>

      {/* Formatting */}
      <section>
        <SectionTitle>Formatting</SectionTitle>
        <div className="space-y-3">
          <div>
            <Label>Custom Format Prompt</Label>
            <textarea
              value={local.formatPrompt}
              onChange={(e) => update({ formatPrompt: e.target.value })}
              placeholder="e.g. Format as bullet points, fix grammar, use professional tone..."
              rows={3}
              className={inputClass + ' resize-none'}
            />
          </div>
          <div>
            <Label>Personal Dictionary</Label>
            <div className="flex gap-2 mb-2">
              <input
                type="text"
                value={dictWord}
                onChange={(e) => setDictWord(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && addDictWord()}
                placeholder="Add a word..."
                className={inputClass}
              />
              <button
                onClick={addDictWord}
                className="px-3 py-2 rounded-lg bg-primary-600 text-white text-sm font-medium hover:bg-primary-700 transition-colors shrink-0"
                type="button"
              >
                Add
              </button>
            </div>
            {local.personalDictionary.length > 0 && (
              <div className="flex flex-wrap gap-1.5">
                {local.personalDictionary.map((word) => (
                  <span
                    key={word}
                    className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs
                      bg-surface-100 dark:bg-surface-700 text-surface-700 dark:text-surface-300"
                  >
                    {word}
                    <button
                      onClick={() => removeDictWord(word)}
                      className="hover:text-red-500 transition-colors"
                      type="button"
                      aria-label={`Remove word: ${word}`}
                    >
                      <XIcon className="w-3 h-3" />
                    </button>
                  </span>
                ))}
              </div>
            )}
          </div>
        </div>
      </section>

      {/* Appearance */}
      <section>
        <SectionTitle>Appearance</SectionTitle>
        <div>
          <Label>Theme</Label>
          <div className="flex gap-2">
            {(['light', 'dark', 'system'] as const).map((t) => (
              <button
                key={t}
                onClick={() => update({ theme: t })}
                className={`flex-1 px-3 py-2 text-sm rounded-lg border transition-colors flex items-center justify-center gap-2 ${
                  local.theme === t
                    ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300 font-medium'
                    : 'border-surface-300 dark:border-surface-600 text-surface-600 dark:text-surface-400 hover:bg-surface-50 dark:hover:bg-surface-700'
                }`}
                type="button"
              >
                {t === 'light' && <SunIcon />}
                {t === 'dark' && <MoonIcon />}
                {t === 'system' && (
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <rect x="2" y="3" width="20" height="14" rx="2" />
                    <line x1="8" y1="21" x2="16" y2="21" />
                    <line x1="12" y1="17" x2="12" y2="21" />
                  </svg>
                )}
                {t.charAt(0).toUpperCase() + t.slice(1)}
              </button>
            ))}
          </div>
        </div>
      </section>

      {/* Behavior */}
      <section>
        <SectionTitle>Behavior</SectionTitle>
        <div className="space-y-3">
          <label className="flex items-center justify-between cursor-pointer">
            <span className="text-sm text-surface-700 dark:text-surface-300">Auto-copy to clipboard</span>
            <button
              onClick={() => update({ autoCopy: !local.autoCopy })}
              className={`relative w-10 h-6 rounded-full transition-colors ${
                local.autoCopy ? 'bg-primary-600' : 'bg-surface-300 dark:bg-surface-600'
              }`}
              type="button"
              role="switch"
              aria-checked={local.autoCopy}
              aria-label="Toggle auto-copy to clipboard"
            >
              <span
                className={`absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white shadow transition-transform ${
                  local.autoCopy ? 'translate-x-4' : ''
                }`}
              />
            </button>
          </label>
          <label className="flex items-center justify-between cursor-pointer">
            <span className="text-sm text-surface-700 dark:text-surface-300">Auto-paste to active app</span>
            <button
              onClick={() => update({ autoPaste: !local.autoPaste })}
              className={`relative w-10 h-6 rounded-full transition-colors ${
                local.autoPaste ? 'bg-primary-600' : 'bg-surface-300 dark:bg-surface-600'
              }`}
              type="button"
              role="switch"
              aria-checked={local.autoPaste}
              aria-label="Toggle auto-paste to active app"
            >
              <span
                className={`absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white shadow transition-transform ${
                  local.autoPaste ? 'translate-x-4' : ''
                }`}
              />
            </button>
          </label>
        </div>
      </section>

      {/* Save button */}
      <div className="sticky bottom-0 pt-3 pb-2 bg-white dark:bg-surface-900">
        <button
          onClick={handleSave}
          disabled={saving}
          className="w-full py-2.5 rounded-xl text-sm font-medium transition-all bg-primary-600 hover:bg-primary-700 text-white shadow-sm hover:shadow disabled:opacity-50"
        >
          {saving ? 'Saving...' : 'Save Settings'}
        </button>
      </div>
    </div>
  );
};
