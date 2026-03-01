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
  { value: 'gpt-4.1', label: 'GPT-4.1', desc: 'Latest, most capable' },
  { value: 'gpt-4.1-mini', label: 'GPT-4.1 Mini', desc: 'Fast and affordable' },
  { value: 'gpt-4.1-nano', label: 'GPT-4.1 Nano', desc: 'Fastest, lowest cost' },
  { value: 'gpt-4o', label: 'GPT-4o', desc: 'Multimodal' },
  { value: 'gpt-4o-mini', label: 'GPT-4o Mini', desc: 'Compact multimodal' },
  { value: 'o4-mini', label: 'o4 Mini', desc: 'Reasoning, compact' },
  { value: 'o3', label: 'o3', desc: 'Reasoning' },
  { value: 'o3-mini', label: 'o3 Mini', desc: 'Reasoning, fast' },
  { value: 'o1', label: 'o1', desc: 'Reasoning (prev gen)' },
  { value: 'o1-mini', label: 'o1 Mini', desc: 'Reasoning, compact (prev gen)' },
  { value: 'gpt-4-turbo', label: 'GPT-4 Turbo', desc: 'Legacy turbo' },
  { value: 'gpt-4', label: 'GPT-4', desc: 'Legacy' },
];

const GPT_MODEL_VALUES = GPT_MODELS.map((m) => m.value);

