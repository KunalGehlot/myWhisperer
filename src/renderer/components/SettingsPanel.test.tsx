import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import React from 'react';
import { SettingsPanel } from './SettingsPanel';
import { ToastProvider } from './Toast';
import type { AppSettings } from '../types';

// Mock navigator.mediaDevices.enumerateDevices
Object.defineProperty(navigator, 'mediaDevices', {
  value: {
    enumerateDevices: vi.fn().mockResolvedValue([]),
  },
  writable: true,
});

const defaultSettings: AppSettings = {
  apiKey: 'sk-test-key-123',
  whisperModel: 'whisper-1',
  gptModel: 'gpt-4',
  language: 'auto',
  hotkey: 'CommandOrControl+Shift+Space',
  theme: 'system',
  autoPaste: true,
  autoCopy: true,
  recordingMode: 'toggle',
  audioInputDevice: 'default',
  personalDictionary: [],
  formatPrompt: '',
  gptFormattingLevel: 70,
};

function renderSettings(overrides: Partial<AppSettings> = {}, onSave = vi.fn()) {
  const settings = { ...defaultSettings, ...overrides };
  return render(
    <ToastProvider>
      <SettingsPanel settings={settings} onSave={onSave} />
    </ToastProvider>
  );
}

describe('SettingsPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders all settings sections', () => {
    renderSettings();

    expect(screen.getByText('API Configuration')).toBeInTheDocument();
    expect(screen.getByText('Models')).toBeInTheDocument();
    expect(screen.getByText('Recording')).toBeInTheDocument();
    expect(screen.getByText('Language')).toBeInTheDocument();
    expect(screen.getByText('Formatting')).toBeInTheDocument();
    expect(screen.getByText('Appearance')).toBeInTheDocument();
    expect(screen.getByText('Behavior')).toBeInTheDocument();
  });

  it('renders formatting level slider with correct label', () => {
    renderSettings({ gptFormattingLevel: 50 });

    const slider = screen.getByRole('slider');
    expect(slider).toBeInTheDocument();
    expect(slider).toHaveValue('50');
    expect(screen.getByText('Raw')).toBeInTheDocument();
    expect(screen.getByText('Full')).toBeInTheDocument();
  });

  it('shows correct formatting level description for different levels', () => {
    const { unmount } = renderSettings({ gptFormattingLevel: 0 });
    expect(screen.getByText(/No formatting \(raw transcription\)/)).toBeInTheDocument();
    unmount();

    const { unmount: unmount2 } = renderSettings({ gptFormattingLevel: 20 });
    expect(screen.getByText(/Light \(capitalization, filler removal\)/)).toBeInTheDocument();
    unmount2();

    const { unmount: unmount3 } = renderSettings({ gptFormattingLevel: 50 });
    expect(screen.getByText(/Moderate \(grammar, punctuation\)/)).toBeInTheDocument();
    unmount3();

    renderSettings({ gptFormattingLevel: 85 });
    expect(screen.getByText(/context-aware rewrite/i)).toBeInTheDocument();
  });

  it('renders Toggle and Push to Talk buttons that are not disabled', () => {
    renderSettings();

    const toggleBtn = screen.getByRole('button', { name: 'Toggle' });
    const pttBtn = screen.getByRole('button', { name: 'Push to Talk' });

    expect(toggleBtn).toBeInTheDocument();
    expect(pttBtn).toBeInTheDocument();
    expect(toggleBtn).not.toBeDisabled();
    expect(pttBtn).not.toBeDisabled();
  });

  it('renders theme buttons correctly', () => {
    renderSettings();

    expect(screen.getByRole('button', { name: /Light/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Dark/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /System/i })).toBeInTheDocument();
  });

  it('API key input works with show/hide toggle', () => {
    renderSettings({ apiKey: 'sk-secret-key' });

    const input = screen.getByPlaceholderText('sk-...');
    expect(input).toHaveAttribute('type', 'password');
    expect(input).toHaveValue('sk-secret-key');

    // Click to show
    const toggleBtn = screen.getByLabelText('Show API key');
    fireEvent.click(toggleBtn);
    expect(input).toHaveAttribute('type', 'text');

    // Click to hide
    const hideBtn = screen.getByLabelText('Hide API key');
    fireEvent.click(hideBtn);
    expect(input).toHaveAttribute('type', 'password');
  });

  it('renders Save Settings button', () => {
    renderSettings();
    expect(screen.getByRole('button', { name: 'Save Settings' })).toBeInTheDocument();
  });
});
