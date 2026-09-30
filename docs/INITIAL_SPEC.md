# Local Dictation App — Spec

## One-liner
A menu-bar-only macOS dictation app. Hold a key, speak, text appears at your cursor. Fully local, fully open source, no paid tier, ever.

## Non-goals
No cloud, no accounts, no telemetry, no LLM post-processing, no translation, no meeting recording, no cross-platform, no file-transcription UI (CLI covers it). English-only in v1.

## Principles
1. Invisible until invoked. No Dock icon, no window on launch.
2. Never steal focus. The target text field must never lose focus.
3. Never silently fail. If insertion is impossible, say so and leave text on the clipboard.
4. Everything on disk is visible and deletable by the user.

---

## Architecture

```
┌─────────────────────────────────────────┐
│ menu bar (NSStatusItem, LSUIElement)    │
└───────────────┬─────────────────────────┘
                │
        ┌───────▼────────┐
        │  HotkeyMonitor │  CGEventTap, key-down/up for hold-to-talk
        └───────┬────────┘
                │ captures frontmost app + focused AXUIElement FIRST
        ┌───────▼────────┐
        │  AudioCapture  │  AVAudioEngine → AVAudioConverter → 16kHz mono
        └───────┬────────┘
                │
        ┌───────▼────────┐
        │  Engine        │  protocol: AppleEngine | WhisperEngine
        └───────┬────────┘
                │ partials + finals
        ┌───────▼────────┐        ┌──────────────┐
        │  Inserter      │        │ OrbPanel     │ nonactivating NSPanel
        └───────┬────────┘        └──────────────┘
                │
        ┌───────▼────────┐
        │  HistoryStore  │  SQLite, retention policy
        └────────────────┘
```

**Engine protocol** with two implementations:
- `AppleEngine` — `SpeechAnalyzer` + `SpeechTranscriber`, macOS 26+, default. Gives live partials via `volatileResults`.
- `WhisperEngine` — whisper.cpp, fallback for macOS 15 and below, and for users who want a specific model. Batch only, no partials.

Keep the protocol narrow: `start(stream) -> AsyncStream<Transcript>` where `Transcript` has `text` and `isFinal`.

**Insertion chain**, in order, each falling through on failure:
1. `AXUIElementSetAttributeValue(el, kAXSelectedText, text)` — direct, no clipboard, undo-safe
2. Clipboard + synthesized Cmd+V, with prior clipboard contents saved and restored after ~150ms
3. `CGEvent` + `keyboardSetUnicodeString` — slow, works where paste is blocked
4. Leave on clipboard + notification "Copied, couldn't insert here"

Check `IsSecureEventInputEnabled()` up front; if true, jump to step 4 rather than failing through 1–3.

---

## UI

**Orb (during speech).**
A nonactivating `NSPanel`, no titlebar, no shadow, ignores mouse events, positioned bottom-center or near the caret if the AX element gives you a frame.

- SwiftUI + Metal shader or `Canvas` for the orb. A sphere of layered noise-displaced gradients.
- Amplitude drives radius and displacement — pull RMS from the audio tap, smooth it with a low-pass filter so it breathes rather than jitters.
- Three states: **listening** (slow idle pulse), **speaking** (amplitude-reactive, brighter), **transcribing** (rotation, no amplitude).
- Live partial text rendered under the orb in a small pill, fading in word by word. This is the feature Handy doesn't have and the reason the app feels different.
- Total lifetime under 200ms to appear, instant to dismiss. Any animation that delays dictation is a bug.

**Main window (only on menu-bar click).** Three tabs, nothing more:

- **History** — reverse-chronological list, search field, per-item copy and delete, target app shown as an icon next to each entry, retention setting at the bottom ("keep 30 days", "keep 500 items", "keep forever"), and a Delete All button.
- **Settings** — hotkey recorder, hold-to-talk vs toggle, input device picker, engine picker, launch at login, a permissions block showing green/red for Accessibility, Input Monitoring, and Microphone with a button that opens the right System Settings pane.
- **Models** — the installed engine list. For Apple: "Managed by macOS, 0 MB in your app" and the locale install state. For Whisper: name, size, exact path, a reveal-in-Finder button, and delete. Downloads show progress and are resumable.

Vocabulary can be a fourth tab later, or a text area in Settings for v1 — a newline-separated word list fed as bias terms. Don't build a UI for it until you know the engine respects it.

---

## Data

```
~/Library/Application Support/<app>/
  history.sqlite
  models/            (whisper only)
  config.toml        (human-editable, watched for changes)
```

Config in TOML, not a plist, so it's diffable and editable from Helix.

History schema: `id, text, created_at, duration_ms, engine, target_bundle_id, insert_method`. Storing `insert_method` means your own failure telemetry lives locally and you can debug which apps use which path.

---

## Milestones

**Week 1 — the core loop.**
Menu bar item, hotkey, audio capture, `AppleEngine`, AX insertion with the full fallback chain, SQLite history append. No UI beyond the menu bar. Test against TextEdit, Safari, Notes, Ghostty, VS Code, Slack. Build the app-compatibility matrix as you go — it's the most valuable artifact you'll produce.

**Week 2 — the orb and the window.**
Orb with amplitude reactivity and live partials. History, Settings, Models tabs. Permissions onboarding.

**Week 3 — the engine fallback and the daemon.**
`WhisperEngine` with model download and management. Unix socket exposing `transcribe` so other tools can call it, plus a small CLI client. This is what makes it more than a dictation app for you.

**Week 4 — shipping.**
Codesign, notarize, hardened runtime, Sparkle updates, Homebrew cask, README with a GIF. This week is not optional and always takes longer than expected.

---

## What determines whether this succeeds
Not features. Two things: does the text land in the right place every single time, and does the orb plus live partials feel good enough that you prefer it to Handy. Build the insertion chain first and test it brutally. If week 1 doesn't beat Handy's reliability, stop — the rest doesn't matter.