const BUILTIN_PROMPTS: Record<string, string> = {
  light: `You are a minimal text editor. Take the raw speech transcription and make only essential corrections:
- Fix capitalization at the beginning of sentences
- Remove filler words (um, uh, like, you know, so basically, etc.)
- Fix obvious typos and misspellings
- Add basic punctuation (periods at sentence ends, commas for natural pauses)
Do NOT restructure sentences, change word choices, or rewrite anything. Preserve the speaker's exact phrasing and sentence structure.
If custom terminology is provided, use those exact spellings.
Output ONLY the corrected text with no explanations.`,
  moderate: `You are a text editor. Take the raw speech transcription and clean it up:
- Fix grammar, punctuation, and capitalization
- Remove filler words (um, uh, like, you know, so basically, etc.)
- Fix spelling errors and typos
- Lightly improve sentence flow where needed, but keep the speaker's original sentence structure and word choices where possible
- Do not heavily rewrite, restructure paragraphs, or change the tone
If custom terminology is provided, use those exact spellings.
Output ONLY the formatted text with no explanations.`,
  full: `You are an intelligent voice-to-text assistant integrated into a desktop application.
You receive two inputs: (1) raw speech transcription and (2) context about where the user is currently typing (application name and window title).

Your job is to format the transcription appropriately based on the context:

Context-Aware Formatting Rules:

- Email clients (Mail, Outlook, Gmail, Thunderbird, Spark, Airmail, etc.):
  Format as a professional email. Add appropriate greeting and sign-off if missing. Use proper email paragraph structure. Keep tone professional but warm.

- Chat/messaging apps (Slack, Discord, Teams, WhatsApp, Telegram, iMessage, Signal, etc.):
  Keep it casual and conversational. Short sentences. No formal structure needed. Preserve the speaker's natural tone. Light punctuation only.

- Note-taking apps (Notion, Obsidian, Apple Notes, OneNote, Bear, Evernote, Craft, Joplin, etc.):
  Format as clean, organized notes. Use bullet points for lists. Add markdown headers if the content covers multiple distinct topics. Be concise and scannable.

- Document editors (Word, Google Docs, Pages, LibreOffice Writer, TextEdit, Scrivener, etc.):
  Format as polished prose. Full sentences, proper paragraphs. Professional writing style with clear structure and logical flow.

- Code editors/IDEs (VS Code, IntelliJ, Xcode, Vim, Neovim, Sublime Text, Cursor, Zed, etc.):
  Format as code comments (// or # depending on file type). If the speech describes code logic, attempt to write the actual code. Keep it precise and technical.

- Spreadsheet apps (Excel, Google Sheets, Numbers, LibreOffice Calc):
  Format as comma-separated or tab-separated values if the content sounds like data entries. Otherwise, format as concise cell-appropriate text.

- Presentation apps (PowerPoint, Keynote, Google Slides, LibreOffice Impress):
  Format as concise bullet points suitable for slides. Short phrases, not full sentences. Focus on key points.

- Terminal/CLI (Terminal, iTerm, Command Prompt, PowerShell, Warp, Alacritty, Kitty, etc.):
  If the speech describes a command, output the actual shell command. Otherwise, format as a brief technical comment prefixed with #.

- Social media (Twitter/X, LinkedIn, Facebook, Reddit, Instagram, Threads, Mastodon, etc.):
  Match the platform's tone and conventions. Keep within character limits. Casual but clear. Use hashtags if appropriate.

- Search bars / Browsers (Chrome, Safari, Firefox, Arc, Edge, Brave, Opera, etc.):
  Format as a search query — concise keywords, no full sentences, no punctuation.

- Task/project management (Jira, Linear, Asana, Trello, Monday, Todoist, Things, etc.):
  Format as a clear, actionable task description or comment. Concise language with relevant context.

- Unknown/Other applications:
  Default to clean, professional prose. Fix grammar, punctuation, capitalization. Remove filler words. Maintain original meaning.

General Rules (always apply):
- Remove filler words (um, uh, like, you know, so basically, I mean, sort of, kind of, etc.)
- Fix grammar, spelling, and punctuation
- If custom terminology/dictionary is provided, use those exact spellings
- Preserve the speaker's original meaning, intent, and key information
- Output ONLY the formatted text — no explanations, labels, preambles, or metadata`,
};

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
  const [isCapturingHotkey, setIsCapturingHotkey] = useState(false);
  const [showDefaultPrompt, setShowDefaultPrompt] = useState(false);
  const { showToast } = useToast();

  useEffect(() => {
    setLocal(settings);
    if (!GPT_MODEL_VALUES.includes(settings.gptModel)) {
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

  // Use window-level keydown listener for reliable hotkey capture (especially on macOS)
  useEffect(() => {
    if (!isCapturingHotkey) return;

    const handler = (e: KeyboardEvent) => {
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();

      if (e.key === 'Escape') {
        setIsCapturingHotkey(false);
        return;
      }

      // Ignore modifier-only presses
      if (['Meta', 'Control', 'Alt', 'Shift', 'OS'].includes(e.key)) return;

      const parts: string[] = [];
      if (e.ctrlKey) parts.push('Control');
      if (e.metaKey) parts.push('Command');
      if (e.altKey) parts.push('Alt');
      if (e.shiftKey) parts.push('Shift');

      // Map key names to Electron accelerator format
      let key = e.key;
      if (key === ' ') key = 'Space';
      else if (key.length === 1) key = key.toUpperCase();
      else if (key === 'ArrowUp') key = 'Up';
      else if (key === 'ArrowDown') key = 'Down';
      else if (key === 'ArrowLeft') key = 'Left';
      else if (key === 'ArrowRight') key = 'Right';
      else if (key === 'Enter') key = 'Return';
      else if (key === 'Backspace') key = 'Backspace';
      else if (key === 'Delete') key = 'Delete';
      else if (key === 'Tab') key = 'Tab';

      parts.push(key);

      const accelerator = parts.join('+');
      update({ hotkey: accelerator });
      setIsCapturingHotkey(false);
    };

    window.addEventListener('keydown', handler, true);
    return () => window.removeEventListener('keydown', handler, true);
  }, [isCapturingHotkey]);

  const formattingLabel =
    local.gptFormattingLevel === 0
      ? 'No formatting (raw transcription)'
      : local.gptFormattingLevel <= 30
        ? 'Light (capitalization, filler removal)'
        : local.gptFormattingLevel <= 70
          ? 'Moderate (grammar, punctuation)'
          : 'Full (context-aware rewrite based on active app)';

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
                    <option key={m.value} value={m.value}>
                      {m.label} — {m.desc}
                    </option>
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
                  placeholder="e.g. gpt-4.1-2025-04-14"
                  className={inputClass}
                />
                <button
                  onClick={() => {
                    setUseCustomModel(false);
                    setCustomModel('');
                    if (!GPT_MODEL_VALUES.includes(local.gptModel)) {
                      update({ gptModel: 'gpt-4.1' });
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
            <p className="text-xs text-surface-400 mt-1">
              {local.recordingMode === 'toggle'
                ? 'Press hotkey to start, press again to stop'
                : 'Hold hotkey to record, release to stop'}
            </p>
          </div>
          <div>
            <Label>Hotkey</Label>
            <div
              role="button"
              tabIndex={0}
              onClick={() => setIsCapturingHotkey(true)}
              onKeyDown={(e) => {
                if (!isCapturingHotkey && (e.key === 'Enter' || e.key === ' ')) {
                  e.preventDefault();
                  setIsCapturingHotkey(true);
                }
              }}
              className={`${inputClass} cursor-pointer select-none flex items-center justify-between ${
                isCapturingHotkey ? 'ring-2 ring-primary-500 border-primary-500' : ''
              }`}
            >
              {isCapturingHotkey ? (
                <span className="text-primary-500 dark:text-primary-400 animate-pulse">Press your shortcut...</span>
              ) : (
                <span>{local.hotkey}</span>
              )}
              {!isCapturingHotkey && (
                <span className="text-xs text-surface-400">Click to change</span>
              )}
            </div>
            <p className="text-xs text-surface-400 mt-1">
              Click the field above, then press your desired key combination. Press Escape to cancel.
            </p>
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
            <Label>GPT Formatting Level</Label>
            <div className="flex items-center gap-3">
              <span className="text-xs text-surface-400 w-8">Raw</span>
              <input
                type="range"
                min={0}
                max={100}
                step={1}
                value={local.gptFormattingLevel}
                onChange={(e) => update({ gptFormattingLevel: parseInt(e.target.value, 10) })}
                className="flex-1 h-2 rounded-lg appearance-none cursor-pointer accent-primary-600 bg-surface-200 dark:bg-surface-700"
              />
              <span className="text-xs text-surface-400 w-12 text-right">Full</span>
            </div>
            <p className="text-xs text-surface-400 mt-1">
              {local.gptFormattingLevel}% &mdash; {formattingLabel}
            </p>
          </div>
          <div>
            <Label>Custom Format Prompt</Label>
            <textarea
              value={local.formatPrompt}
              onChange={(e) => update({ formatPrompt: e.target.value })}
              placeholder="Leave empty to use the level-based smart prompt above. Set a custom prompt to override it."
              rows={3}
              className={inputClass + ' resize-none'}
            />
            <p className="text-xs text-surface-400 mt-1">
              When set, this overrides the level-based formatting above.
            </p>
          </div>
          {local.gptFormattingLevel > 0 && !local.formatPrompt && (
            <div>
              <button
                onClick={() => setShowDefaultPrompt(!showDefaultPrompt)}
                className="text-xs text-primary-600 dark:text-primary-400 hover:underline flex items-center gap-1"
                type="button"
              >
                <svg
                  width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
                  className={`transition-transform ${showDefaultPrompt ? 'rotate-90' : ''}`}
                >
                  <path d="M9 18l6-6-6-6" />
                </svg>
                {showDefaultPrompt ? 'Hide' : 'View'} active built-in prompt
              </button>
              {showDefaultPrompt && (
                <div className="mt-2 p-3 rounded-lg bg-surface-50 dark:bg-surface-800 border border-surface-200 dark:border-surface-700 max-h-64 overflow-y-auto">
                  <pre className="text-xs text-surface-600 dark:text-surface-300 whitespace-pre-wrap font-mono leading-relaxed">
                    {local.gptFormattingLevel <= 30
                      ? BUILTIN_PROMPTS.light
                      : local.gptFormattingLevel <= 70
                        ? BUILTIN_PROMPTS.moderate
                        : BUILTIN_PROMPTS.full}
                  </pre>
                </div>
              )}
            </div>
          )}
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
      <div className="sticky bottom-0 pt-3 pb-2 bg-gradient-to-t from-white via-white dark:from-surface-900 dark:via-surface-900">
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
