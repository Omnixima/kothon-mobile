// Drops recordings with no speech before they reach the model. Whisper
// makes up a word or two when given silence, e.g. when stop is pressed
// without speaking. Same Silero VAD model and threshold as the desktop app.

import Foundation
import KothonCore

final class SpeechGate {
    static let modelName = "silero-vad-v6.2-F32"
    private var vad: OpaquePointer?
    private var tried = false

    /// The speech part of `samples` (silence trimmed), or nil if there's none.
    /// Call on the engine queue.
    func speech(in samples: [Float]) -> [Float]? {
        if !tried {
            tried = true
            if let url = Bundle.main.url(forResource: Self.modelName, withExtension: "gguf") {
                var err: UnsafeMutablePointer<CChar>?
                vad = url.path.withCString { kothon_vad_new($0, &err) }
                if let err { kothon_string_free(err) }
            }
        }
        var start = 0, end = 0
        let found = samples.withUnsafeBufferPointer {
            kothon_vad_speech(vad, $0.baseAddress, $0.count, &start, &end)
        }
        guard found else { return nil }
        return Array(samples[start..<end])
    }

    deinit { if let vad { kothon_vad_free(vad) } }
}
