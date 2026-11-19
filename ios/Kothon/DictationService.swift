// The dictation session. It keeps the microphone open in the background (the
// "audio" background mode), so the keyboard can start and stop recording
// without bringing the app forward each time. Samples are only kept while
// recording; otherwise they're dropped as they arrive.
//
// A session ends by itself after `idleTimeout` without dictation, which
// turns the microphone off and lets iOS suspend the app.

import AVFoundation
import Foundation
import UIKit

@MainActor
final class DictationService: ObservableObject {
    static let shared = DictationService()

    @Published private(set) var phase: DictationPhase = .off
    @Published private(set) var lastResult = ""
    @Published private(set) var lastError: String?
    @Published private(set) var level: Float = 0
    @Published private(set) var lastDuration: TimeInterval = 0
    /// "৮.২ সে. কথা → ১.৪ সে.-এ লেখা (CPU)", to see how fast each model is.
    @Published private(set) var lastStats = ""

    /// How long an unused session stays open. Wispr Flow uses 5 minutes too.
    var idleTimeout: TimeInterval = 5 * 60
    /// Recordings stop on their own after this long.
    let maxRecording: TimeInterval = 5 * 60

    private let audioEngine = AVAudioEngine()
    private let sampleRate: Double = 16_000
    private let buffer = SampleBuffer()
    private var heartbeat: Timer?
    private var lastActivity = Date()
    private var recordingStarted = Date()
    private var levelPosted = Date.distantPast

    private var engine: Transcriber?
    private var engineModelID: String?
    private let engineQueue = DispatchQueue(label: "com.kothon.engine", qos: .userInitiated)

    private let shared = KothonShared.defaults

    private init() {
        shared.dictationPhase = .off
        DarwinCenter.shared.observe(.start) { [weak self] in self?.startRecording() }
        DarwinCenter.shared.observe(.stop) { [weak self] in self?.stopRecording() }
        DarwinCenter.shared.observe(.cancel) { [weak self] in self?.cancelRecording() }
        // Background apps can't use the GPU: swap to the CPU copy of the
        // model as the app leaves the screen, while a session keeps it alive.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.prepareForBackground() }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
    }

    // MARK: Session

