# myWhisperer

**Open-source voice-to-text for your desktop. Powered by OpenAI Whisper and GPT.**

[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](https://github.com/KunalGehlot/myWhisperer/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey.svg)]()

---

## About

myWhisperer is an open-source desktop application that turns your voice into text using OpenAI's Whisper API, then polishes it with GPT for clean, publication-ready output. It is a local, privacy-first alternative to subscription-based dictation tools like Wispr Flow.

Bring your own OpenAI API key. No subscriptions. No recurring fees. Your data stays yours.

## Features

- **Voice-to-text powered by OpenAI Whisper** -- accurate transcription across 100+ languages
- **AI text formatting with GPT** -- automatic grammar correction, punctuation, and filler word removal
- **Choose any GPT model** -- select from GPT-4, GPT-4-turbo, GPT-4o, GPT-3.5-turbo, or any model available on your API key
- **Global hotkey** -- start and stop recording from anywhere with a configurable keyboard shortcut
- **System tray integration** -- runs quietly in the background, always ready when you need it
- **Auto-paste into active application** -- transcribed text is automatically pasted where your cursor is
- **Personal dictionary** -- add custom terminology, names, and jargon for more accurate transcriptions
- **Transcription history** -- browse, search, and reuse past transcriptions
- **Dark and light theme** -- matches your system preference or set it manually
- **100+ language support** -- Whisper supports transcription in over 100 languages
- **Cross-platform** -- runs on macOS, Windows, and Linux
- **Fully local and private** -- your API key never leaves your machine, and no data is stored on external servers

## Prerequisites

- [Node.js](https://nodejs.org/) 18 or later
- An [OpenAI API key](https://platform.openai.com/api-keys)

## Installation

```bash
# Clone the repository
git clone https://github.com/KunalGehlot/myWhisperer.git
cd myWhisperer

# Install dependencies
npm install

# Start the development server
npm run dev
```

To build distributable packages:

```bash
# Build for your current platform
npm run dist

# Or build for a specific platform
npm run dist:mac
npm run dist:win
npm run dist:linux
```

Built packages are output to the `release/` directory.

## Quick Start

1. Launch myWhisperer.
2. Open **Settings** and enter your OpenAI API key.
3. Choose your preferred GPT model for text formatting (default: GPT-4).
4. Set your global hotkey (default: `Ctrl+Shift+Space` / `Cmd+Shift+Space`).
5. Press the hotkey to start recording. Speak naturally.
6. Press the hotkey again (or release if using push-to-talk mode) to stop.
7. Your transcription is automatically formatted, copied to your clipboard, and pasted into the active application.

## Configuration

All settings are accessible from the Settings panel inside the app:

| Setting | Description | Default |
|---------|-------------|---------|
| API Key | Your OpenAI API key | -- |
| Whisper Model | Model used for transcription | `whisper-1` |
| GPT Model | Model used for text formatting | `gpt-4` |
| Language | Transcription language | Auto-detect |
| Hotkey | Global keyboard shortcut | `Ctrl+Shift+Space` |
| Theme | Light, dark, or system | System |
| Auto-paste | Paste text into active app after transcription | Enabled |
| Auto-copy | Copy text to clipboard after transcription | Enabled |
| Recording Mode | Push-to-talk or toggle | Toggle |
| Audio Input | Microphone device | System default |
| Personal Dictionary | Custom words and phrases for better accuracy | -- |
| Format Prompt | Custom instructions for GPT formatting | Built-in |

## Architecture

myWhisperer follows the standard Electron architecture with a clear separation between the main process and the renderer:

```
+------------------+       IPC        +-------------------+
|  Main Process    | <--------------> |  Renderer Process  |
|  (Node.js)       |                  |  (React + Vite)    |
|                  |                  |                    |
|  - Audio capture |                  |  - UI components   |
|  - Whisper API   |                  |  - Settings panel  |
|  - GPT API       |                  |  - History view    |
|  - Clipboard     |                  |  - Recording state |
|  - System tray   |                  |                    |
|  - Global hotkey |                  |                    |
|  - Settings store|                  |                    |
+------------------+                  +-------------------+
         |
         v
   +-------------+
   |  OpenAI API |
   |  - Whisper  |
   |  - GPT      |
   +-------------+
```

The **main process** handles all system-level operations: audio recording, API calls to OpenAI, clipboard management, system tray, and global hotkey registration. The **renderer process** is a React application that provides the user interface. Communication between processes uses Electron's IPC mechanism through a secure preload bridge.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | [Electron](https://www.electronjs.org/) 33 |
| Frontend | [React](https://react.dev/) 19 |
| Language | [TypeScript](https://www.typescriptlang.org/) 5.7 |
| Styling | [Tailwind CSS](https://tailwindcss.com/) 3.4 |
| Bundler | [Vite](https://vite.dev/) 6 |
| AI | [OpenAI SDK](https://github.com/openai/openai-node) 4.x |
| Storage | [electron-store](https://github.com/sindresorhus/electron-store) 10 |
| Packaging | [electron-builder](https://www.electron.build/) 25 |

## Development

### Project Structure

```
myWhisperer/
  src/
    main/                  # Electron main process
      clipboard-manager.ts # Clipboard and auto-paste logic
      gpt-service.ts       # GPT API integration for text formatting
      settings-store.ts    # Persistent settings with electron-store
      tray-manager.ts      # System tray icon and menu
      whisper-service.ts   # Whisper API integration for transcription
    preload/
      preload.ts           # Secure IPC bridge between main and renderer
    renderer/
      hooks/               # React hooks
      styles/              # Global CSS and Tailwind setup
      types/               # TypeScript type definitions
      main.tsx             # React entry point
  resources/               # App icons and platform-specific assets
  index.html               # HTML entry point
  package.json
  tsconfig.json            # TypeScript config (renderer)
  tsconfig.main.json       # TypeScript config (main process)
  vite.config.ts           # Vite bundler config
  tailwind.config.js       # Tailwind CSS config
```

### Scripts

| Command | Description |
|---------|-------------|
| `npm run dev` | Start both renderer and main process in development mode |
| `npm run build` | Build renderer and main process for production |
| `npm start` | Build and launch the app |
| `npm run dist` | Build and package distributable for current platform |
| `npm run lint` | Run ESLint |
| `npm run typecheck` | Run TypeScript type checking |

### Setting Up Your Development Environment

1. Fork and clone the repository.
2. Install dependencies with `npm install`.
3. Run `npm run dev` to start the app in development mode with hot reload for the renderer.
4. The Vite dev server runs on `http://localhost:5173` and the Electron main process watches for file changes.

## Contributing

Contributions are welcome. Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to get started, code style, and the pull request process.

## Roadmap

Future plans for myWhisperer:

- **Local Whisper model support** -- run transcription entirely on-device without an API key
- **Snippet library** -- save and reuse frequently dictated text blocks
- **Per-app tone profiles** -- automatically adjust GPT formatting style based on the target application (e.g., formal for email, casual for chat)
- **Mobile companion app** -- extend voice-to-text to iOS and Android via React Native

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [OpenAI](https://openai.com/) for the Whisper and GPT APIs
- Inspired by [Wispr Flow](https://www.wispr.com/)
