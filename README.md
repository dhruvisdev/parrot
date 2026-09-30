# Parrot

**Hold a shortcut. Speak. Release to type.**

Parrot is a native macOS menu-bar app for on-device dictation. Hold **Control–Option–Space** in a text field, speak, and release to insert your words. A small teal orb shows live transcription without taking focus.

- On-device transcription using Apple’s speech model, or optionally [Phonon-2](#phonon-2-optional-engine), after the initial model download.
- No account, recording archive, or transcript history.
- Customizable shortcut and optional launch at login.
- Built with SwiftUI and AppKit, with no external package dependencies.

Parrot is an early project. Compatibility with individual apps is still being checked; see the [manual validation checklist](docs/VALIDATION.md).

## Requirements

- **macOS 26 or later.** The initial target is Apple silicon with hardware supported by Apple’s `SpeechTranscriber`.
- **English (US)** for the current version.
- Microphone and Accessibility permissions.
- An internet connection to download Apple’s speech assets if they are not already installed. Transcription runs on device afterward.
- **Xcode 26 or later** to build from source.

## Build once, then launch

From a local checkout of this repository, run:

```sh
./scripts/build-app.sh
```

This compiles the source in release mode, assembles `build/Parrot.app`, and signs it locally with an ad-hoc signature. It also quits a running Parrot before replacing the build.

For everyday use, copy `build/Parrot.app` into **Applications** using Finder, then open it and grant permissions. Keeping the app in one location helps macOS track those permissions.

For a quick development launch, use:

```sh
open build/Parrot.app
```

**You do not need to build every time you use Parrot.** Once the app exists, open it from Finder, Spotlight, or Applications. Rebuild when you change the source or pull an update, then replace your installed copy. Moving or rebuilding an ad-hoc-signed app may require granting Accessibility again.

See [Developer notes](docs/DEVELOPMENT.md) for command differences, the edit/build/run workflow, and DMG packaging. Installing a packaged release does not require Xcode.

## First launch

1. Allow **Microphone** so Parrot can hear you while you hold the shortcut.
2. Allow **Accessibility** so Parrot can insert text into the focused app.
3. Download the English speech model if setup asks for it.
4. Close setup, focus a text field, and hold **Control–Option–Space**.
5. Speak, then release. The orb shows “Finishing…” while the final text is prepared, then Parrot inserts it once.

Press **Escape** while the orb is visible to cancel without inserting text.

Click the parrot icon in the menu bar for **Settings** or **Quit**. Opening Parrot again from Finder or Spotlight also opens Settings. There is no Dock icon; closing Settings leaves Parrot running.

In Settings, click the shortcut and press a new combination: a key with Control, Option, or Command, or a function key alone. Escape cancels shortcut recording. You can also enable **Start quietly at login**.

## Phonon-2 (optional engine)

Settings → **Speech engine** switches between Apple’s model and [Phonon-2](https://huggingface.co/FermionResearch/Phonon-2), a 164 MB English model from Fermion Research that runs on device with MLX.

- **Download** sets up a private Python runtime for Fermion’s engine in `~/Library/Application Support/Parrot/Phonon runtime` (about 450 MB; needs [uv](https://docs.astral.sh/uv/) or Python 3.10+), then runs `hf download FermionResearch/Phonon-2` into the standard Hugging Face cache, `~/.cache/huggingface/hub`. If the `hf` CLI is not installed, the runtime’s copy is used. On first load, Fermion unpacks a verified copy into `~/.cache/fermion`.
- Parrot runs `fermion serve` as a local process, offline, bound to `127.0.0.1` with a random API key, and streams your microphone to it while you hold the shortcut. It uses about 2–3 GB of memory while loaded.
- **Unload** (in Settings or the menu bar) ends that process and returns its memory. The model loads again the next time you dictate, which takes about 10 seconds; audio spoken meanwhile is kept. Switching back to Apple unloads it, and the server also exits when Parrot quits.

Phonon-2’s weights are CC-BY-4.0, based on NVIDIA’s Parakeet TDT 0.6B v3.

## Privacy and insertion

Parrot captures audio only during dictation and does not write audio or transcript files. Preferences are stored locally in UserDefaults; Apple manages speech assets in system storage. The macOS microphone privacy indicator remains visible during capture. Parrot uses a registered system shortcut and does not request Input Monitoring.

Live transcription is provisional. Only the final transcript is inserted after release. Parrot first attempts direct Accessibility insertion. When that is unavailable, it pastes through the clipboard and restores the previous contents a second later, unless the clipboard has changed. Dictated text is marked transient for clipboard managers that honor that marker.

If the original app or focused field changes, or Secure Input is enabled, Parrot copies the transcript and shows a notice instead of sending keystrokes. You can then paste it yourself. Apps differ in how they accept text, and Parrot cannot always confirm that a paste succeeded.

Capture has a two-minute safety limit, and finalization has a twenty-second timeout. The orb disappears after use and its animation views are released.

## Troubleshooting

- **Nothing happens when you hold the shortcut:** open Settings from the menu bar and check permissions and model installation. Try a different shortcut if another app uses the same combination.
- **Permissions stopped working after a rebuild or move:** check Parrot in System Settings → Privacy & Security → Accessibility and grant access again if needed.
- **Text was copied instead of inserted:** focus the intended field and paste. See the notice in the orb for the reason.
- **Model download failed:** check your connection, open Settings, and retry the download.

## Contributing

Bug reports and focused pull requests are welcome. For bugs, include your macOS version, Mac model, steps to reproduce, and the affected app when reporting insertion problems. Avoid sharing private transcripts or sensitive logs.

See [Developer notes](docs/DEVELOPMENT.md) for building, testing, icon generation, and releases. Include the checks you ran with your pull request.
