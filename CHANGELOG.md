# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.3] - 2026-03-01

### Fixed

- **Critical: app crash on macOS** — completely removed `uiohook-napi` native module which caused `SIGABRT` crash on launch (native addon incompatible with packaged Electron app)
- Push-to-talk now uses Electron's built-in `globalShortcut` with key-repeat debounce detection — no native dependencies required
- Eliminated all native binary dependencies for maximum cross-platform reliability

## [0.2.2] - 2026-03-01

### Fixed

- **Critical: app crash on macOS** — `uiohook-napi` was imported at startup causing `SIGABRT` when Accessibility permissions were not granted. Now lazy-loaded only when push-to-talk mode is activated.
- Push-to-talk gracefully falls back to toggle mode if `uiohook-napi` fails to initialize
- Clear error message logged when Accessibility permissions are missing

## [0.2.1] - 2026-03-01

### Fixed

- Hotkey capture now uses window-level keyboard listener (reliable on macOS)
- Record button properly centered with overflow-safe container
- Always show both Original and Formatted transcription panels side-by-side
- Added built-in prompt viewer in Settings (collapsible, shows active prompt per level)
- README: macOS Gatekeeper bypass and self-signing instructions
- SEO: updated repo description, 17 GitHub topics, keyword-rich README

## [0.2.0] - 2026-03-01

### Added

- Push-to-talk recording mode with configurable hotkey (default: Control+Space)
- Context-aware smart formatting (detects active application for intelligent formatting)
- GPT formatting level slider (0-100%) with tiered prompts (Light / Moderate / Full)
- Active window context detection for macOS, Windows, and Linux
- Side-by-side transcription view (original and GPT-formatted text)
- Built-in prompt viewer — see the active prompt for each formatting level in Settings
- Customizable global hotkey with click-to-capture keyboard input
- 12 GPT models including GPT-4.1 family, o-series reasoning models
- CI/CD release pipeline (auto-build and publish on push to broad branch)
- GitHub Releases with platform-specific installers (DMG, EXE, AppImage, DEB)
- macOS notarization support (when Apple credentials are configured)
- Unit test framework (Vitest with React Testing Library, 24 tests)
- NSMicrophoneUsageDescription for macOS app permission prompt
- App icons for all platforms (icns, ico, png)
- Icon generation script (scripts/generate-icons.js)
- macOS Gatekeeper bypass and self-signing instructions in README

### Changed

- Upgraded Electron from v33 to v35+ (security fixes)
- Upgraded electron-builder from v25 to v26+ (tar vulnerability fixes)
- UI overhaul: native titlebar on Windows/Linux, hiddenInset on macOS, pill-style navigation
- Recording mode buttons are now fully interactive (push-to-talk enabled)
- Default hotkey changed to `Control+Space`
- Default GPT model changed to `gpt-4.1`
- Default formatting level set to 70% (moderate formatting)
- Default system prompt is now context-aware (adapts to email, chat, code, notes, etc.)
- Record button properly centered with overflow-safe container

### Fixed

- Hotkey capture now uses window-level keyboard listener (reliable on macOS)
- Settings now merge with defaults on upgrade (new fields get proper defaults)
- Record button no longer clips outside its container
- Resolved ASAR integrity bypass vulnerability (GHSA-vmqv-hx8q-j7mg)
- Resolved tar path traversal vulnerabilities (9 high severity)
- 0 npm audit vulnerabilities

## [0.1.0] - 2026-02-28

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
