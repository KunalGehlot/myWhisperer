import React, { useState, useEffect, useCallback } from 'react';
import type { TranscriptionResult } from '../types';

const SearchIcon: React.FC = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <circle cx="11" cy="11" r="8" />
    <line x1="21" y1="21" x2="16.65" y2="16.65" />
  </svg>
);

const CopyIcon: React.FC = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <rect x="9" y="9" width="13" height="13" rx="2" />
    <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
  </svg>
);

const TrashIcon: React.FC = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <polyline points="3 6 5 6 21 6" />
    <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
  </svg>
);

function formatTimestamp(ts: number): string {
  const d = new Date(ts);
  const now = new Date();
  const diff = now.getTime() - d.getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'Just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  return d.toLocaleDateString();
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return m > 0 ? `${m}m ${s}s` : `${s}s`;
}

export const HistoryPanel: React.FC = () => {
  const [items, setItems] = useState<TranscriptionResult[]>([]);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [copiedId, setCopiedId] = useState<string | null>(null);

  const loadHistory = useCallback(async () => {
    const history = await window.electronAPI.getHistory();
    setItems(history);
  }, []);

  useEffect(() => {
    loadHistory();
  }, [loadHistory]);

  const filtered = search.trim()
    ? items.filter(
        (i) =>
          i.formattedText.toLowerCase().includes(search.toLowerCase()) ||
          i.rawText.toLowerCase().includes(search.toLowerCase())
      )
    : items;

  const handleCopy = async (item: TranscriptionResult) => {
    await window.electronAPI.copyToClipboard(item.formattedText);
    setCopiedId(item.id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const handleDelete = async (id: string) => {
    await window.electronAPI.deleteHistoryItem(id);
    setItems((prev) => prev.filter((i) => i.id !== id));
    if (expandedId === id) setExpandedId(null);
  };

  const handleClearAll = async () => {
    await window.electronAPI.clearHistory();
    setItems([]);
    setExpandedId(null);
  };

  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="flex items-center gap-2 px-4 pt-4 pb-2">
        <div className="relative flex-1">
          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-surface-400">
            <SearchIcon />
          </span>
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search transcriptions..."
            className="w-full pl-9 pr-3 py-2 rounded-lg border border-surface-300 dark:border-surface-600
              bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 text-sm
              focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent transition-colors"
          />
        </div>
        {items.length > 0 && (
          <button
            onClick={handleClearAll}
            className="px-3 py-2 text-xs font-medium rounded-lg text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors shrink-0"
          >
            Clear All
          </button>
        )}
      </div>

      {/* List */}
      <div className="flex-1 overflow-y-auto px-4 pb-4">
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-center py-12">
            <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="text-surface-300 dark:text-surface-600 mb-3">
              <circle cx="12" cy="12" r="10" />
              <path d="M12 6v6l4 2" />
            </svg>
            <p className="text-surface-400 dark:text-surface-500 text-sm">
              {search ? 'No matching transcriptions' : 'No transcriptions yet'}
            </p>
            {!search && (
              <p className="text-surface-300 dark:text-surface-600 text-xs mt-1">
                Your transcriptions will appear here
              </p>
            )}
          </div>
        ) : (
          <div className="space-y-2">
            {filtered.map((item) => {
              const isExpanded = expandedId === item.id;
              return (
                <div
                  key={item.id}
                  className="rounded-xl border border-surface-200 dark:border-surface-700
                    bg-white dark:bg-surface-800 overflow-hidden transition-all"
                >
                  <button
                    onClick={() => setExpandedId(isExpanded ? null : item.id)}
                    className="w-full text-left px-4 py-3 hover:bg-surface-50 dark:hover:bg-surface-700/50 transition-colors"
                  >
                    <p className="text-sm text-surface-800 dark:text-surface-100 line-clamp-2">
                      {item.formattedText}
                    </p>
                    <div className="flex items-center gap-3 mt-1.5">
                      <span className="text-xs text-surface-400 dark:text-surface-500">
                        {formatTimestamp(item.timestamp)}
                      </span>
                      <span className="text-xs text-surface-400 dark:text-surface-500">
                        {formatDuration(item.duration)}
                      </span>
                      <span className="text-xs text-surface-400 dark:text-surface-500">
                        {item.model}
                      </span>
                    </div>
                  </button>

                  {isExpanded && (
                    <div className="px-4 pb-3 border-t border-surface-100 dark:border-surface-700">
                      <p className="text-sm text-surface-700 dark:text-surface-200 whitespace-pre-wrap py-3 user-select-text">
                        {item.formattedText}
                      </p>
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => handleCopy(item)}
                          className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium rounded-lg
                            bg-surface-100 dark:bg-surface-700 text-surface-600 dark:text-surface-300
                            hover:bg-surface-200 dark:hover:bg-surface-600 transition-colors"
                        >
                          <CopyIcon />
                          {copiedId === item.id ? 'Copied!' : 'Copy'}
                        </button>
                        <button
                          onClick={() => handleDelete(item.id)}
                          className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium rounded-lg
                            text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                        >
                          <TrashIcon />
                          Delete
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};
