import React, { useState, useEffect, useCallback } from 'react';
import type { TranscriptionResult, ProcessingState } from './types';
import { useSettings } from './hooks/useSettings';
import { useAudioRecorder } from './hooks/useAudioRecorder';
import { RecordButton } from './components/RecordButton';
import { TranscriptionPanel } from './components/TranscriptionPanel';
import { SettingsPanel } from './components/SettingsPanel';
import { HistoryPanel } from './components/HistoryPanel';
import { StatusBar } from './components/StatusBar';

type View = 'main' | 'settings' | 'history';

const MicTabIcon: React.FC<{ active: boolean }> = ({ active }) => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"
    strokeWidth={active ? 2.5 : 2} strokeLinecap="round" strokeLinejoin="round">
    <rect x="9" y="1" width="6" height="12" rx="3" />
    <path d="M5 10a7 7 0 0 0 14 0" />
    <line x1="12" y1="17" x2="12" y2="21" />
    <line x1="8" y1="21" x2="16" y2="21" />
  </svg>
);

const SettingsTabIcon: React.FC<{ active: boolean }> = ({ active }) => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"
    strokeWidth={active ? 2.5 : 2} strokeLinecap="round" strokeLinejoin="round">
    <circle cx="12" cy="12" r="3" />
    <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
  </svg>
);

const HistoryTabIcon: React.FC<{ active: boolean }> = ({ active }) => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"
    strokeWidth={active ? 2.5 : 2} strokeLinecap="round" strokeLinejoin="round">
    <circle cx="12" cy="12" r="10" />
    <path d="M12 6v6l4 2" />
  </svg>
);

function applyTheme(theme: 'light' | 'dark' | 'system') {
  const root = document.documentElement;
  if (theme === 'dark') {
    root.classList.add('dark');
  } else if (theme === 'light') {
    root.classList.remove('dark');
  } else {
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    root.classList.toggle('dark', prefersDark);
  }
}

