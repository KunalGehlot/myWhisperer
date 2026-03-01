import React from 'react';

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
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

const MicIcon: React.FC = () => (
  <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <rect x="9" y="1" width="6" height="12" rx="3" />
    <path d="M5 10a7 7 0 0 0 14 0" />
    <line x1="12" y1="17" x2="12" y2="21" />
    <line x1="8" y1="21" x2="16" y2="21" />
  </svg>
);

const StopIcon: React.FC = () => (
  <svg width="36" height="36" viewBox="0 0 24 24" fill="currentColor">
    <rect x="5" y="5" width="14" height="14" rx="2" />
  </svg>
);

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
        {/* Audio level ring */}
        {isRecording && (
          <div
            className="absolute w-36 h-36 rounded-full bg-red-500/20 transition-transform duration-100"
            style={{ transform: `scale(${ringScale})` }}
          />
        )}

        {/* Ripple animations when recording */}
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
          {isProcessing ? <SpinnerIcon /> : isRecording ? <StopIcon /> : <MicIcon />}
        </button>
      </div>

      {/* Status text */}
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
