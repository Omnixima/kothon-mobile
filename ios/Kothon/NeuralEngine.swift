// Whisper on the Neural Engine, through Core ML (WhisperKit, MIT).
//
// iOS doesn't let background apps use the GPU, and the keyboard's dictations
// run with the app in the background. The Neural Engine is a separate chip;
// this checks whether it stays fast there. Nothing here uses the GPU.

import CoreML
import Foundation
import KothonCore
import WhisperKit

enum NeuralEngineModels {
    static func download(repo: String, variant: String, into dir: URL,
                         progress: @escaping (Double) -> Void) async throws -> URL {
        try await WhisperKit.download(
            variant: variant, downloadBase: dir, from: repo,
            progressCallback: { progress($0.fractionCompleted) })
    }
}

final class NeuralEngineEngine: Transcriber {
    /// Timing breakdown of the last run, for the benchmark readout.
    nonisolated(unsafe) static var lastBreakdown = ""
    private let whisper: WhisperKit
    let model: SpeechModel
    /// The running transcription, so cancel() can stop it.
    private let lock = NSLock()
    private var running: Task<Void, Never>?

    init(model: SpeechModel, folder: URL) async throws {
        let compute = ModelComputeOptions(
            melCompute: .cpuOnly,
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine,
            prefillCompute: .cpuOnly)
        let config = WhisperKitConfig(
            modelFolder: folder.path,
            computeOptions: compute,
            verbose: false,
            prewarm: true,
            load: true,
            download: false)
        whisper = try await WhisperKit(config)
        self.model = model
    }

    func transcribe(_ samples: [Float], settings: DictationSettings) throws -> String {
        // The Transcriber protocol is synchronous and runs on the engine
        // queue, so wait here for WhisperKit's async call.
        let done = DispatchSemaphore(value: 0)
        var outcome: Result<String, Error> = .success("")
        let whisper = self.whisper
        let task = Task.detached(priority: .userInitiated) {
            do {
                let options = DecodingOptions(
                    task: .transcribe, language: "bn", temperature: 0,
                    usePrefillPrompt: true, detectLanguage: false,
                    skipSpecialTokens: true, withoutTimestamps: true)
                let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
                if let t = results.first?.timings {
                    // Where the time goes: the encoder (one pass) versus the
                    // decoder (one step per token). Shown under the benchmark.
                    NeuralEngineEngine.lastBreakdown = String(
                        format: "encoder %.2f s · decoder %.2f s, %d tokens",
                        t.encoding, t.decodingLoop, Int(t.totalDecodingLoops))
                }
                outcome = .success(results.map(\.text).joined(separator: " "))
            } catch {
                outcome = .failure(error)
            }
            done.signal()
        }
        lock.lock(); running = task; lock.unlock()
        done.wait()
        lock.lock(); running = nil; lock.unlock()
        if task.isCancelled { throw CancellationError() }
        let raw = try outcome.get().trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.postProcess(raw, settings: settings)
    }

    func prepareForBackground() {}

    /// WhisperKit checks for cancellation between decoding steps.
    func cancel() {
        lock.lock(); let task = running; lock.unlock()
        task?.cancel()
    }

    /// Kothon's rule-based cleanup (numbers, fillers, English words).
    private static func postProcess(_ text: String, settings: DictationSettings) -> String {
        var options = KothonOptions(
            digits: settings.digits.rawValue, remove_fillers: settings.removeFillers,
            english_words_in_english: settings.englishWordsInEnglish,
            punctuation: false, no_timestamps: true, cpu_only: true)
        guard let out = text.withCString({ kothon_post_process($0, &options) }) else { return text }
        defer { kothon_string_free(out) }
        return String(cString: out)
    }
}
