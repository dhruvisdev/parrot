import Foundation
import Darwin

/// Phonon-2 ships in Fermion Research's packed format, which only their Python/MLX engine can load. Parrot keeps a private
/// runtime for that engine, fetches the model with the `hf` CLI into the standard Hugging Face cache, and runs `fermion serve`
/// as a child process for as long as the model should stay in memory.
enum Phonon {
    static let repo = "FermionResearch/Phonon-2"
    static let archive = "phonon-2.bps.tar.zst"
    static let downloadBytes = 163_515_201.0
    /// Fermion declares torch for its CPU engine; on Apple silicon the MLX engine needs only these, which saves about a gigabyte.
    static let packages = ["numpy", "huggingface_hub", "mlx", "mlx-audio", "mlx-lm", "soundfile", "scipy", "zstandard"]

    static var hubCache: URL {
        let env = ProcessInfo.processInfo.environment
        if let hub = env["HF_HUB_CACHE"] { return URL(fileURLWithPath: hub) }
        if let home = env["HF_HOME"] { return URL(fileURLWithPath: home).appending(path: "hub") }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cache/huggingface/hub")
    }
    static var repoCache: URL { hubCache.appending(path: "models--" + repo.replacingOccurrences(of: "/", with: "--")) }
    static var runtime: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Parrot/Phonon runtime")
    }
    static var python: URL { runtime.appending(path: "bin/python") }
    private static var runtimeMarker: URL { runtime.appending(path: ".parrot-ready") }

    static var runtimeReady: Bool { FileManager.default.fileExists(atPath: runtimeMarker.path) }
    /// `hf download` renames a blob into place and links it only once it is complete, so a resolvable archive means a whole one.
    static var downloaded: Bool {
        guard let revision = try? String(contentsOf: repoCache.appending(path: "refs/main"), encoding: .utf8) else { return false }
        let snapshot = repoCache.appending(path: "snapshots").appending(path: revision.trimmingCharacters(in: .whitespacesAndNewlines))
        return FileManager.default.fileExists(atPath: snapshot.appending(path: archive).path)
    }
    static var installed: Bool { runtimeReady && downloaded }

    /// Sets up the runtime if needed, then downloads the model. Progress is nil while it cannot be measured.
    @MainActor static func install(progress: @escaping (String, Double?) -> Void) async throws {
        if !runtimeReady {
            progress("Setting up the Phonon runtime (about 450 MB)…", nil)
            try await installRuntime()
        }
        guard !downloaded else { return }
        progress("Downloading Phonon-2…", 0)
        let monitor = Task { @MainActor in
            while !Task.isCancelled {
                progress("Downloading Phonon-2…", min(1, downloadedBytes() / downloadBytes))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { monitor.cancel() }
        let (hf, prefix) = find("hf").map { ($0, [String]()) } ?? (python, ["-m", "huggingface_hub.cli.hf"])
        try await run(hf, prefix + ["download", repo])
        guard downloaded else { throw ParrotError.message("The download finished without the Phonon-2 model archive.") }
    }

    private static func installRuntime() async throws {
        let files = FileManager.default
        try? files.removeItem(at: runtime)
        try files.createDirectory(at: runtime.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let uv = find("uv") {
            try await run(uv, ["venv", "--python", "3.12", runtime.path])
            try await run(uv, ["pip", "install", "--python", python.path, "--no-deps", "fermion-research"])
            try await run(uv, ["pip", "install", "--python", python.path] + packages)
        } else if let python3 = await systemPython() {
            try await run(python3, ["-m", "venv", runtime.path])
            try await run(python, ["-m", "pip", "install", "--no-deps", "fermion-research"])
            try await run(python, ["-m", "pip", "install"] + packages)
        } else {
            throw ParrotError.message("Phonon-2 needs uv or Python 3.10 or later. Install one (for example, `brew install uv`) and try again.")
        }
        files.createFile(atPath: runtimeMarker.path, contents: nil)
    }

    private static func downloadedBytes() -> Double {
        let blobs = repoCache.appending(path: "blobs")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: blobs.path)) ?? []
        return names.reduce(0) { total, name in
            let size = (try? FileManager.default.attributesOfItem(atPath: blobs.appending(path: name).path)[.size] as? NSNumber)?.doubleValue
            return total + (size ?? 0)
        }
    }

    // MARK: Tools

    /// Apps launched from Finder get a minimal PATH, so the usual install locations are searched too.
    private static var searchPath: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.cargo/bin"] + inherited
    }
    private static func find(_ tool: String) -> URL? {
        searchPath.map { URL(fileURLWithPath: $0).appending(path: tool) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    private static func systemPython() async -> URL? {
        for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let candidate = URL(fileURLWithPath: directory).appending(path: "python3")
            guard FileManager.default.isExecutableFile(atPath: candidate.path) else { continue }
            if (try? await run(candidate, ["-c", "import sys; sys.exit(sys.version_info < (3, 10))"])) != nil { return candidate }
        }
        return nil
    }
    static func environment(_ extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath.joined(separator: ":")
        env["HF_HUB_CACHE"] = hubCache.path
        env["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        return env.merging(extra) { $1 }
    }
    private static func run(_ tool: URL, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.environment = environment()
        let output = OutputTail()
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { output.append($0.availableData) }
        log.info("Running \(tool.lastPathComponent, privacy: .public) \(arguments.joined(separator: " "), privacy: .public)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        guard process.terminationStatus == 0 else {
            throw ParrotError.message("\(tool.lastPathComponent) \(arguments.first ?? "") failed: \(output.summary)")
        }
    }
}

/// The last few kilobytes a child process printed, for error messages.
final class OutputTail: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) {
        lock.withLock { data.append(chunk); if data.count > 4096 { data.removeFirst(data.count - 4096) } }
    }
    func reset() { lock.withLock { data.removeAll() } }
    var summary: String {
        let text = lock.withLock { String(decoding: data, as: UTF8.self) }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.suffix(3).joined(separator: " ")
    }
}

