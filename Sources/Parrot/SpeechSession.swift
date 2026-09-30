import AVFoundation
import Speech
import os

let log = Logger(subsystem: "com.inqube.parrot", category: "speech")

@MainActor final class SpeechSession: DictationSession {
    private let capture = AudioCapture()
    private var analyzer: SpeechAnalyzer?
    private var feeder: Task<Void, Never>?
    private var results: Task<Void, Error>?
    private var cancelled = false
    private var transcript = Transcript()
    var onText: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onFailure: ((Error) -> Void)?

    static func transcriber() async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw ParrotError.message("Apple speech transcription is unavailable on this Mac.") }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            throw ParrotError.message("English speech transcription is unavailable.")
        }
        return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
    }

    /// Capture starts before the analyzer is ready; buffered audio is fed once it is, so the first words are kept.
    func start() async throws {
        let (buffers, native) = try capture.start(level: onLevel, failure: onFailure)

        let transcriber = try await Self.transcriber()
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw ParrotError.message("Open Parrot to download the speech model first.")
        }
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")),
           !(await AssetInventory.reservedLocales).contains(locale) {
            _ = try? await AssetInventory.reserve(locale: locale)
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: native),
              let converter = AVAudioConverter(from: native, to: format) else {
            throw ParrotError.message("No usable microphone audio format is available.")
        }
        guard !cancelled else { return }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: format)
        let (input, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        results = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    self.transcript.receive(String(result.text.characters), final: result.isFinal)
                    self.onText?(self.transcript.text)
                }
            } catch { self?.onFailure?(error); throw error }
        }
        try await analyzer.start(inputSequence: input)
        let failure = onFailure
        feeder = Task.detached {
            for await buffer in buffers {
                do { if let output = try AudioCapture.convert(buffer, with: converter) { inputContinuation.yield(AnalyzerInput(buffer: output)) } }
                catch { await MainActor.run { failure?(error) }; break }
            }
            inputContinuation.finish()
        }
        log.info("Analyzer ready: \(format, privacy: .public)")
    }

    func finish() async throws -> String {
        stopAudio()
        await feeder?.value
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        try await results?.value
        return transcript.committed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func cancel() async {
        cancelled = true
        stopAudio(); feeder?.cancel(); results?.cancel()
        await analyzer?.cancelAndFinishNow()
    }
    private func stopAudio() { capture.stop() }
}
