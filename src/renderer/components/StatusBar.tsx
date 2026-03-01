import React from 'react';
import type { AppSettings } from '../types';

interface StatusBarProps {
  settings: AppSettings;
  isRecording: boolean;
}

export const StatusBar: React.FC<StatusBarProps> = ({ settings, isRecording }) => {
  const hasApiKey = settings.apiKey.length > 0;

  return (
    <div className="flex items-center justify-between px-4 py-1.5 border-t border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/50 text-xs text-surface-500 dark:text-surface-400">
      <div className="flex items-center gap-3">
        <span className="flex items-center gap-1.5">
          <span
            className={`w-1.5 h-1.5 rounded-full ${
              hasApiKey ? 'bg-green-500' : 'bg-surface-400'
            }`}
          />
          {hasApiKey ? 'API Connected' : 'No API Key'}
        </span>
        <span className="text-surface-300 dark:text-surface-600">|</span>
        <span>{settings.gptModel}</span>
      </div>
      <div className="flex items-center gap-3">
        <span className="capitalize">{settings.recordingMode.replace('-', ' ')}</span>
        {isRecording && (
          <>
            <span className="text-surface-300 dark:text-surface-600">|</span>
            <span className="flex items-center gap-1.5 text-red-500">
              <span className="w-1.5 h-1.5 rounded-full bg-red-500 animate-pulse" />
              Recording
            </span>
          </>
        )}
      </div>
    </div>
  );
};