/// A `fermion serve` process holding Phonon-2 in memory. Unloading ends the process, which returns all of its memory.
@MainActor final class PhononServer {
    enum State { case unloaded, loading, loaded }
    struct Endpoint { let stream: URL; let key: String }

    private(set) var state = State.unloaded { didSet { onChange?() } }
    var onChange: (() -> Void)?
    private var process: Process?
    private var lifeline: Pipe?
    private var endpoint: Endpoint?
    private var loading: Task<Endpoint, Error>?
    private let output = OutputTail()

    /// Runs Fermion's CLI and exits when stdin closes, so the server never outlives Parrot, even after a crash.
    private static let launcher = """
    import os, sys, threading
    threading.Thread(target=lambda: (sys.stdin.buffer.read(), os._exit(0)), daemon=True).start()
    from fermion.cli import main
    sys.argv = ["fermion"] + sys.argv[1:]
    sys.exit(main())
    """

    /// Starts the server if needed and waits until the model is in memory. Concurrent callers share one launch.
    func load() async throws -> Endpoint {
        if let endpoint, process?.isRunning == true { return endpoint }
        if let loading { return try await loading.value }
        let launch = Task { try await self.launch() }
        loading = launch
        defer { if loading == launch { loading = nil } }
        return try await launch.value
    }

    func unload() {
        loading?.cancel(); loading = nil
        guard let process else { state = .unloaded; return }
        self.process = nil; endpoint = nil
        try? lifeline?.fileHandleForWriting.close(); lifeline = nil
        process.terminate()
        let pid = process.processIdentifier
        Task.detached {
            try? await Task.sleep(for: .seconds(3))
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
        state = .unloaded
        log.info("Phonon-2 unloaded")
    }

    /// Physical memory the server holds, including the GPU buffers MLX allocates on its behalf.
    var footprint: UInt64? {
        guard state == .loaded, let pid = process?.processIdentifier else { return nil }
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    private func launch() async throws -> Endpoint {
        guard Phonon.installed else { throw ParrotError.message("Download Phonon-2 in Settings first.") }
        state = .loading
        let port = try Self.freePort()
        let key = UUID().uuidString
        let process = Process()
        process.executableURL = Phonon.python
        process.arguments = ["-c", Self.launcher, "serve", "--model", Phonon.repo, "--host", "127.0.0.1", "--port", String(port), "--api-key", key]
        // Offline: the model is read from the Hugging Face cache and never re-fetched.
        process.environment = Phonon.environment(["HF_HUB_OFFLINE": "1", "PYTHONUNBUFFERED": "1"])
        let lifeline = Pipe(), pipe = Pipe()
        process.standardInput = lifeline
        process.standardOutput = pipe; process.standardError = pipe
        output.reset()
        pipe.fileHandleForReading.readabilityHandler = { [output] in output.append($0.availableData) }
        process.terminationHandler = { [weak self] ended in
            Task { @MainActor in self?.exited(ended) }
        }
        try process.run()
        self.process = process; self.lifeline = lifeline
        log.info("Phonon-2 server starting on port \(port)")

        do {
            let health = URL(string: "http://127.0.0.1:\(port)/health")!
            let deadline = ContinuousClock.now + .seconds(180)
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                guard self.process === process else { throw CancellationError() }
                guard process.isRunning else { throw ParrotError.message("Phonon-2 stopped while loading: \(output.summary)") }
                if let (_, response) = try? await URLSession.shared.data(from: health), (response as? HTTPURLResponse)?.statusCode == 200 {
                    let endpoint = Endpoint(stream: URL(string: "ws://127.0.0.1:\(port)/v1/audio/stream")!, key: key)
                    self.endpoint = endpoint; state = .loaded
                    log.info("Phonon-2 loaded")
                    return endpoint
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            throw ParrotError.message("Phonon-2 took too long to load.")
        } catch {
            if self.process === process { unload() }
            throw error
        }
    }

    private func exited(_ ended: Process) {
        guard process === ended else { return }
        log.error("Phonon-2 server exited: \(self.output.summary, privacy: .public)")
        process = nil; endpoint = nil; lifeline = nil
        state = .unloaded
    }

    private static func freePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ParrotError.message("Could not reserve a local port for Phonon-2.") }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) == 0 && getsockname(fd, $0, &length) == 0 }
        }
        guard bound else { throw ParrotError.message("Could not reserve a local port for Phonon-2.") }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}
