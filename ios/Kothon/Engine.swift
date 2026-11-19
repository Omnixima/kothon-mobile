// Swift face of kothon-core (the Rust engine shared with Android).

import Foundation
import KothonCore

/// Anything that turns 16 kHz mono audio into Bengali text. On-device today;
/// an optional online engine could slot in here later.
protocol Transcriber: AnyObject {
    func transcribe(_ samples: [Float], settings: DictationSettings) throws -> String
    /// Getting ready to run in the background: free what can't be used there.
    func prepareForBackground()
    /// Stop a running transcribe() early, if the engine can. Thread-safe.
    func cancel()
}

extension Transcriber {
    /// GGUF engines run to the end; their result is dropped instead.
    func cancel() {}
}

extension OnDeviceEngine {
    func prepareForBackground() {
        unload(cpu: false)
        warmCPU()
    }
}

struct DictationSettings {
    enum Digits: UInt8 { case bengali = 0, latin = 1, words = 2 }
    var digits: Digits = .bengali
    var removeFillers = true
    var englishWordsInEnglish = false
    var punctuation = true
    /// iOS doesn't let background apps use the GPU, so dictations from the
    /// keyboard (app in the background) run on the CPU.
    var cpuOnly = false

    static var current: DictationSettings {
        let d = KothonShared.defaults
        var s = DictationSettings()
        if let raw = d.object(forKey: "digits") as? Int, let v = Digits(rawValue: UInt8(raw)) {
            s.digits = v
        }
        if d.object(forKey: "removeFillers") != nil { s.removeFillers = d.bool(forKey: "removeFillers") }
        s.englishWordsInEnglish = d.bool(forKey: "englishWordsInEnglish")
        if d.object(forKey: "punctuation") != nil { s.punctuation = d.bool(forKey: "punctuation") }
        return s
    }
}

struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class OnDeviceEngine: Transcriber {
    private let handle: OpaquePointer
    let model: SpeechModel

    init(model: SpeechModel, modelURL: URL, punctuationDir: URL?, cpuOnly: Bool) throws {
        var err: UnsafeMutablePointer<CChar>?
        let h = modelURL.path.withCString { modelPath in
            if let punctuationDir {
                return punctuationDir.path.withCString { kothon_engine_new(modelPath, $0, cpuOnly, &err) }
            }
            return kothon_engine_new(modelPath, nil, cpuOnly, &err)
        }
        guard let h else {
            throw EngineError(message: Self.take(err) ?? "Couldn't load the model")
        }
        handle = h
        self.model = model
    }

    deinit { kothon_engine_free(handle) }

    func transcribe(_ samples: [Float], settings: DictationSettings) throws -> String {
        var options = KothonOptions(
            digits: settings.digits.rawValue,
            remove_fillers: settings.removeFillers,
            english_words_in_english: settings.englishWordsInEnglish,
            punctuation: settings.punctuation,
            no_timestamps: model.noTimestamps,
            cpu_only: settings.cpuOnly)
        var err: UnsafeMutablePointer<CChar>?
        let out = samples.withUnsafeBufferPointer { buf in
            kothon_transcribe(handle, buf.baseAddress, buf.count, &options, &err)
        }
        guard let text = Self.take(out) else {
            throw EngineError(message: Self.take(err) ?? "Transcription failed")
        }
        return text
    }

    /// CPU threads (0 = library default) and Accelerate on/off. The CPU copy reloads.
    func setCPU(threads: Int32, accel: Bool) { kothon_engine_set_cpu(handle, threads, accel) }

    /// Free the GPU or CPU copy of the model; it reloads when next needed.
    func unload(cpu: Bool) { kothon_engine_unload(handle, cpu) }

    /// Load the CPU copy now (by running a moment of silence), so the first
    /// dictation from the keyboard doesn't wait for it.
    func warmCPU() {
        var settings = DictationSettings()
        settings.cpuOnly = true
        _ = try? transcribe([Float](repeating: 0, count: 8_000), settings: settings)
    }

    /// Copy a Rust-owned string into Swift and free it.
    private static func take(_ p: UnsafeMutablePointer<CChar>?) -> String? {
        guard let p else { return nil }
        defer { kothon_string_free(p) }
        return String(cString: p)
    }
}
