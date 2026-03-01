# myWhisperer

**Open-source voice-to-text for your desktop. Powered by OpenAI Whisper and GPT.**

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey.svg)]()

---

## About

myWhisperer is an open-source desktop application that turns your voice into text using OpenAI's Whisper API, then polishes it with GPT for clean, publication-ready output. It is a local, privacy-first alternative to subscription-based dictation tools.

Bring your own OpenAI API key. No subscriptions. No recurring fees. Your data stays yours.

## Features

- **Voice-to-text transcription using OpenAI Whisper** -- accurate transcription in 100+ languages
- **Context-aware smart formatting** -- detects the active application (email, chat, code editor, notes, terminal, etc.) and adapts output formatting automatically
- **GPT formatting level slider** -- from 0% (raw transcription) to 100% (fully formatted with context-aware rewriting), with Light, Moderate, and Full tiers
- **Two recording modes** -- Toggle (press to start/stop) and Push-to-Talk (hold to record, release to stop)
- **Global hotkeys** -- `Cmd+Shift+Space` for toggle mode, `Control+Space` for push-to-talk (customizable)
- **System tray integration** -- runs quietly in the background with minimize-to-tray
- **Light/Dark/System theme support** -- matches your OS preference or set manually
- **Personal dictionary** -- add custom terminology, names, and jargon for more accurate transcriptions
- **Auto-copy and auto-paste** -- transcribed text is automatically copied to clipboard and pasted into the active application
- **Transcription history** -- browse, search, and reuse past transcriptions
- **Cross-platform** -- macOS, Windows, and Linux
- **Secure** -- API key encryption via OS keychain (macOS Keychain, Windows DPAPI), context isolation enabled, no external data storage

## Installation

