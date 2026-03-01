/** Panel displaying the latest transcription result with copy/paste actions. */
import React, { useState } from 'react';
import type { TranscriptionResult } from '../types';
import { CopyIcon, PasteIcon, ChevronDownIcon } from './Icons';

interface TranscriptionPanelProps {
  result: TranscriptionResult | null;
}

export const TranscriptionPanel: React.FC<TranscriptionPanelProps> = ({ result }) => {
  const [showRaw, setShowRaw] = useState(false);
  const [copied, setCopied] = useState(false);

  if (!result) return null;

  const handleCopy = async () => {
    await window.electronAPI.copyToClipboard(result.formattedText);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handlePaste = async () => {
    await window.electronAPI.pasteText(result.formattedText);
  };

  return (
    <div className="w-full max-w-lg mx-auto animate-fade-in">
      <div className="rounded-xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 shadow-sm overflow-hidden">
        <div className="p-4">
          <p className="text-surface-800 dark:text-surface-100 text-sm leading-relaxed whitespace-pre-wrap user-select-text">
            {result.formattedText}
          </p>
        </div>

        <div className="flex items-center gap-2 px-4 pb-3">
          <button
            onClick={handleCopy}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg
              bg-surface-100 dark:bg-surface-700 text-surface-600 dark:text-surface-300
              hover:bg-surface-200 dark:hover:bg-surface-600 transition-colors"
            aria-label="Copy to clipboard"
          >
            <CopyIcon />
            {copied ? 'Copied!' : 'Copy'}
          </button>
          <button
            onClick={handlePaste}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg
              bg-primary-50 dark:bg-primary-900/30 text-primary-600 dark:text-primary-400
              hover:bg-primary-100 dark:hover:bg-primary-900/50 transition-colors"
            aria-label="Paste to active application"
          >
            <PasteIcon />
            Paste
          </button>
        </div>

        <div className="border-t border-surface-100 dark:border-surface-700">
          <button
            onClick={() => setShowRaw(!showRaw)}
            className="flex items-center gap-2 w-full px-4 py-2 text-xs text-surface-500 dark:text-surface-400
              hover:bg-surface-50 dark:hover:bg-surface-700/50 transition-colors"
            aria-label={showRaw ? 'Hide raw transcription' : 'Show raw transcription'}
          >
            <ChevronDownIcon className={`transition-transform duration-200 ${showRaw ? 'rotate-180' : ''}`} />
            Raw transcription
          </button>
          {showRaw && (
            <div className="px-4 pb-3">
              <p className="text-xs text-surface-500 dark:text-surface-400 leading-relaxed whitespace-pre-wrap user-select-text">
                {result.rawText}
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
