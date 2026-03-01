/** Root application component that manages views, recording, and transcription processing. */
import React, { useState, useEffect, useCallback } from 'react';
import type { TranscriptionResult, ProcessingState } from './types';
import { useSettings } from './hooks/useSettings';
import { useAudioRecorder } from './hooks/useAudioRecorder';
import { RecordButton } from './components/RecordButton';
import { TranscriptionPanel } from './components/TranscriptionPanel';
import { SettingsPanel } from './components/SettingsPanel';
import { HistoryPanel } from './components/HistoryPanel';
import { StatusBar } from './components/StatusBar';
import { ToastProvider, useToast } from './components/Toast';
import { MicIcon, SettingsIcon, HistoryIcon, AlertIcon } from './components/Icons';

type View = 'main' | 'settings' | 'history';

const MicTabIcon: React.FC<{ active: boolean }> = ({ active }) => (
  <MicIcon className={`w-[18px] h-[18px] ${active ? 'stroke-[2.5]' : 'stroke-2'}`} />
);

const SettingsTabIcon: React.FC<{ active: boolean }> = ({ active }) => (
  <SettingsIcon className={`w-[18px] h-[18px] ${active ? 'stroke-[2.5]' : 'stroke-2'}`} />
);

const HistoryTabIcon: React.FC<{ active: boolean }> = ({ active }) => (
  <HistoryIcon className={`w-[18px] h-[18px] ${active ? 'stroke-[2.5]' : 'stroke-2'}`} />
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

const AppContent: React.FC = () => {
  const [currentView, setCurrentView] = useState<View>('main');
  const [latestResult, setLatestResult] = useState<TranscriptionResult | null>(null);
  const [processing, setProcessing] = useState<ProcessingState>({
    isProcessing: false,
    progress: 0,
    statusMessage: '',
  });
  const [historyRefresh, setHistoryRefresh] = useState(0);

  const { settings, updateSettings, loaded } = useSettings();
  const { isRecording, duration, audioLevel, startRecording, stopRecording } = useAudioRecorder();
  const { showToast } = useToast();

  const isProcessing = processing.isProcessing;

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
      const message = err instanceof Error && err.name === 'NotAllowedError'
        ? 'Microphone access denied'
        : 'Recording failed';
      showToast(message, 'error');
    }
  }, [startRecording, settings.audioInputDevice, showToast]);

  const handleStopRecording = useCallback(async () => {
    setProcessing({
      isProcessing: true,
      progress: 50,
      statusMessage: 'Processing audio...',
    });

    try {
      const blob = await stopRecording();
      if (!blob) {
        setProcessing({ isProcessing: false, progress: 0, statusMessage: '' });
        return;
      }

      const buffer = await blob.arrayBuffer();
      const result = await window.electronAPI.sendAudio(buffer);

      setLatestResult(result);
      setHistoryRefresh((n) => n + 1);

      // Auto-copy/paste is handled by the main process in audio:process
    } catch (err) {
      const detail = err instanceof Error ? err.message : 'Unknown error';
      showToast(`Transcription failed: ${detail}`, 'error');
    } finally {
      setProcessing({ isProcessing: false, progress: 0, statusMessage: '' });
    }
  }, [stopRecording, showToast]);

  // Listen for hotkey recording toggle from main process (toggle mode only)
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

  const showApiKeyBanner = currentView === 'main' && !settings.apiKey;

  return (
    <div className="h-screen flex flex-col bg-white dark:bg-surface-900 text-surface-900 dark:text-surface-50">
      {/* Titlebar */}
      <div className="titlebar select-none flex items-center justify-between px-4 py-2 bg-surface-50 dark:bg-surface-800 border-b border-surface-200 dark:border-surface-700">
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
            {showApiKeyBanner && (
              <div className="w-full max-w-lg mx-auto">
                <div className="flex items-start gap-3 p-4 rounded-xl bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800">
                  <AlertIcon className="w-5 h-5 text-yellow-600 dark:text-yellow-400 shrink-0 mt-0.5" />
                  <div className="flex-1">
                    <p className="text-sm font-medium text-yellow-800 dark:text-yellow-200">
                      Configure your OpenAI API key in Settings to get started
                    </p>
                    <button
                      onClick={() => setCurrentView('settings')}
                      className="mt-2 text-xs font-medium text-yellow-700 dark:text-yellow-300 underline hover:no-underline"
                    >
                      Go to Settings
                    </button>
                  </div>
                </div>
              </div>
            )}
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
        {currentView === 'history' && <HistoryPanel refreshTrigger={historyRefresh} />}
      </div>

      {/* Status bar */}
      <StatusBar settings={settings} isRecording={isRecording} />
    </div>
  );
};

/** Application root that wraps content with the Toast notification provider. */
const App: React.FC = () => (
  <ToastProvider>
    <AppContent />
  </ToastProvider>
);

export default App;
