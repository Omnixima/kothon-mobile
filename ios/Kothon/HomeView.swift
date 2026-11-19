// Kothon's home: glass cards on a soft lavender backdrop, like the desktop app.

import SwiftUI

struct KothonBackdrop: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            RadialGradient(colors: [Color.accentColor.opacity(0.16), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color.accentColor.opacity(0.10), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06)))
            .shadow(color: Color(red: 60/255, green: 20/255, blue: 110/255).opacity(0.18), radius: 18, y: 10)
    }
}

struct Wordmark: View {
    var height: CGFloat = 40
    var body: some View {
        HStack(spacing: 10) {
            Image("KothonMark").resizable().scaledToFit().frame(height: height * 0.8)
                .foregroundStyle(Color.accentColor)
            Image("KothonWordmark").resizable().scaledToFit().frame(height: height)
                .foregroundStyle(.primary)
            Text("বেটা")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .foregroundStyle(Color.accentColor)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var dictation: DictationService
    @EnvironmentObject var models: ModelStore

    var body: some View {
        NavigationStack {
            ZStack {
                KothonBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Wordmark()
                            Text("বলুন, কথন লিখে দিবে।")
                                .font(.title3).foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)

                        ModelCard()
                        KeyboardSetupCard()
                        TryItCard()
                        SessionCard()
                        SettingsCard()

                        Text("সব কাজ আপনার ফোনেই হয়। কোনো শব্দ বা লেখা ইন্টারনেটে যায় না।")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 8)
                    }
                    .padding(16)
                }
            }
        }
    }
}

struct ModelCard: View {
    @EnvironmentObject var models: ModelStore

    var body: some View {
        GlassCard {
            Label("মডেল", systemImage: "cpu").font(.headline)
            ForEach(SpeechModel.all) { model in
                ModelRow(model: model)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("যতিচিহ্ন (। , ?)").font(.subheadline.weight(.medium))
                    Text("ঐচ্ছিক · \(PunctuationModel.sizeMB) MB").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if models.punctuationInstalled {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if let p = models.progress[PunctuationModel.dirName] {
                    ProgressView(value: p).frame(width: 80)
                } else {
                    Button("নামান") { Task { await models.downloadPunctuation() } }
                        .buttonStyle(.bordered)
                }
            }
            if let err = models.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

struct ModelRow: View {
    @EnvironmentObject var models: ModelStore
    @EnvironmentObject var dictation: DictationService
    let model: SpeechModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: models.selectedID == model.id ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(Color.accentColor)
                .onTapGesture {
                    guard models.isInstalled(model) else { return }
                    models.selectedID = model.id
                    dictation.unloadEngine()
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.label).font(.subheadline.weight(.semibold))
                Text(model.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if models.isInstalled(model) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if let p = models.progress[model.id] {
                ProgressView(value: p).frame(width: 80)
            } else {
                Button("নামান") { Task { await models.download(model) } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct KeyboardSetupCard: View {
    var body: some View {
        GlassCard {
            Label("কথন কিবোর্ড চালু করুন", systemImage: "keyboard").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("১. সেটিংস → সাধারণ → কিবোর্ড → কিবোর্ডসমূহ → নতুন কিবোর্ড যোগ করুন → কথন")
                Text("২. কথন-এ ট্যাপ করে \"Allow Full Access\" চালু করুন। মাইক থেকে লেখা কিবোর্ডে আনতে এটা লাগে; কিবোর্ড ইন্টারনেটে কিছু পাঠায় না।")
                Text("৩. যেকোনো অ্যাপে 🌐 চেপে কথন বেছে নিন, তারপর মাইক চাপুন।")
            }
            .font(.subheadline)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("সেটিংস খুলুন", systemImage: "gear")
            }
            .buttonStyle(.bordered)
        }
    }
}

struct TryItCard: View {
    @EnvironmentObject var dictation: DictationService
    @EnvironmentObject var models: ModelStore

    var body: some View {
        GlassCard {
            Label("এখানে চেষ্টা করুন", systemImage: "waveform").font(.headline)
            HStack(spacing: 14) {
                MicButton(phase: dictation.phase, level: dictation.level) {
                    Task {
                        guard await KothonApp.microphoneAllowed() else { return }
                        if dictation.phase == .recording {
                            dictation.stopRecording()
                        } else {
                            dictation.startRecording()
                        }
                    }
                }
                .disabled(!models.isInstalled(models.selected) || dictation.phase == .transcribing)
                Text(status).font(.subheadline).foregroundStyle(.secondary)
            }
            if !dictation.lastResult.isEmpty {
                Text(dictation.lastResult)
                    .font(.title3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            if !lastStats.isEmpty {
                Text("শেষবার: \(lastStats)").font(.caption).foregroundStyle(.secondary)
            }
            if let err = dictation.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { lastStats = KothonShared.defaults.string(forKey: SharedKey.stats) ?? "" }
        .onChange(of: dictation.lastStats) { _, new in lastStats = new }
    }

    @State private var lastStats = ""

    private var status: String {
        if !models.isInstalled(models.selected) { return "আগে একটা মডেল নামান" }
        switch dictation.phase {
        case .recording: return "শুনছি… শেষ হলে আবার চাপুন"
        case .transcribing: return "লিখছি…"
        default: return "মাইক চেপে কথা বলুন"
        }
    }
}

struct MicButton: View {
    let phase: DictationPhase
    var level: Float = 0
    var size: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .scaleEffect(phase == .recording ? 1 + CGFloat(level) * 0.5 : 1)
                    .animation(.easeOut(duration: 0.1), value: level)
                Circle().fill(Color.accentColor).padding(size * 0.1)
                if phase == .transcribing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: phase == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: size * 0.32, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(phase == .recording ? "থামুন" : "বলা শুরু করুন")
    }
}

struct SessionCard: View {
    @EnvironmentObject var dictation: DictationService

    var body: some View {
        if dictation.phase != .off {
            GlassCard {
                HStack {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                    Text("কথন সেশন চালু").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("বন্ধ করুন") { dictation.endSession() }.buttonStyle(.bordered)
                }
                Text("সেশন চালু থাকলে কিবোর্ড থেকে সরাসরি বলা যায়, অ্যাপে আসতে হয় না। ৫ মিনিট কিছু না বললে নিজেই বন্ধ হয়ে যায়।")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct SettingsCard: View {
    @AppStorage("digits", store: KothonShared.defaults) private var digits = 0
    @AppStorage("removeFillers", store: KothonShared.defaults) private var removeFillers = true
    @AppStorage("englishWordsInEnglish", store: KothonShared.defaults) private var english = false
    @AppStorage("punctuation", store: KothonShared.defaults) private var punctuation = true

    var body: some View {
        GlassCard {
            Label("লেখার ধরন", systemImage: "textformat").font(.headline)
            Picker("সংখ্যা", selection: $digits) {
                Text("২০২৬").tag(0)
                Text("2026").tag(1)
                Text("শব্দে").tag(2)
            }
            .pickerStyle(.segmented)
            Toggle("যতিচিহ্ন বসান", isOn: $punctuation)
            Toggle("উম, হুম বাদ দিন", isOn: $removeFillers)
            Toggle("ইংরেজি শব্দ ইংরেজিতে (meeting-এ)", isOn: $english)
        }
        .font(.subheadline)
    }
}
