# Manual acceptance checks

These require interacting with macOS permissions, a microphone, and target applications. They are not covered by the automated transcript tests.

## Setup and lifecycle

- Fresh app: setup appears, parrot menu-bar icon is visible, no Dock icon.
- Deny microphone, then enable it from System Settings; verify setup refreshes.
- Grant Accessibility; verify shortcut and insertion work. Re-grant if a rebuild invalidates trust.
- Download English assets; verify progress, download failure feedback, retry, and recognition with networking disabled after installation.
- Close setup; relaunch from Finder/Spotlight to reopen it.
- Enable launch at login and log out/in; verify quiet launch when ready.
- Quit from settings; verify the shortcut becomes available to other apps.
- Test macOS 26 on Apple silicon in addition to the development machine.

## Phonon-2

- With no runtime and no cached model, choose Phonon-2 and Download; verify runtime setup, download progress, and that the model lands in `~/.cache/huggingface/hub/models--FermionResearch--Phonon-2`.
- Verify it loads after download, shows its memory use, and that Unload (Settings and menu bar) ends the `fermion` process.
- Dictate while unloaded; confirm the orb says it is loading, early words are kept, and one insertion happens.
- Switch to Apple; confirm the server exits. Quit or force-quit Parrot while loaded; confirm no `fermion` process remains.
- With networking disabled, confirm Phonon-2 still loads and transcribes.

## Dictation

- Hold Control–Option–Space, speak, release; confirm no focus change and exactly one insertion.
- Release immediately during speech-engine startup; confirm the mic stops and the app recovers.
- Repeat dictation many times, including silence, long pauses, punctuation, and short phrases.
- Hold longer than two minutes; confirm automatic finalization.
- Change audio device, disconnect the microphone, or sleep during capture; verify no stuck capture.
- Test multiple displays, full-screen apps, Spaces, and Reduce Motion.
- Check the compact teal orb with silence, loud speech, long transcripts, and multiline error notices. Confirm the finishing ring appears after release and Reduce Motion keeps the orb stationary.
- While idle after dictation, verify no audio capture and no repeating orb rendering; measure CPU and memory with Activity Monitor/Instruments.

## Insertion matrix

For each app, test an empty field, middle-of-text caret, selected text, undo, focus switch during finalization, and clipboard fallback. Record OS/app version, insertion path, and observed result.

| App | Status |
| --- | --- |
| TextEdit | Not yet manually verified |
| Safari text field | Not yet manually verified |
| Notes | Not yet manually verified |
| VS Code | Not yet manually verified |
| Slack | Not yet manually verified |
| Ghostty | Not yet manually verified |

Verify Secure Input does not receive injected text. Clipboard fallback intentionally replaces the prior clipboard content and shows a notice; verify its transcript remains available if the target rejects paste. A paste event being sent is not proof the receiving app accepted it.

## Release

- Verify the parrot app icon in Finder and the monochrome parrot in the menu bar; sound waves should appear during dictation. Check light and dark menu bars.

Developer ID signing, notarization, clean-machine installation, and real-device accuracy/latency measurements remain required before public distribution. No performance or accuracy claims have been benchmarked yet.
