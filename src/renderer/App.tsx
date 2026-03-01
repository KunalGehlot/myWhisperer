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
  const [platform, setPlatform] = useState('');

  const { settings, updateSettings, loaded } = useSettings();
  const { isRecording, duration, audioLevel, startRecording, stopRecording } = useAudioRecorder();
  const { showToast } = useToast();

  const isProcessing = processing.isProcessing;
  const isMac = platform === 'darwin';

  useEffect(() => {
    window.electronAPI.getPlatform().then(setPlatform);
  }, []);

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
    } catch (err) {
      const detail = err instanceof Error ? err.message : 'Unknown error';
      showToast(`Transcription failed: ${detail}`, 'error');
    } finally {
      setProcessing({ isProcessing: false, progress: 0, statusMessage: '' });
    }
  }, [stopRecording, showToast]);

  // Listen for hotkey events from main process (toggle mode)
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

  // Listen for push-to-talk events from main process
  useEffect(() => {
    const unsubStart = window.electronAPI.onRecordingStart(() => {
      if (isProcessing || isRecording) return;
      handleStartRecording();
    });
    const unsubStop = window.electronAPI.onRecordingStop(() => {
      if (!isRecording) return;
      handleStopRecording();
    });
    return () => {
      unsubStart();
      unsubStop();
    };
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
    <div className="h-screen flex flex-col bg-gradient-to-b from-surface-50 to-white dark:from-surface-900 dark:to-surface-900 text-surface-900 dark:text-surface-50">
      {/* macOS drag region - only shown on macOS where we use hiddenInset titlebar */}
      {isMac && (
        <div className="titlebar h-12 shrink-0 flex items-center justify-center">
          <span className="text-[11px] font-semibold text-surface-400 dark:text-surface-500 tracking-widest uppercase">
            myWhisperer
          </span>
        </div>
      )}

      {/* Navigation */}
      <nav className={`no-drag flex items-center gap-1 px-3 py-2 border-b border-surface-200/60 dark:border-surface-700/60 ${!isMac ? 'pt-3' : ''}`}>
        {tabs.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => setCurrentView(id)}
            className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm transition-all duration-200
              ${currentView === id
                ? 'bg-primary-100 dark:bg-primary-900/40 text-primary-700 dark:text-primary-300 font-medium shadow-sm'
                : 'text-surface-500 dark:text-surface-400 hover:text-surface-700 dark:hover:text-surface-200 hover:bg-surface-100 dark:hover:bg-surface-700/50'
              }`}
          >
            <Icon active={currentView === id} />
            {label}
          </button>
        ))}
      </nav>

      {/* Content */}
      <div className="flex-1 min-h-0 overflow-y-auto">
        {currentView === 'main' && (
          <div className="h-full flex flex-col">
            {showApiKeyBanner && (
              <div className="px-4 pt-4">
                <div className="max-w-lg mx-auto flex items-start gap-3 p-4 rounded-xl bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800">
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
            <div className="flex items-center justify-center py-8 shrink-0">
              <RecordButton
                isRecording={isRecording}
                isProcessing={isProcessing}
                duration={duration}
                audioLevel={audioLevel}
                statusMessage={processing.statusMessage}
                recordingMode={settings.recordingMode}
                onStart={handleStartRecording}
                onStop={handleStopRecording}
              />
            </div>
            {latestResult && (
              <div className="flex-1 min-h-0 px-4 pb-4">
                <TranscriptionPanel result={latestResult} />
              </div>
            )}
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
