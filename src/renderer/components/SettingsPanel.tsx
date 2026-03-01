import React, { useState, useEffect } from 'react';
import type { AppSettings, AudioDevice } from '../types';

interface SettingsPanelProps {
  settings: AppSettings;
  onSave: (patch: Partial<AppSettings>) => Promise<void>;
}

const EyeIcon: React.FC = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
    <circle cx="12" cy="12" r="3" />
  </svg>
);

const EyeOffIcon: React.FC = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94" />
    <path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19" />
    <line x1="1" y1="1" x2="23" y2="23" />
  </svg>
);

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
  const [saved, setSaved] = useState(false);
  const [customModel, setCustomModel] = useState('');
  const [useCustomModel, setUseCustomModel] = useState(false);

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
    setSaved(false);
  };

  const handleSave = async () => {
    setSaving(true);
    const toSave = { ...local };
    if (useCustomModel && customModel.trim()) {
      toSave.gptModel = customModel.trim();
    }
    await onSave(toSave);
    setSaving(false);
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
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
                  onChange={(e) => {
                    setCustomModel(e.target.value);
                    setSaved(false);
                  }}
                  placeholder="e.g. gpt-4o-2024-05-13"
                  className={inputClass}
                />
                <button
                  onClick={() => {
                    setUseCustomModel(false);
                    setCustomModel('');
                    if (!GPT_MODELS.includes(local.gptModel)) {
                      update({ gptModel: 'gpt-4o-mini' });
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
              {(['toggle', 'push-to-talk'] as const).map((mode) => (
                <button
                  key={mode}
                  onClick={() => update({ recordingMode: mode })}
                  className={`flex-1 px-3 py-2 text-sm rounded-lg border transition-colors ${
                    local.recordingMode === mode
                      ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300 font-medium'
                      : 'border-surface-300 dark:border-surface-600 text-surface-600 dark:text-surface-400 hover:bg-surface-50 dark:hover:bg-surface-700'
                  }`}
                  type="button"
                >
                  {mode === 'toggle' ? 'Toggle' : 'Push to Talk'}
                </button>
              ))}
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
            <p className="text-xs text-surface-400 mt-1">Configured in system preferences</p>
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
                    >
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                        <line x1="18" y1="6" x2="6" y2="18" />
                        <line x1="6" y1="6" x2="18" y2="18" />
                      </svg>
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
                {t === 'light' && (
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <circle cx="12" cy="12" r="5" />
                    <path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42" />
                  </svg>
                )}
                {t === 'dark' && (
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
                  </svg>
                )}
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
          className={`w-full py-2.5 rounded-xl text-sm font-medium transition-all ${
            saved
              ? 'bg-green-500 text-white'
              : 'bg-primary-600 hover:bg-primary-700 text-white shadow-sm hover:shadow'
          } disabled:opacity-50`}
        >
          {saving ? 'Saving...' : saved ? 'Saved!' : 'Save Settings'}
        </button>
      </div>
    </div>
  );
};