    /// Open the microphone and keep it open in the background.
    func startSession() throws {
        lastActivity = Date()
        guard phase == .off else { return }
        let session = AVAudioSession.sharedInstance()
        // mixWithOthers: music and videos keep playing while a session is open.
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
        try session.setActive(true)

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false)
        else { throw EngineError(message: "মাইক্রোফোন পাওয়া যায়নি") }
        guard let resampler = Resampler(from: format, to: target) else {
            throw EngineError(message: "মাইক্রোফোনের ফরম্যাট সাপোর্ট করে না")
        }
        let buffer = self.buffer
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] pcm, _ in
            // Runs on the audio thread. The buffer is reused once this returns,
            // so convert it here, synchronously.
            let level = Resampler.level(pcm)
            if buffer.isRecording { resampler.convert(pcm) { buffer.append($0) } }
            Task { @MainActor in self?.updateLevel(level) }
        }
        audioEngine.prepare()
        try audioEngine.start()

        setPhase(.ready)
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
        preloadEngine()
    }

    func endSession() {
        heartbeat?.invalidate()
        heartbeat = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        buffer.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        setPhase(.off)
    }

    private func tick() {
        shared.set(Date().timeIntervalSince1970, forKey: SharedKey.heartbeat)
        if phase == .ready, Date().timeIntervalSince(lastActivity) > idleTimeout {
            endSession()
        }
        if phase == .recording, Date().timeIntervalSince(recordingStarted) > maxRecording {
            stopRecording()
        }
    }

    // MARK: Recording

    func startRecording() {
        lastActivity = Date()
        if phase == .off {
            do { try startSession() } catch {
                fail(error.localizedDescription)
                return
            }
        }
        guard phase == .ready else { return }
        buffer.start()
        recordingStarted = Date()
        lastError = nil
        shared.removeObject(forKey: SharedKey.errorText)
        setPhase(.recording)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func stopRecording() {
        guard phase == .recording else { return }
        lastActivity = Date()
        let samples = buffer.stop()
        lastDuration = Double(samples.count) / sampleRate
        setPhase(.transcribing)
        var settings = DictationSettings.current
        settings.cpuOnly = UIApplication.shared.applicationState != .active
        let modelID = ModelStore.shared.selectedID

        Task {
            do {
                let started = Date()
                let engine = try await loadEngine(modelID: modelID)
                let text = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                    engineQueue.async {
                        cont.resume(with: Result { try engine.transcribe(samples, settings: settings) })
                    }
                }
                lastStats = Self.stats(audio: lastDuration, took: Date().timeIntervalSince(started),
                                       cpu: settings.cpuOnly)
                deliver(text)
            } catch {
                fail(error.localizedDescription)
            }
            if phase == .transcribing { setPhase(.ready) }
        }
    }

    func cancelRecording() {
        guard phase == .recording else { return }
        buffer.stop()
        setPhase(.ready)
    }

    private static func stats(audio: TimeInterval, took: TimeInterval, cpu: Bool) -> String {
        func bn(_ x: Double) -> String {
            let f = NumberFormatter()
            f.locale = Locale(identifier: "bn-BD")
            f.maximumFractionDigits = 1
            f.minimumFractionDigits = 1
            return f.string(from: NSNumber(value: x)) ?? String(format: "%.1f", x)
        }
        return "\(bn(audio)) সে. কথা → \(bn(took)) সে.-এ লেখা (\(cpu ? "CPU" : "GPU"))"
    }

    private func deliver(_ text: String) {
        lastResult = text
        shared.set(text, forKey: SharedKey.resultText)
        shared.set(lastStats, forKey: SharedKey.stats)
        shared.set(shared.integer(forKey: SharedKey.resultID) + 1, forKey: SharedKey.resultID)
        DarwinCenter.shared.post(.changed)
    }

    private func fail(_ detail: String) {
        let message = detail.hasPrefix("আগে") ? detail : "লিখতে পারিনি (\(detail))"
        lastError = message
        shared.set(message, forKey: SharedKey.errorText)
        if phase == .recording || phase == .transcribing { setPhase(audioEngine.isRunning ? .ready : .off) }
        DarwinCenter.shared.post(.changed)
    }

    private func setPhase(_ p: DictationPhase) {
        phase = p
        shared.dictationPhase = p
        shared.set(Date().timeIntervalSince1970, forKey: SharedKey.heartbeat)
        DarwinCenter.shared.post(.changed)
    }

    // MARK: Engine

    /// Load the model as the session opens, so the first dictation doesn't wait.
    private func preloadEngine() {
        let id = ModelStore.shared.selectedID
        Task { _ = try? await loadEngine(modelID: id) }
    }

    private func loadEngine(modelID: String) async throws -> Transcriber {
        if let engine, engineModelID == modelID { return engine }
        let store = ModelStore.shared
        guard let model = SpeechModel.all.first(where: { $0.id == modelID }), store.isInstalled(model) else {
            throw EngineError(message: "আগে কথন অ্যাপে মডেল ডাউনলোড করুন")
        }
        let modelURL = store.file(for: model)
        let punct = store.punctuationInstalled ? store.punctuationDir : nil
        let cpuOnly = UIApplication.shared.applicationState != .active
        let loaded = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<OnDeviceEngine, Error>) in
            engineQueue.async {
                cont.resume(with: Result { try OnDeviceEngine(model: model, modelURL: modelURL, punctuationDir: punct, cpuOnly: cpuOnly) })
            }
        }
        engine = loaded
        engineModelID = modelID
        return loaded
    }

    private func prepareForBackground() {
        guard phase != .off, let engine else { return }
        engineQueue.async { engine.prepareForBackground() }
    }

    /// Drop the loaded model, e.g. after switching models or on a memory warning.
    func unloadEngine() {
        guard phase != .transcribing else { return }
        engine = nil
        engineModelID = nil
    }

    // MARK: Levels

    private func updateLevel(_ value: Float) {
        level = value
        // The keyboard redraws its meter from this; ~12 updates a second is plenty.
        if phase == .recording, Date().timeIntervalSince(levelPosted) > 0.08 {
            levelPosted = Date()
            shared.set(value, forKey: SharedKey.level)
            DarwinCenter.shared.post(.changed)
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            // A phone call or Siri took the microphone.
            if phase == .recording { stopRecording() }
        case .ended:
            if phase != .off { try? audioEngine.start() }
        @unknown default:
            break
        }
    }
}

/// Converts the microphone's format (often 48 kHz) to 16 kHz mono.
final class Resampler: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let target: AVAudioFormat

    init?(from: AVAudioFormat, to: AVAudioFormat) {
        guard let c = AVAudioConverter(from: from, to: to) else { return nil }
        converter = c
        target = to
    }

    func convert(_ pcm: AVAudioPCMBuffer, into sink: (UnsafeBufferPointer<Float>) -> Void) {
        let ratio = target.sampleRate / pcm.format.sampleRate
        let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return pcm
        }
        if error == nil, let data = out.floatChannelData?[0] {
            sink(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
        }
    }

    /// Rough loudness 0...1 for the meters.
    static func level(_ pcm: AVAudioPCMBuffer) -> Float {
        guard let ch = pcm.floatChannelData?[0], pcm.frameLength > 0 else { return 0 }
        let n = Int(pcm.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        return min(1, sqrt(sum / Float(n)) * 12)
    }
}

/// 16 kHz samples collected while recording.
final class SampleBuffer: @unchecked Sendable {
    private var samples: [Float] = []
    private var recording = false
    private let lock = NSLock()

    var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return recording
    }

    func start() {
        lock.lock(); defer { lock.unlock() }
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(16_000 * 30)
        recording = true
    }

    func append(_ chunk: UnsafeBufferPointer<Float>) {
        lock.lock(); defer { lock.unlock() }
        if recording { samples.append(contentsOf: chunk) }
    }

    @discardableResult
    func stop() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        recording = false
        let out = samples
        samples = []
        return out
    }
}
