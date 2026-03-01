/** Panel displaying the latest transcription result with side-by-side original and formatted text. */
import React, { useState } from 'react';
import type { TranscriptionResult } from '../types';
import { CopyIcon, PasteIcon } from './Icons';

interface TranscriptionPanelProps {
  result: TranscriptionResult | null;
}

const ActionButton: React.FC<{
  onClick: () => void;
  variant?: 'default' | 'primary';
  children: React.ReactNode;
  label: string;
}> = ({ onClick, variant = 'default', children, label }) => (
  <button
    onClick={onClick}
    className={`inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-md transition-colors
      ${variant === 'primary'
        ? 'bg-primary-50 dark:bg-primary-900/30 text-primary-600 dark:text-primary-400 hover:bg-primary-100 dark:hover:bg-primary-900/50'
        : 'bg-surface-100 dark:bg-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-200 dark:hover:bg-surface-600'
      }`}
    aria-label={label}
  >
    {children}
  </button>
);

export const TranscriptionPanel: React.FC<TranscriptionPanelProps> = ({ result }) => {
  const [copied, setCopied] = useState<'raw' | 'formatted' | null>(null);

  if (!result) return null;

  const handleCopy = async (text: string, which: 'raw' | 'formatted') => {
    await window.electronAPI.copyToClipboard(text);
    setCopied(which);
    setTimeout(() => setCopied(null), 2000);
  };

  const handlePaste = async () => {
    await window.electronAPI.pasteText(result.formattedText);
  };

  return (
    <div className="h-full animate-fade-in">
      <div className="h-full flex gap-3">
        {/* Original */}
        <div className="flex-1 min-w-0 rounded-xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 shadow-sm flex flex-col overflow-hidden">
          <div className="flex items-center justify-between px-4 py-2.5 border-b border-surface-100 dark:border-surface-700/50 bg-surface-50/50 dark:bg-surface-800/50">
            <h4 className="text-xs font-semibold uppercase tracking-wider text-surface-400 dark:text-surface-500">
              Original
            </h4>
            <ActionButton onClick={() => handleCopy(result.rawText, 'raw')} label="Copy original text">
              <CopyIcon />
              {copied === 'raw' ? 'Copied!' : 'Copy'}
            </ActionButton>
          </div>
          <div className="flex-1 overflow-y-auto p-4">
            <p className="text-sm text-surface-600 dark:text-surface-300 leading-relaxed whitespace-pre-wrap user-select-text">
              {result.rawText}
            </p>
          </div>
        </div>

        {/* Formatted */}
        <div className="flex-1 min-w-0 rounded-xl border border-primary-200 dark:border-primary-800/40 bg-white dark:bg-surface-800 shadow-sm flex flex-col overflow-hidden">
          <div className="flex items-center justify-between px-4 py-2.5 border-b border-primary-100 dark:border-primary-800/30 bg-primary-50/50 dark:bg-primary-900/20">
            <h4 className="text-xs font-semibold uppercase tracking-wider text-primary-500 dark:text-primary-400">
              Formatted
            </h4>
            <div className="flex items-center gap-1.5">
              <ActionButton onClick={() => handleCopy(result.formattedText, 'formatted')} label="Copy formatted text">
                <CopyIcon />
                {copied === 'formatted' ? 'Copied!' : 'Copy'}
              </ActionButton>
              <ActionButton onClick={handlePaste} variant="primary" label="Paste to active app">
                <PasteIcon />
                Paste
              </ActionButton>
            </div>
          </div>
          <div className="flex-1 overflow-y-auto p-4">
            <p className="text-sm text-surface-800 dark:text-surface-100 leading-relaxed whitespace-pre-wrap user-select-text">
              {result.formattedText}
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};
