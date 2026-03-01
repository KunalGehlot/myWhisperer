/** Main recording button with audio level visualization and status display. */
import React from 'react';
import { MicIcon, StopIcon } from './Icons';

interface RecordButtonProps {
  isRecording: boolean;
  isProcessing: boolean;
  duration: number;
  audioLevel: number;
  statusMessage: string;
  onStart: () => void;
  onStop: () => void;
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

const SpinnerIcon: React.FC = () => (
  <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="animate-spin">
    <circle cx="12" cy="12" r="10" strokeOpacity="0.25" />
    <path d="M12 2a10 10 0 0 1 10 10" strokeLinecap="round" />
  </svg>
);

export const RecordButton: React.FC<RecordButtonProps> = ({
  isRecording,
  isProcessing,
  duration,
  audioLevel,
  statusMessage,
  onStart,
  onStop,
}) => {
  const handleClick = () => {
    if (isProcessing) return;
    if (isRecording) {
      onStop();
    } else {
      onStart();
    }
  };

  const ringScale = 1 + audioLevel * 0.3;

  return (
    <div className="flex flex-col items-center gap-4">
      <div className="relative flex items-center justify-center">
        {isRecording && (
          <div
            className="absolute w-36 h-36 rounded-full bg-red-500/20 transition-transform duration-100"
            style={{ transform: `scale(${ringScale})` }}
          />
        )}

        {isRecording && (
          <>
            <div className="absolute w-32 h-32 rounded-full border-2 border-red-400/40 animate-ripple" />
            <div
              className="absolute w-32 h-32 rounded-full border-2 border-red-400/30 animate-ripple"
              style={{ animationDelay: '0.5s' }}
            />
          </>
        )}

        <button
          onClick={handleClick}
          disabled={isProcessing}
          className={`
            relative z-10 w-32 h-32 rounded-full flex items-center justify-center
            transition-all duration-200 shadow-lg
            focus:outline-none focus:ring-4 focus:ring-offset-2
            dark:focus:ring-offset-surface-900
            ${isProcessing
              ? 'bg-surface-400 dark:bg-surface-600 cursor-wait text-white focus:ring-surface-300'
              : isRecording
                ? 'bg-gradient-to-br from-red-500 to-red-600 hover:from-red-600 hover:to-red-700 text-white animate-pulse-recording focus:ring-red-300'
                : 'bg-gradient-to-br from-primary-500 to-primary-700 hover:from-primary-600 hover:to-primary-800 text-white focus:ring-primary-300 hover:shadow-xl hover:scale-105 active:scale-95'
            }
          `}
          aria-label={isRecording ? 'Stop recording' : isProcessing ? 'Processing' : 'Start recording'}
        >
          {isProcessing ? <SpinnerIcon /> : isRecording ? <StopIcon className="w-9 h-9" /> : <MicIcon className="w-10 h-10" />}
        </button>
      </div>

      <div className="text-center h-8">
        {isRecording && (
          <span className="text-red-500 dark:text-red-400 font-medium text-lg tabular-nums">
            {formatDuration(duration)}
          </span>
        )}
        {isProcessing && (
          <span className="text-surface-500 dark:text-surface-400 text-sm animate-pulse">
            {statusMessage || 'Processing...'}
          </span>
        )}
        {!isRecording && !isProcessing && (
          <span className="text-surface-400 dark:text-surface-500 text-sm">
            Tap to record
          </span>
        )}
      </div>
    </div>
  );
};
