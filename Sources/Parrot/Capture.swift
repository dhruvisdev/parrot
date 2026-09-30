import AVFoundation

/// What the app delegate drives during a hold-to-talk: one per dictation, whichever engine is selected.
@MainActor protocol DictationSession: AnyObject {
    var onText: ((String) -> Void)? { get set }
    var onLevel: ((Float) -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }
    func start() async throws
    func finish() async throws -> String
    func cancel() async
}

/// Microphone capture shared by both engines. Buffers queue from the first moment, so words spoken while an engine gets ready are kept.
@MainActor final class AudioCapture {
    private let engine = AVAudioEngine()
    private var audio: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var deviceObserver: NSObjectProtocol?
    private var tapped = false

    func start(level: ((Float) -> Void)?, failure: ((Error) -> Void)?) throws -> (buffers: AsyncStream<AVAudioPCMBuffer>, format: AVAudioFormat) {
        let native = engine.inputNode.outputFormat(forBus: 0)
        guard native.sampleRate > 0, native.channelCount > 0 else { throw ParrotError.message("No microphone is available.") }
        let (buffers, audio) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.audio = audio
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: native, block: Self.tap(into: audio, level: level))
        tapped = true
        deviceObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            MainActor.assumeIsolated { failure?(ParrotError.message("Microphone changed. Please try again.")) }
        }
        engine.prepare()
        try engine.start()
        log.info("Capture started: \(native, privacy: .public)")
        return (buffers, native)
    }
    func stop() {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        audio?.finish()
        if let deviceObserver { NotificationCenter.default.removeObserver(deviceObserver); self.deviceObserver = nil }
    }

    /// Built outside the main actor: the tap runs on a realtime audio thread.
    nonisolated private static func tap(into audio: AsyncStream<AVAudioPCMBuffer>.Continuation, level: ((Float) -> Void)?) -> AVAudioNodeTapBlock {
        { buffer, _ in
            if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                var sum: Float = 0
                for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
                let rms = sqrt(sum / Float(buffer.frameLength))
                Task { @MainActor in level?(min(1, rms * 9)) }
            }
            audio.yield(buffer)
        }
    }
    nonisolated static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) throws -> AVAudioPCMBuffer? {
        let format = converter.outputFormat
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true; inputStatus.pointee = .haveData; return buffer
        }
        if status == .error || error != nil { throw error ?? ParrotError.message("Audio conversion failed.") }
        return output.frameLength > 0 ? output : nil
    }
}
