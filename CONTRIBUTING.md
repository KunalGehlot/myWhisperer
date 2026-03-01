# Contributing to myWhisperer

Thank you for your interest in contributing to myWhisperer. This document provides guidelines and information to help you get started.

## Getting Started

1. **Fork** the repository on GitHub.
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/your-username/myWhisperer.git
   cd myWhisperer
   ```
3. **Install dependencies**:
   ```bash
   npm install
   ```
4. **Create a branch** for your work:
   ```bash
   git checkout -b feature/your-feature-name
   ```
5. **Start the dev server**:
   ```bash
   npm run dev
   ```

## Development Workflow

- Run `npm run dev` to start both the Vite renderer dev server and the Electron main process with file watching.
- The renderer supports hot module replacement. Changes to files in `src/renderer/` will reflect immediately.
- Changes to main process files (`src/main/`) require restarting the Electron process.
- Run `npm run lint` to check for linting errors before committing.
- Run `npm run typecheck` to verify TypeScript types.

## Code Style

- **TypeScript** is used throughout the project. All new code should be written in TypeScript with proper type annotations.
- **React** components should be functional components using hooks.
- **Tailwind CSS** is used for styling. Avoid writing custom CSS unless absolutely necessary.
- Keep functions focused and small. Prefer clear names over comments.
- Follow the existing patterns in the codebase for consistency.

## Commit Messages

Write clear, descriptive commit messages. Use the imperative mood in the subject line:

- Good: `Add personal dictionary export feature`
- Good: `Fix hotkey registration on Linux`
- Avoid: `Added stuff` or `Fixed bug`

## Pull Request Process

1. Ensure your branch is up to date with `main`:
   ```bash
   git fetch origin
   git rebase origin/main
   ```
2. Make sure all checks pass:
   ```bash
   npm run lint
   npm run typecheck
   npm run build
   ```
3. Push your branch to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```
4. Open a pull request against the `main` branch of the upstream repository.
5. Fill in the PR template with a clear description of your changes, the motivation behind them, and any relevant context.
6. Be responsive to review feedback. PRs that go stale may be closed.

## Reporting Issues

When reporting a bug, please include:

- **Operating system and version** (e.g., macOS 15.2, Windows 11, Ubuntu 24.04)
- **myWhisperer version** (check Settings or `package.json`)
- **Steps to reproduce** the issue
- **Expected behavior** vs. **actual behavior**
- **Screenshots or logs** if applicable (check the DevTools console with `Ctrl+Shift+I` / `Cmd+Option+I`)

For feature requests, describe the use case and why it would be valuable.

## Project Structure

```
src/
  main/           # Electron main process (Node.js)
  preload/        # Secure IPC preload bridge
  renderer/       # React frontend (Vite)
    hooks/        # React hooks
    styles/       # CSS and Tailwind
    types/        # TypeScript type definitions
```

## License

By contributing to myWhisperer, you agree that your contributions will be licensed under the [MIT License](LICENSE).