Download the latest release from [GitHub Releases](https://github.com/KunalGehlot/myWhisperer/releases):

| Platform | Format |
|----------|--------|
| macOS | `.dmg` |
| Windows | NSIS installer (`.exe`) or portable `.exe` |
| Linux | `.AppImage` or `.deb` |

**Requires an [OpenAI API key](https://platform.openai.com/api-keys).**

## Getting Started

1. Download and install myWhisperer for your platform.
2. Launch the app and open **Settings**.
3. Enter your OpenAI API key in the API Configuration section.
4. Choose your preferred recording mode (Toggle or Push-to-Talk) and hotkey.
5. Press the hotkey to start recording. Speak naturally.
6. Your transcription is formatted, copied, and pasted automatically.

## Development Setup

### Prerequisites

- [Node.js](https://nodejs.org/) 20+
- [npm](https://www.npmjs.com/)
- An [OpenAI API key](https://platform.openai.com/api-keys) (for runtime)

### Getting Started

```bash
# Clone the repository
git clone https://github.com/KunalGehlot/myWhisperer.git
cd myWhisperer

# Install dependencies
npm install

# Start in development mode (hot reload)
npm run dev
```

### Build and Package

```bash
# Build for production
npm run build

# Package for your current platform
npm run dist

# Package for a specific platform
npm run dist:mac
npm run dist:win
npm run dist:linux
```

Built packages are output to the `release/` directory.

### Quality Checks

```bash
# TypeScript type checking
npm run typecheck

# Run tests
npm test
```

## Configuration

All settings are accessible from the Settings panel inside the app:

| Setting | Description | Default |
|---------|-------------|---------|
| **API Key** | Your OpenAI API key | -- |
| **Whisper Model** | Model used for transcription | `whisper-1` |
| **GPT Model** | Model used for text formatting | `gpt-4` |
| **Formatting Level** | GPT formatting intensity (0-100% slider) | 70% |
| **Custom Format Prompt** | Override the level-based formatting with a custom prompt | -- |
| **Recording Mode** | Toggle or Push-to-Talk | Toggle |
| **Hotkey** | Global keyboard shortcut | `Cmd+Shift+Space` |
| **Language** | Transcription language (20+ presets, auto-detect default) | Auto-detect |
| **Theme** | Light, Dark, or System | System |
| **Audio Input** | Microphone device | System default |
| **Auto-copy** | Copy text to clipboard after transcription | Enabled |
| **Auto-paste** | Paste text into active app after transcription | Enabled |
| **Personal Dictionary** | Custom words and phrases for better accuracy | -- |

### Formatting Levels

The formatting slider controls how aggressively GPT processes your transcription:

| Level | Behavior |
|-------|----------|
| **0%** | No formatting -- raw transcription output |
| **1-30%** | Light -- capitalization, filler word removal, basic punctuation |
| **31-70%** | Moderate -- grammar, punctuation, light sentence flow improvements |
| **71-100%** | Full -- context-aware rewriting based on the active application (email, chat, code editor, etc.) |

Setting a **custom format prompt** overrides the level-based formatting entirely.

## Architecture

myWhisperer follows standard Electron architecture with a clear separation between processes:

```
+-------------------+       IPC        +--------------------+
|  Main Process     | <--------------> |  Renderer Process  |
|  (Node.js)        |                  |  (React + Vite)    |
|                   |                  |                    |
|  - Audio capture  |                  |  - UI components   |
|  - Whisper API    |                  |  - Settings panel  |
|  - GPT API        |                  |  - History view    |
|  - Context detect |                  |  - Recording state |
|  - Clipboard      |                  |                    |
|  - System tray    |                  |                    |
|  - Global hotkeys |                  |                    |
|  - Settings store |                  |                    |
+-------------------+                  +--------------------+
         |
         v
  +--------------+
  |  OpenAI API  |
  |  - Whisper   |
  |  - GPT       |
  +--------------+
```

- **Main process** handles all system-level operations: audio recording, API calls to OpenAI, context detection, clipboard management, system tray, and global hotkey registration.
- **Renderer process** is a React application that provides the user interface, styled with Tailwind CSS.
- **IPC bridge** connects the two processes via a secure preload script with context isolation enabled.

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | [Electron](https://www.electronjs.org/) 35 |
| Frontend | [React](https://react.dev/) 19 |
| Language | [TypeScript](https://www.typescriptlang.org/) 5.7 |
| Styling | [Tailwind CSS](https://tailwindcss.com/) 3.4 |
| Bundler | [Vite](https://vite.dev/) 6 |
| AI | [OpenAI SDK](https://github.com/openai/openai-node) 4.x |
| Storage | [electron-store](https://github.com/sindresorhus/electron-store) 8 |
| Packaging | [electron-builder](https://www.electron.build/) 26 |
| Input hooks | [uiohook-napi](https://github.com/SergioBeworworked/uiohook-napi) (push-to-talk) |

### Project Structure

```
myWhisperer/
  src/
    main/                     # Electron main process
      main.ts                 # App lifecycle, IPC handlers
      gpt-service.ts          # GPT formatting with level-based prompts
      whisper-service.ts      # Whisper API transcription
      context-detector.ts     # Active window detection (macOS/Win/Linux)
      shortcut-manager.ts     # Global shortcuts (toggle + push-to-talk)
      clipboard-manager.ts    # Clipboard and auto-paste
      settings-store.ts       # Persistent settings with electron-store
      tray-manager.ts         # System tray icon and menu
    preload/
      preload.ts              # Secure IPC bridge (context isolation)
    renderer/
      components/             # React UI components
      hooks/                  # React hooks
      styles/                 # Global CSS and Tailwind setup
      types/                  # TypeScript type definitions
      main.tsx                # React entry point
  resources/                  # App icons and platform-specific assets
  .github/workflows/          # CI/CD pipelines
  index.html                  # HTML entry point
  package.json
  tsconfig.json               # TypeScript config (renderer)
  tsconfig.main.json          # TypeScript config (main process)
  vite.config.ts              # Vite bundler config
  tailwind.config.js          # Tailwind CSS config
```

## Contributing

Contributions are welcome.

- Development happens on the `main` branch.
- Pushing to the `broad` branch triggers the auto-release pipeline, which builds and publishes to GitHub Releases for all platforms.
- Before submitting a PR, run `npm run typecheck` and `npm test` to ensure everything passes.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [OpenAI](https://openai.com/) for the Whisper and GPT APIs
- Inspired by [Wispr Flow](https://wisprflow.ai)