const App: React.FC = () => {
  const [currentView, setCurrentView] = useState<View>('main');
  const [latestResult, setLatestResult] = useState<TranscriptionResult | null>(null);
  const [processing, setProcessing] = useState<ProcessingState>({
    isTranscribing: false,
    isFormatting: false,
    progress: 0,
    statusMessage: '',
  });

  const { settings, updateSettings, loaded } = useSettings();
  const { isRecording, duration, audioLevel, startRecording, stopRecording } = useAudioRecorder();

  const isProcessing = processing.isTranscribing || processing.isFormatting;

  // Apply theme
  useEffect(() => {
    applyTheme(settings.theme);
    if (settings.theme === 'system') {
      const mq = window.matchMedia('(prefers-color-scheme: dark)');
      const handler = () => applyTheme('system');
      mq.addEventListener('change', handler);
      return () => mq.removeEventListener('change', handler);
    }
  }, [settings.theme]);

  const handleStartRecording = useCallback(async () => {
    try {
      await startRecording(settings.audioInputDevice);
    } catch (err) {
      console.error('Failed to start recording:', err);
    }
  }, [startRecording, settings.audioInputDevice]);

  const handleStopRecording = useCallback(async () => {
    setProcessing({
      isTranscribing: true,
      isFormatting: false,
      progress: 30,
      statusMessage: 'Transcribing audio...',
    });

    try {
      const blob = await stopRecording();
      if (!blob) {
        setProcessing({ isTranscribing: false, isFormatting: false, progress: 0, statusMessage: '' });
        return;
      }

      setProcessing({
        isTranscribing: false,
        isFormatting: true,
        progress: 70,
        statusMessage: 'Formatting text...',
      });

      const buffer = await blob.arrayBuffer();
      const result = await window.electronAPI.sendAudio(buffer);

      setLatestResult(result);

      if (settings.autoCopy) {
        await window.electronAPI.copyToClipboard(result.formattedText);
      }
      if (settings.autoPaste) {
        await window.electronAPI.pasteText(result.formattedText);
      }
    } catch (err) {
      console.error('Transcription failed:', err);
    } finally {
      setProcessing({ isTranscribing: false, isFormatting: false, progress: 0, statusMessage: '' });
    }
  }, [stopRecording, settings.autoCopy, settings.autoPaste]);

  // Listen for hotkey recording toggle from main process
  useEffect(() => {
    const unsub = window.electronAPI.onRecordingToggle(() => {
      if (isProcessing) return;
      if (isRecording) {
        handleStopRecording();
      } else {
        handleStartRecording();
      }
    });
    return unsub;
  }, [isRecording, isProcessing, handleStartRecording, handleStopRecording]);

  if (!loaded) {
    return (
      <div className="h-screen flex items-center justify-center bg-white dark:bg-surface-900">
        <div className="w-6 h-6 border-2 border-primary-600 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const tabs: { id: View; label: string; icon: React.FC<{ active: boolean }> }[] = [
    { id: 'main', label: 'Record', icon: MicTabIcon },
    { id: 'history', label: 'History', icon: HistoryTabIcon },
    { id: 'settings', label: 'Settings', icon: SettingsTabIcon },
  ];

  return (
    <div className="h-screen flex flex-col bg-white dark:bg-surface-900 text-surface-900 dark:text-surface-50">
      {/* Titlebar */}
      <div className="titlebar flex items-center justify-between px-4 py-2 bg-surface-50 dark:bg-surface-800 border-b border-surface-200 dark:border-surface-700">
        <span className="text-sm font-semibold text-surface-700 dark:text-surface-200 tracking-tight">
          myWhisperer
        </span>
        <div className="flex items-center gap-1">
          <button
            onClick={() => window.electronAPI.minimizeToTray()}
            className="titlebar-button w-7 h-7 flex items-center justify-center rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors"
            aria-label="Minimize to tray"
          >
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="2">
              <line x1="2" y1="6" x2="10" y2="6" />
            </svg>
          </button>
          <button
            onClick={() => window.electronAPI.quitApp()}
            className="titlebar-button w-7 h-7 flex items-center justify-center rounded-lg hover:bg-red-100 dark:hover:bg-red-900/30 hover:text-red-600 transition-colors"
            aria-label="Quit"
          >
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="2">
              <line x1="2" y1="2" x2="10" y2="10" />
              <line x1="10" y1="2" x2="2" y2="10" />
            </svg>
          </button>
        </div>
      </div>

      {/* Navigation */}
      <div className="flex items-center border-b border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900">
        {tabs.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => setCurrentView(id)}
            className={`flex-1 flex items-center justify-center gap-2 py-2.5 text-sm font-medium transition-colors relative
              ${currentView === id
                ? 'text-primary-600 dark:text-primary-400'
                : 'text-surface-500 dark:text-surface-400 hover:text-surface-700 dark:hover:text-surface-300'
              }`}
          >
            <Icon active={currentView === id} />
            {label}
            {currentView === id && (
              <span className="absolute bottom-0 left-1/4 right-1/4 h-0.5 bg-primary-600 dark:bg-primary-400 rounded-full" />
            )}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-hidden">
        {currentView === 'main' && (
          <div className="h-full flex flex-col items-center justify-center gap-8 px-4">
            <RecordButton
              isRecording={isRecording}
              isProcessing={isProcessing}
              duration={duration}
              audioLevel={audioLevel}
              statusMessage={processing.statusMessage}
              onStart={handleStartRecording}
              onStop={handleStopRecording}
            />
            <TranscriptionPanel result={latestResult} />
          </div>
        )}
        {currentView === 'settings' && (
          <SettingsPanel settings={settings} onSave={updateSettings} />
        )}
        {currentView === 'history' && <HistoryPanel />}
      </div>

      {/* Status bar */}
      <StatusBar settings={settings} isRecording={isRecording} />
    </div>
  );
};

export default App;
