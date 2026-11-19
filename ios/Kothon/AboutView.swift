// The version line (with the hidden developer mode) and the open-source
// acknowledgements, both in the কিবোর্ড sheet.

import SwiftUI

/// "কথন 0.1.0 (build 3) · Beta". Tapping it 5 times turns developer mode on
/// or off: the speed test, chip names and load times.
struct VersionLine: View {
    @Binding var developerMode: Bool
    @State private var taps = 0

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "কথন \(short) (build \(build)) · Beta"
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(version)
            if developerMode { Text("ডেভেলপার মোড চালু").foregroundStyle(Brand.lilac) }
        }
        .font(.bn(.caption))
        .foregroundStyle(.white.opacity(0.5))
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            taps += 1
            if taps >= 5 {
                taps = 0
                developerMode.toggle()
            }
        }
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Open-source software and models Kothon is built on.
struct AcknowledgementsView: View {
    private struct Credit: Identifiable {
        let name: String
        let what: String
        let license: String
        var id: String { name }
    }

    private let software: [Credit] = [
        Credit(name: "Handy", what: "CJ Pais · কথন যার ওপর গড়া", license: "MIT"),
        Credit(name: "WhisperKit", what: "Argmax · Neural Engine-এ Whisper", license: "MIT"),
        Credit(name: "transcribe.cpp, whisper.cpp, ggml", what: "ফোনে মডেল চালানো (GPU/CPU)", license: "MIT"),
        Credit(name: "Candle", what: "Hugging Face · যতিচিহ্ন মডেল চালানো", license: "MIT / Apache-2.0"),
        Credit(name: "Tokenizers", what: "Hugging Face", license: "Apache-2.0"),
        Credit(name: "Silero VAD", what: "কথা আছে কিনা বোঝা", license: "MIT"),
        Credit(name: "Noto Sans Bengali", what: "Google · বাংলা ফন্ট", license: "SIL Open Font License 1.1"),
    ]

    private let models: [Credit] = [
        Credit(name: "নিখুঁত: BengaliAI Whisper Medium",
               what: "bengaliAI/tugstugi_bengaliai-asr_whisper-medium · Erdene-Ochir Tuguldur (tugstugi), team Chimege",
               license: "Apache-2.0"),
        Credit(name: "দ্রুত: Bangla FastConformer CTC 116M",
               what: "kazalbrur/Bangla-asr-fastconformer-116m-dialects", license: "Apache-2.0"),
        Credit(name: "যতিচিহ্ন: MuRIL (৬ লেয়ার)",
               what: "SayedShaun/asr-punctuation-restore-bn", license: "Apache-2.0"),
        Credit(name: "Whisper", what: "OpenAI · মূল মডেলের নকশা", license: "MIT"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("সফটওয়্যার", software)
                section("মডেল", models)
                Text("কথন নিজে MIT লাইসেন্সে। মডেলগুলো Hugging Face-এ omnixima-র পাতায়।")
                    .font(.bn(.footnote)).foregroundStyle(.white.opacity(0.6))
            }
            .padding(16)
        }
        .navigationTitle("লাইসেন্স ও কৃতজ্ঞতা")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, _ items: [Credit]) -> some View {
        GlassCard {
            Text(title).font(.bn(.headline, .semibold))
            ForEach(items) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.bn(.subheadline, .semibold))
                    Text(c.what).font(.bn(.caption)).foregroundStyle(.white.opacity(0.65))
                    Text(c.license).font(.bn(.caption, .medium)).foregroundStyle(Brand.lilac)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
