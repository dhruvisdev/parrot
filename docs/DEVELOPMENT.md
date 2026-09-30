# Developer notes

## Edit, build, and launch

Install Xcode 26 or later and work from the repository root. After changing code or pulling updates, run:

```sh
./scripts/build-app.sh
open build/Parrot.app
```

The build script compiles in release mode, assembles and locally signs the app bundle, and quits any running Parrot before replacing the build. The open command launches that new bundle. If you use a copy in Applications, replace it with the new build before launching that copy. Rebuilding or moving an ad-hoc-signed app may require granting Accessibility again.

For subsequent launches without code changes, only `open build/Parrot.app` is needed. Use the app bundle for testing microphone permissions and insertion.

### What is the difference between build and run?

| Command | What it does | When to use it |
| --- | --- | --- |
| `./scripts/build-app.sh` | Compiles and creates a signed macOS app bundle at `build/Parrot.app`. Does not launch it. | First build and after source changes. |
| `open build/Parrot.app` | Launches the app you already built. Does not compile source changes. | Trying a local build. |
| `swift build` | Compiles a development executable into `.build/`. Does not assemble an app bundle. | Checking whether code compiles. |
| `swift run` | Builds as needed and starts the bare executable. Does not assemble an app bundle. | Not the supported everyday launch path: use the bundle so macOS associates permissions with Parrot’s app identity. |

Someone installing a packaged release does not need Xcode or a build command; building is for people installing from source or developing Parrot. The release packaging process is described below.

To work on the code:

1. Make your changes in `Sources/Parrot`.
2. Run `swift test`.
3. Build the app bundle and try the relevant checks in [validation checklist](VALIDATION.md).
4. Describe the change and your validation in the pull request.

The automated tests cover transcript accumulation, including revised partial results, and Phonon-2 stream events. They do not validate microphone permissions, model downloads, the orb’s appearance, or insertion into other apps. Those need manual testing on a Mac.

The implementation uses SwiftUI, AppKit, AVAudioEngine, SpeechAnalyzer/SpeechTranscriber, Carbon hotkeys, and Accessibility. The optional Phonon-2 engine (`Phonon.swift`, `PhononSession.swift`) drives Fermion’s Python CLI as a child process and speaks its `/v1/audio/stream` WebSocket protocol; the automated tests cover that protocol’s event parsing and phrase joining. The [original proposal](INITIAL_SPEC.md) is background material, not a list of shipped features.

## Packaging a release

Maintainers can create a DMG containing Parrot and an Applications link:

```sh
SIGNING_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" ./scripts/release.sh
```

The script builds, signs, notarizes, and staples the DMG at `build/Parrot-<version>.dmg`. See [scripts/release.sh](../scripts/release.sh) for the one-time `notarytool` credential setup. Set the version in `Resources/Info.plist` before packaging.

To test packaging locally without notarization:

```sh
SIGNING_IDENTITY=- SKIP_NOTARIZE=1 ./scripts/release.sh
```

That local artifact is not suitable for public distribution: other Macs may block it with Gatekeeper. Before publishing, complete the manual validation checklist, verify installation on a clean Mac, and measure resource use before making performance claims.

## Icons

`Sources/Parrot/Mark.swift` defines the shared parrot artwork. The menu bar uses its monochrome template image, which adapts to the menu bar appearance; sound waves appear during dictation. The full-color app icon is bundled separately for Finder and other macOS app surfaces.

After changing the artwork, regenerate the app icon, then rebuild:

```sh
./scripts/make-icon.sh
./scripts/build-app.sh
open build/Parrot.app
```

The generator writes `Resources/AppIcon.icns`. The build script copies it into the bundle, and `CFBundleIconFile` in `Resources/Info.plist` points to it.

## Diagnostics

To inspect diagnostic logs:

```sh
log stream --predicate 'subsystem == "com.inqube.parrot"'
```

