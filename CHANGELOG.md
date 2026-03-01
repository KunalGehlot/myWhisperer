# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Added

- Core voice-to-text transcription powered by OpenAI Whisper API
- GPT-based text formatting and post-processing (grammar, punctuation, filler word removal)
- Model selection for GPT formatting (GPT-4, GPT-4-turbo, GPT-4o, GPT-4o-mini, GPT-3.5-turbo)
- Global hotkey for start/stop recording with configurable keyboard shortcut
- Toggle recording mode (push-to-talk coming soon)
- System tray integration with background operation
- Auto-paste transcribed text into the active application
- Auto-copy transcribed text to clipboard
- Personal dictionary for custom terminology and jargon
- Transcription history with browse and delete functionality
- Dark and light theme support with system preference detection
- Audio input device selection
- Custom GPT format prompt for personalized text styling
- Cross-platform support for macOS, Windows, and Linux
- Secure IPC bridge between main and renderer processes
- Toast notification system for user feedback
- Confirmation dialogs for destructive actions
- Shared icon component library

### Fixed

- Application crash on launch due to electron-store ESM incompatibility
- Incorrect file paths preventing Electron from finding main process and preload scripts
- Content Security Policy blocking development server
- Missing macOS microphone permission request
- Double clipboard copy/paste operations
- Stale system tray context menu
- Global hotkey state not toggling correctly
- Misleading processing state indicators
- Settings input not validated
- API key stored without encryption (now uses OS keychain)
- Command injection risk in clipboard manager
- Unbounded history storage (capped at 500)
- Missing error feedback for users
- Aggressive text selection prevention
- Missing accessibility labels
- Inconsistent default settings between main and renderer
- MediaRecorder mimeType compatibility

### Improved

- UI/UX polish across all panels
- Code quality with proper TypeScript types and JSDoc comments
