# Contributing to myWhisperer

Thanks for helping out! A few pointers:

- **Build and test:** `swift build && swift test`. The unit tests cover prompts,
  providers, text post-processing, and the dictation state machine, and don't
  need API keys.
- **Run the app:** `scripts/bundle.sh`, then `open ~/Applications/myWhisperer.app`.
  Sign with an Apple Development certificate so permission grants survive
  rebuilds (see the README).
- **UI changes:** render screens with
  `~/Applications/myWhisperer.app/Contents/MacOS/myWhisperer --snapshot all /tmp/shots`
  (add `--dark` for dark mode) and include before/after images in your PR.
- **Prompt or model changes:** run `scripts/eval/eval.py` and paste the output.
  It makes real API calls and costs a few cents.
- **Architecture:** logic that doesn't need AppKit belongs in `MyWhispererCore`,
  behind protocols, so it can be tested with fakes. `Sources/MyWhisperer` holds
  the thin system adapters and the UI.
- **Never block the event-tap callback** in `HotkeyManager`. It delays every
  keystroke on the system; dispatch real work to the main queue.

Please keep pull requests focused, and describe what you tested.
