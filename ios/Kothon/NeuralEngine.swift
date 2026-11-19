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
    private let whisper: WhisperKit
    let model: SpeechModel

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
        Task.detached(priority: .userInitiated) {
            do {
                let options = DecodingOptions(
                    task: .transcribe, language: "bn", temperature: 0,
                    usePrefillPrompt: true, detectLanguage: false,
                    skipSpecialTokens: true, withoutTimestamps: true)
                let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
                outcome = .success(results.map(\.text).joined(separator: " "))
            } catch {
                outcome = .failure(error)
            }
            done.signal()
        }
        done.wait()
        let raw = try outcome.get().trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.postProcess(raw, settings: settings)
    }

    func prepareForBackground() {}

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
