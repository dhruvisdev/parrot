import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices
import Speech
import ServiceManagement
import Carbon

enum Engine: String, CaseIterable {
    case apple, phonon
    var name: String { self == .apple ? "Apple" : "Phonon-2" }
}

@MainActor final class AppModel: ObservableObject {
    @Published var microphone = false
    @Published var accessibility = false
    @Published var modelReady = false
    @Published var downloading = false
    @Published var progress: Double? = 0
    @Published var progressLabel = ""
    @Published var message = ""
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var shortcut = Shortcut.load()
    @Published var recording = false
    @Published var engine = Engine(rawValue: UserDefaults.standard.string(forKey: "engine") ?? "") ?? .apple
    @Published var phononInstalled = false
    @Published var phononState = PhononServer.State.unloaded
    let phonon = PhononServer()
    var hotkey: Hotkey?
    private var monitor: Any?
    var engineReady: Bool { engine == .apple ? modelReady : phononInstalled }
    var ready: Bool { microphone && accessibility && engineReady }

    init() {
        phonon.onChange = { [weak self] in
            guard let self else { return }
            phononState = phonon.state
        }
    }

    func refresh() async {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibility = AXIsProcessTrusted()
        loginEnabled = SMAppService.mainApp.status == .enabled
        phononInstalled = Phonon.installed
        do {
            let transcriber = try await SpeechSession.transcriber()
            modelReady = await AssetInventory.status(forModules: [transcriber]) == .installed
        } catch { message = error.localizedDescription }
    }
    func requestMicrophone() async {
        microphone = await AVCaptureDevice.requestAccess(for: .audio)
        if !microphone { openPrivacy("Privacy_Microphone") }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibility = AXIsProcessTrustedWithOptions(options)
        if !accessibility { openPrivacy("Privacy_Accessibility") }
    }
    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) { NSWorkspace.shared.open(url) }
    }
    func download() async {
        guard !downloading else { return }
        downloading = true; message = ""; progress = 0
        defer { downloading = false }
        do {
            let transcriber = try await SpeechSession.transcriber()
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                let monitor = Task { @MainActor in
                    while !Task.isCancelled {
                        progress = request.progress.fractionCompleted
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                defer { monitor.cancel() }
                try await request.downloadAndInstall()
            }
            await refresh()
        } catch { message = error.localizedDescription }
    }
    func downloadPhonon() async {
        guard !downloading else { return }
        downloading = true; message = ""; progress = nil
        defer { downloading = false; progressLabel = "" }
        do {
            try await Phonon.install { [weak self] label, value in self?.progressLabel = label; self?.progress = value }
            await refresh()
            if engine == .phonon { loadPhonon() }
        } catch { message = error.localizedDescription; await refresh() }
    }
    func loadPhonon() {
        Task {
            do { _ = try await phonon.load() }
            catch is CancellationError {}
            catch { message = error.localizedDescription }
        }
    }
    func unloadPhonon() { phonon.unload() }
    /// Phonon-2 is loaded when chosen so the first dictation is quick, and leaves memory when Apple's model takes over.
    func setEngine(_ engine: Engine) {
        guard engine != self.engine else { return }
        self.engine = engine; message = ""
        UserDefaults.standard.set(engine.rawValue, forKey: "engine")
        if engine == .phonon { if phononInstalled { loadPhonon() } } else { unloadPhonon() }
    }
    /// Key presses go to the recorder while it is open, so the current shortcut is released until recording ends.
    func startRecording() {
        guard monitor == nil else { return }
        recording = true; message = ""
        hotkey?.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.record(event); return nil
        }
    }
    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        recording = false
        do { try hotkey?.register(shortcut) } catch { message = error.localizedDescription }
    }
    func resetShortcut() { use(.standard) }
    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { stopRecording(); return }
        guard let candidate = Shortcut(event: event) else {
            message = "Include ⌃, ⌥, or ⌘ with the key. Function keys can be used alone."; return
        }
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        recording = false
        use(candidate)
    }
    private func use(_ candidate: Shortcut) {
        let previous = shortcut
        do {
            try hotkey?.register(candidate)
            shortcut = candidate; candidate.save(); message = ""
        } catch {
            message = error.localizedDescription
            try? hotkey?.register(previous)
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { message = "Allow Parrot in System Settings → General → Login Items." }
        } catch { message = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(nsImage: ParrotMark.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parrot").font(.largeTitle.bold())
                    Text("A thought, spoken. Text, wherever you are.").foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 14) {
                permission("Microphone", detail: "Only active while you hold the shortcut.", ready: model.microphone) { Task { await model.requestMicrophone() } }
                Divider()
                permission("Accessibility", detail: "Places text into the field you’re using.", ready: model.accessibility) { model.requestAccessibility() }
                Divider()
                HStack {
                    Text("Speech engine").fontWeight(.medium)
                    Spacer()
                    Picker("Speech engine", selection: Binding(get: { model.engine }, set: { model.setEngine($0) })) {
                        ForEach(Engine.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize().disabled(model.downloading)
                }
                Divider()
                if model.engine == .apple {
                    permission("English speech model", detail: "On-device · downloaded and managed by macOS.", ready: model.modelReady, button: "Download") { Task { await model.download() } }
                } else if !model.phononInstalled {
                    permission("Phonon-2 model", detail: "164 MB from Hugging Face · runs on device with MLX.", ready: false, button: "Download") { Task { await model.downloadPhonon() } }
                } else {
                    phononRow
                }
                if model.downloading {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: model.progress)
                        if !model.progressLabel.isEmpty { Text(model.progressLabel).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }.padding(18).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            HStack {
                Text("Hold to talk")
                Spacer()
                if model.shortcut != .standard && !model.recording {
                    Button("Reset") { model.resetShortcut() }.buttonStyle(.link)
                }
                Button { model.recording ? model.stopRecording() : model.startRecording() } label: {
                    Text(model.recording ? "Type shortcut…" : model.shortcut.display)
                        .font(.system(.body, design: .rounded).weight(.medium)).frame(minWidth: 110)
                        .foregroundStyle(model.recording ? Color.accentColor : .primary)
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
            if model.recording {
                Text("Press the new key combination. Esc cancels.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Start quietly at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
            Text("Hold the shortcut in a text field, speak, then release. Press Esc while the orb is showing to cancel. No recordings or history are saved. If direct insertion is unavailable, Parrot pastes through your clipboard and then restores it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.message.isEmpty { Text(model.message).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Button("Quit Parrot") { NSApp.terminate(nil) }
                Spacer()
                Text("esc to close").font(.caption).foregroundStyle(.tertiary)
                Button(model.ready ? "Done" : "Close") { NSApp.keyWindow?.close() }.keyboardShortcut(.defaultAction)
                    .background(Button("") { NSApp.keyWindow?.close() }.keyboardShortcut(.cancelAction).opacity(0))
            }
            Text("Return here from the parrot icon in the menu bar.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(28).frame(width: 510)
        .task { await model.refresh() }
        .onDisappear { if model.recording { model.stopRecording() } }
    }
    private var phononRow: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Phonon-2 model").fontWeight(.medium)
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    Text(phononDetail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer()
            switch model.phononState {
            case .unloaded: Button("Load") { model.loadPhonon() }
            case .loading: ProgressView().controlSize(.small); Button("Cancel") { model.unloadPhonon() }
            case .loaded: Button("Unload") { model.unloadPhonon() }
            }
        }
    }
    private var phononDetail: String {
        switch model.phononState {
        case .unloaded: return "Downloaded · not in memory. Loads when you dictate."
        case .loading: return "Loading into memory…"
        case .loaded:
            guard let bytes = model.phonon.footprint else { return "In memory" }
            return "In memory · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory))"
        }
    }
    private func permission(_ title: String, detail: String, ready: Bool, button: String = "Allow", action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle").foregroundStyle(ready ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) { Text(title).fontWeight(.medium); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if !ready { Button(button, action: action).disabled(model.downloading) }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private let orb = OrbPanel()
    private let hotkey = Hotkey()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var session: DictationSession?
    private let unloadItem = NSMenuItem(title: "Unload Phonon-2", action: #selector(unloadPhonon), keyEquivalent: "")
    private var target: InsertionTarget?
    private var held = false
    private var starting = false
    private var busy = false
    private var dismiss: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.hotkey = hotkey
        registerShortcut()
        installStatusItem()
        hotkey.onPress = { [weak self] in self?.begin() }
        hotkey.onRelease = { [weak self] in self?.release() }
        hotkey.onEscape = { [weak self] in self?.cancel() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        Task {
            await model.refresh()
            if model.engine == .phonon && model.phononInstalled { model.loadPhonon() }
            if !UserDefaults.standard.bool(forKey: "hasLaunched") || !model.ready { showSettings() }
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await model.refresh() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.unloadPhonon() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func registerShortcut() {
        do { try hotkey.register(model.shortcut) }
        catch { model.message = error.localizedDescription; showSettings() }
    }
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = ParrotMark.menuBarImage(listening: false)
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        unloadItem.target = self
        menu.addItem(unloadItem)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit Parrot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
    /// The first item reflects the current shortcut, engine, and setup state each time the menu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first?.title = model.ready ? "Hold \(model.shortcut.display) to dictate · \(model.engine.name)" : "Setup incomplete — open Settings"
        unloadItem.isHidden = model.phononState == .unloaded
    }
    @objc private func openSettings() { showSettings() }
    @objc private func unloadPhonon() { model.unloadPhonon() }
    private func setRecording(_ recording: Bool) {
        statusItem?.button?.image = ParrotMark.menuBarImage(listening: recording)
    }
    private func showSettings() {
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Parrot"; window.isReleasedWhenClosed = false
            let content = NSHostingView(rootView: SettingsView(model: model))
            window.contentView = content
            window.setContentSize(content.fittingSize)
            window.center(); self.window = window
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    private func begin() {
        guard !busy else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, AXIsProcessTrusted(), model.engineReady else {
            model.message = "Complete setup before using hold-to-talk."; showSettings(); return
        }
        busy = true; held = true; starting = true
        dismiss?.cancel(); target = InsertionTarget.capture()
        let warming = model.engine == .phonon && model.phononState != .loaded
        orb.model.text = ""; orb.model.level = 0
        orb.model.caption = warming ? "Loading Phonon-2 · keep talking" : "Listening · Esc to cancel"; showOrb()
        let session: DictationSession = model.engine == .phonon ? PhononSession(server: model.phonon) : SpeechSession()
        self.session = session
        session.onText = { [weak self] text in self?.orb.model.text = text }
        session.onLevel = { [weak self] level in
            guard let self else { return }
            self.orb.model.level = self.orb.model.level * 0.65 + level * 0.35
        }
        session.onFailure = { [weak self, weak session] error in
            guard let self, let session, self.session === session else { return }
            Task { await self.fail(error) }
        }
        watchdog = Task {
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, self.session === session else { return }
            held = false
            if starting { await fail(ParrotError.message("The speech engine did not start. Please try again.")) } else { finish() }
        }
        Task {
            do {
                try await session.start()
                guard self.session === session else { await session.cancel(); return }
                starting = false
                if warming && !orb.model.processing { orb.model.caption = "Listening · Esc to cancel" }
                if !held { finish() }
            } catch { if self.session === session { await fail(error) } }
        }
    }
    private func release() { held = false; if busy && !starting { finish() } }
    private func finish() {
        guard let session, !orb.model.processing else { return }
        orb.model.processing = true; orb.model.caption = "Finishing…"; orb.model.level = 0
        watchdog?.cancel()
        watchdog = Task {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, self.session === session else { return }
            await fail(ParrotError.message("Transcription timed out. Please try again."))
        }
        Task {
            do {
                let text = try await session.finish()
                guard self.session === session else { return }
                let notice = Inserter.insert(text, into: target)
                cleanup()
                if let notice { showNotice(notice) } else { hideOrb() }
            } catch { if self.session === session { await fail(error) } }
        }
    }
    private func fail(_ error: Error) async {
        let old = session
        session = nil
        watchdog?.cancel()
        await old?.cancel()
        guard session == nil else { return }
        cleanup()
        showNotice(error.localizedDescription)
    }
    private func cleanup() {
        watchdog?.cancel(); watchdog = nil; session = nil
        busy = false; held = false; starting = false; orb.model.processing = false
    }
    private func showNotice(_ message: String) {
        orb.model.caption = message; orb.model.text = ""; orb.model.level = 0; showOrb()
        dismiss?.cancel()
        dismiss = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { hideOrb() }
        }
    }
    private func showOrb() { orb.show(); hotkey.captureEscape(true); setRecording(busy) }
    private func hideOrb() { orb.hide(); hotkey.captureEscape(false); setRecording(false) }
    /// Escape, sleep: drop the session without inserting anything.
    private func cancel() {
        let old = session; cleanup(); dismiss?.cancel(); hideOrb()
        Task { await old?.cancel() }
    }
    @objc private func willSleep() { cancel() }
}

@main struct ParrotMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
