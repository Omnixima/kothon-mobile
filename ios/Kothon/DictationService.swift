// The dictation session. It keeps the microphone open in the background (the
// "audio" background mode), so the keyboard can start and stop recording
// without bringing the app forward each time. Samples are only kept while
// recording; otherwise they're dropped as they arrive.
//
// A session ends by itself after `idleTimeout` without dictation, which
// turns the microphone off and lets iOS suspend the app.

import AVFoundation
import BackgroundTasks
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
    @Published private(set) var benchmarking = false
    @Published private(set) var benchmarkResult = ""
    /// Whether the selected model is in memory, shown on the home screen.
    @Published private(set) var engineStatus: EngineStatus = .notLoaded
    /// The current load is the first one after an app update: iOS compiles a
    /// Core ML model for the Neural Engine once per app build (~2 minutes).
    @Published private(set) var preparingAfterUpdate = false
    private var lastSamples: [Float] = []

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

        lastSamples = samples

        Task {
            do {
                let loadStart = Date()
                let engine = try await loadEngine(modelID: modelID)
                let loadTime = Date().timeIntervalSince(loadStart)
                let runStart = Date()
                guard let speech = await gateSpeech(samples) else {
                    // Nothing was said: type nothing.
                    lastStats = ""
                    shared.set("কিছু শোনা যায়নি", forKey: SharedKey.errorText)
                    DarwinCenter.shared.post(.changed)
                    if phase == .transcribing { setPhase(.ready) }
                    return
                }
                let text = try await run(engine, speech, settings)
                lastStats = Self.stats(audio: lastDuration, took: Date().timeIntervalSince(runStart),
                                       load: loadTime, chip: engine is NeuralEngineEngine ? "Neural Engine" : settings.cpuOnly ? "CPU" : "GPU")
                deliver(text)
            } catch {
                fail(error.localizedDescription)
            }
            if phase == .transcribing { setPhase(.ready) }
        }
    }

    private func run(_ engine: Transcriber, _ samples: [Float], _ settings: DictationSettings) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            engineQueue.async {
                cont.resume(with: Result { try engine.transcribe(samples, settings: settings) })
            }
        }
    }

    /// Re-run the last recording a few times on the GPU and on the CPU, to
    /// measure the selected model without first-run costs. App must be open.
    func benchmark() async {
        guard !lastSamples.isEmpty, phase != .recording, phase != .transcribing else { return }
        benchmarking = true
        defer { benchmarking = false }
        do {
            let engine = try await loadEngine(modelID: ModelStore.shared.selectedID)
            var results: [String] = []
            func time(_ settings: DictationSettings, runs: Int) async throws -> Double {
                _ = try await run(engine, lastSamples, settings) // warm-up
                var best = Double.infinity
                for _ in 0..<runs {
                    let t = Date()
                    _ = try await run(engine, lastSamples, settings)
                    best = min(best, Date().timeIntervalSince(t))
                }
                return best
            }
            var settings = DictationSettings.current
            if engine is NeuralEngineEngine {
                results.append("Neural Engine \(Self.bn(try await time(settings, runs: 3)))")
                results.append(NeuralEngineEngine.lastBreakdown)
                benchmarkResult = "\(ModelStore.shared.selected.label), \(Self.bn(lastDuration)) সে. কথা → সময় (সে.): " + results.joined(separator: " · ")
                return
            }
            settings.cpuOnly = false
            results.append("GPU \(Self.bn(try await time(settings, runs: 2)))")

            // CPU setups worth comparing on phones: Accelerate or plain ggml,
            // and all cores or only the performance cores.
            settings.cpuOnly = true
            if let device = engine as? OnDeviceEngine {
                var best: (threads: Int32, accel: Bool, time: Double)?
                for (threads, accel) in [(Int32(0), true), (0, false), (2, false), (4, false)] {
                    await onEngineQueue { device.setCPU(threads: threads, accel: accel) }
                    let t = try await time(settings, runs: 1)
                    results.append("CPU\(threads == 0 ? "" : "×\(threads)")\(accel ? "+BLAS" : "") \(Self.bn(t))")
                    if t < (best?.time ?? .infinity) { best = (threads, accel, t) }
                }
                // Keep the fastest setup for the keyboard's background runs.
                if let best {
                    UserDefaults.standard.set(Int(best.threads), forKey: "cpuThreads")
                    UserDefaults.standard.set(best.accel, forKey: "cpuAccel")
                    await onEngineQueue { device.setCPU(threads: best.threads, accel: best.accel) }
                }
            }
            results.append("পেছনে GPU: \(Self.backgroundGPUSupported ? "হ্যাঁ" : "না")")
            benchmarkResult = "\(ModelStore.shared.selected.label), \(Self.bn(lastDuration)) সে. কথা → সময় (সে.): " + results.joined(separator: " · ")
        } catch {
            benchmarkResult = "মাপা যায়নি: \(error.localizedDescription)"
        }
    }

    private let gate = SpeechGate()

    private func gateSpeech(_ samples: [Float]) async -> [Float]? {
        await withCheckedContinuation { cont in
            engineQueue.async { [gate] in cont.resume(returning: gate.speech(in: samples)) }
        }
    }

    private func onEngineQueue(_ work: @escaping () -> Void) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            engineQueue.async { work(); cont.resume() }
        }
    }

    /// iOS 26 can grant GPU time to background work on some devices.
    static var backgroundGPUSupported: Bool {
        if #available(iOS 26.0, *) {
            return BGTaskScheduler.supportedResources.contains(.gpu)
        }
        return false
    }

    func cancelRecording() {
        guard phase == .recording else { return }
        buffer.stop()
        setPhase(.ready)
    }

    /// Bengali digits, one decimal: 4.7 → ৪.৭
    static func bn(_ x: Double, digits places: Int = 1) -> String {
        let digits = Array("০১২৩৪৫৬৭৮৯")
        return String(format: "%.\(places)f", x).map { c in
            c.wholeNumberValue.map { String(digits[$0]) } ?? String(c)
        }.joined()
    }

    /// Hidden developer mode (tap the version line 5 times): the speed test,
    /// chip names and load times.
    static var developerMode: Bool { UserDefaults.standard.bool(forKey: "developerMode") }

    private static func stats(audio: TimeInterval, took: TimeInterval, load: TimeInterval, chip: String) -> String {
        var s = "\(bn(audio)) সে. কথা → \(bn(took)) সে.-এ লেখা"
        guard developerMode else { return s }
        s += " (\(chip))"
        if load > 0.2 { s += ", মডেল লোড \(bn(load)) সে." }
        return s
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
    /// Also the home screen's "লোড করুন".
    func preloadEngine() {
        let id = ModelStore.shared.selectedID
        Task { _ = try? await loadEngine(modelID: id) }
    }

    /// This build, e.g. "0.1.0 (2)". iOS's compiled-model cache is per build.
    static var buildID: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
    private static let preparedBuildKey = "coreml.preparedBuild"

    /// On launch and when the app comes forward: load a Core ML model right
    /// away, so the one-time Neural Engine compile after an update happens
    /// while the app is open, not on the first dictation. It runs as a
    /// background task, so a quick app switch doesn't cut it off; if it is
    /// cut off, the next launch tries again.
    func prepareEngineIfNeeded() {
        let store = ModelStore.shared
        let model = store.selected
        guard model.isCoreML, store.isInstalled(model), engine == nil, loading == nil else { return }
        let firstAfterUpdate = UserDefaults.standard.string(forKey: Self.preparedBuildKey) != Self.buildID
        preparingAfterUpdate = firstAfterUpdate
        shared.set(firstAfterUpdate, forKey: SharedKey.modelPreparing)

        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "prepare-model") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        Task {
            if (try? await loadEngine(modelID: model.id)) != nil {
                UserDefaults.standard.set(Self.buildID, forKey: Self.preparedBuildKey)
            }
            preparingAfterUpdate = false
            shared.set(false, forKey: SharedKey.modelPreparing)
            DarwinCenter.shared.post(.changed)
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
    }

    /// A load in progress, so a dictation that starts while the session is
    /// still preloading waits for that load instead of starting another.
    private var loading: (id: String, task: Task<Transcriber, Error>)?

    private func loadEngine(modelID: String) async throws -> Transcriber {
        if let engine, engineModelID == modelID { return engine }
        if let loading, loading.id == modelID { return try await loading.task.value }
        let task = Task { try await self.load(modelID: modelID) }
        loading = (modelID, task)
        let started = Date()
        setEngineStatus(.loading(since: started))
        defer { if loading?.id == modelID { loading = nil } }
        do {
            let loaded = try await task.value
            if engineModelID == modelID {
                setEngineStatus(.ready(loadSeconds: Date().timeIntervalSince(started)))
            }
            return loaded
        } catch {
            if loading?.id == modelID { setEngineStatus(.failed(error.localizedDescription)) }
            throw error
        }
    }

    /// The keyboard shows "মডেল লোড হচ্ছে…" from the shared flag.
    private func setEngineStatus(_ status: EngineStatus) {
        engineStatus = status
        if case .loading = status {
            shared.set(true, forKey: SharedKey.modelLoading)
        } else {
            shared.set(false, forKey: SharedKey.modelLoading)
        }
        DarwinCenter.shared.post(.changed)
    }

    private func load(modelID: String) async throws -> Transcriber {
        let store = ModelStore.shared
        guard let model = SpeechModel.all.first(where: { $0.id == modelID }), store.isInstalled(model) else {
            throw EngineError(message: "আগে কথন অ্যাপে মডেল ডাউনলোড করুন")
        }
        if model.isCoreML {
            guard let folder = store.coreMLFolder(for: model) else {
                throw EngineError(message: "আগে কথন অ্যাপে মডেল ডাউনলোড করুন")
            }
            let loaded = try await NeuralEngineEngine(model: model, folder: folder)
            _ = try? await run(loaded, [Float](repeating: 0, count: 16_000), DictationSettings())
            engine = loaded
            engineModelID = modelID
            return loaded
        }
        let modelURL = store.file(for: model)
        let punct = store.punctuationInstalled ? store.punctuationDir : nil
        let cpuOnly = UIApplication.shared.applicationState != .active
        let loaded = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<OnDeviceEngine, Error>) in
            engineQueue.async {
                cont.resume(with: Result { try OnDeviceEngine(model: model, modelURL: modelURL, punctuationDir: punct, cpuOnly: cpuOnly) })
            }
        }
        if UserDefaults.standard.object(forKey: "cpuThreads") != nil {
            let threads = Int32(UserDefaults.standard.integer(forKey: "cpuThreads"))
            let accel = UserDefaults.standard.bool(forKey: "cpuAccel")
            await onEngineQueue { loaded.setCPU(threads: threads, accel: accel) }
        }
        // The first run compiles the GPU kernels and pages the weights in;
        // do it now, on a moment of silence, not on the user's dictation.
        var warm = DictationSettings()
        warm.cpuOnly = cpuOnly
        _ = try? await run(loaded, [Float](repeating: 0, count: 16_000), warm)
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
        loading = nil
        engine = nil
        engineModelID = nil
        setEngineStatus(.notLoaded)
    }

    /// After picking another model: load it now if a session is open.
    func modelChanged() {
        unloadEngine()
        if phase != .off { preloadEngine() }
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

enum EngineStatus: Equatable {
    case notLoaded
    case loading(since: Date)
    case ready(loadSeconds: TimeInterval)
    case failed(String)
}
