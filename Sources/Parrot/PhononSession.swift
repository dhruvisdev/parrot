import AVFoundation

/// Streams the microphone to the Phonon-2 server's WebSocket: 16 kHz mono Float32 in, partial and final phrases out.
@MainActor final class PhononSession: DictationSession {
    private let server: PhononServer
    private let capture = AudioCapture()
    private var socket: URLSessionWebSocketTask?
    private var feeder: Task<Void, Never>?
    private var receiver: Task<Void, Never>?
    private var done: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    private var cancelled = false
    private var transcript = PhraseTranscript()
    var onText: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onFailure: ((Error) -> Void)?

    init(server: PhononServer) { self.server = server }

    /// Capture starts before the server is loaded; buffered audio is sent once it is, so the first words are kept.
    func start() async throws {
        let (buffers, native) = try capture.start(level: onLevel, failure: onFailure)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: native, to: format) else {
            throw ParrotError.message("No usable microphone audio format is available.")
        }
        let endpoint: PhononServer.Endpoint
        do { endpoint = try await server.load() }
        catch is CancellationError { throw ParrotError.message("Phonon-2 was unloaded.") }
        guard !cancelled else { return }
        var request = URLRequest(url: endpoint.stream)
        request.setValue("Bearer \(endpoint.key)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        try await socket.send(.string(#"{"sample_rate": 16000, "format": "pcm_f32le"}"#))
        receiver = Task { [weak self] in await self?.receive(from: socket) }
        let failure = onFailure
        feeder = Task.detached {
            for await buffer in buffers {
                do {
                    guard let output = try AudioCapture.convert(buffer, with: converter), let samples = output.floatChannelData?[0] else { continue }
                    try await socket.send(.data(Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Float>.size)))
                } catch { await MainActor.run { failure?(error) }; break }
            }
        }
        log.info("Phonon-2 stream open")
    }

    func finish() async throws -> String {
        capture.stop()
        await feeder?.value
        guard let socket else { throw ParrotError.message("Phonon-2 did not start. Please try again.") }
        try await socket.send(.string(#"{"type": "end"}"#))
        let text = try await withCheckedThrowingContinuation { continuation in
            if let result { continuation.resume(with: result) } else { done = continuation }
        }
        socket.cancel(with: .normalClosure, reason: nil)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func cancel() async {
        cancelled = true
        capture.stop(); feeder?.cancel(); receiver?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        complete(.failure(CancellationError()))
    }

    private func receive(from socket: URLSessionWebSocketTask) async {
        do {
            while true {
                let data: Data
                switch try await socket.receive() {
                case .string(let text): data = Data(text.utf8)
                case .data(let bytes): data = bytes
                @unknown default: continue
                }
                guard let event = PhononEvent(json: data) else { continue }
                switch event {
                case .done(let text): complete(.success(text)); return
                case .error(let message): throw ParrotError.message("Phonon-2: \(message)")
                default: transcript.receive(event); onText?(transcript.text)
                }
            }
        } catch {
            guard !cancelled else { return }
            complete(.failure(error)); onFailure?(error)
        }
    }
    private func complete(_ outcome: Result<String, Error>) {
        if let done { self.done = nil; done.resume(with: outcome) }
        else if result == nil { result = outcome }
    }
}

enum PhononEvent: Equatable {
    case partial(String), final(String), done(String), error(String)
    init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any], let type = object["type"] as? String else { return nil }
        let text = object["text"] as? String ?? ""
        switch type {
        case "partial": self = .partial(text)
        case "final": self = .final(text)
        case "done": self = .done(text)
        case "error": self = .error(object["message"] as? String ?? "Unknown error.")
        default: return nil
        }
    }
}

/// Each partial is the whole phrase in flight, replacing the last; finals close phrases, joined by single spaces as the server's own transcript is.
struct PhraseTranscript {
    private(set) var phrases: [String] = []
    private(set) var partial = ""
    var text: String { (partial.isEmpty ? phrases : phrases + [partial]).joined(separator: " ") }
    mutating func receive(_ event: PhononEvent) {
        switch event {
        case .partial(let text): partial = text
        case .final(let text): if !text.isEmpty { phrases.append(text) }; partial = ""
        default: break
        }
    }
}
