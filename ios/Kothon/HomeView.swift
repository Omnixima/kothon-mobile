// Kothon's home: a big mic on a deep plum glow (design B). Models, keyboard
// setup and writing style open as sheets from the tiles at the bottom.

import SwiftUI

struct KothonBackdrop: View {
    var body: some View {
        Brand.backdrop.ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10)))
    }
}

/// The wordmark, white on the plum screens, with the mark tile and "Beta".
struct Wordmark: View {
    var height: CGFloat = 40
    var showMark = true

    var body: some View {
        HStack(spacing: 10) {
            if showMark { BrandMark(size: height * 0.95) }
            Image("KothonWordmark").resizable().scaledToFit().frame(height: height * 0.75)
                .foregroundStyle(.white)
                .accessibilityLabel("কথন")
            BetaBadge()
        }
    }
}

private enum HomeSheet: String, Identifiable {
    case models, keyboard, style
    var id: String { rawValue }
}

struct HomeView: View {
    @EnvironmentObject var dictation: DictationService
    @EnvironmentObject var models: ModelStore
    @State private var sheet: HomeSheet?
    /// Set when a cancel is tapped during a model load, which goes on.
    @State private var loadingNote = false
    @State private var lastStats = ""

    var body: some View {
        ZStack {
            KothonBackdrop()
            VStack(spacing: 12) {
                topBar
                if dictation.isLoadingModel { LoadingCard() }
                if dictation.phase != .off { sessionPill }
                Spacer(minLength: 8)
                micArea
                Spacer(minLength: 8)
                lastCard
                tiles
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .foregroundStyle(.white)
        .sheet(item: $sheet) { which in
            HomeSheetView(which: which)
                .environmentObject(dictation)
                .environmentObject(models)
        }
        .onAppear { lastStats = KothonShared.defaults.string(forKey: SharedKey.stats) ?? "" }
        .onChange(of: dictation.lastStats) { _, new in lastStats = new }
        .onChange(of: dictation.phase) { _, _ in loadingNote = false }
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 8) {
            Image("KothonWordmark").resizable().scaledToFit().frame(height: 29)
                .foregroundStyle(.white)
                .accessibilityLabel("কথন")
            BetaBadge()
            Spacer(minLength: 8)
            ModelStatusPill { sheet = .models }
        }
        .frame(minHeight: 44)
    }

    private var sessionPill: some View {
        HStack(spacing: 8) {
            Circle().fill(.orange).frame(width: 8, height: 8)
            Text("সেশন চালু").font(.bn(.footnote, .medium))
            Spacer()
            Button("বন্ধ করুন") { dictation.endSession() }
                .font(.bn(.footnote, .semibold))
                .foregroundStyle(Brand.lilac)
        }
        .padding(.horizontal, 14).frame(minHeight: 40)
        .background(Color.white.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: Mic

    private var installed: Bool { models.isInstalled(models.selected) }

    private var micArea: some View {
        VStack(spacing: 26) {
            ZStack {
                Circle().strokeBorder(Brand.lilac.opacity(0.16), lineWidth: 1.5)
                    .frame(width: 240, height: 240)
                    .scaleEffect(ringScale(0.35))
                Circle().strokeBorder(Brand.lilac.opacity(0.26), lineWidth: 1.5)
                    .frame(width: 196, height: 196)
                    .scaleEffect(ringScale(0.25))
                Circle().fill(Brand.violetLight.opacity(0.22))
                    .frame(width: 156, height: 156)
                    .scaleEffect(ringScale(0.18))
                Button(action: micTapped) {
                    ZStack {
                        Circle().fill(Brand.micGradient)
                            .shadow(color: Brand.violet.opacity(0.9), radius: 20, y: 12)
                        switch dictation.phase {
                        case .transcribing:
                            ProgressView().tint(.white).controlSize(.large)
                        case .recording:
                            Image(systemName: "stop.fill").font(.system(size: 40, weight: .semibold))
                        default:
                            Image("KothonMark").resizable().scaledToFit().frame(width: 58)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 120, height: 120)
                }
                .buttonStyle(.plain)
                .disabled(!installed)
                .opacity(installed ? 1 : 0.55)
                .accessibilityLabel(dictation.phase == .recording ? "থামুন"
                                    : dictation.phase == .transcribing ? "লেখা বাতিল করুন" : "বলা শুরু করুন")
            }
            .frame(width: 240, height: 240)
            .animation(.easeOut(duration: 0.1), value: dictation.level)

            VStack(spacing: 6) {
                Text("বলুন, কথন লিখে দিবে।")
                    .font(.bn(size: 26, .bold))
                    .multilineTextAlignment(.center)
                Text(statusLine)
                    .font(.bn(.subheadline))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func ringScale(_ amount: CGFloat) -> CGFloat {
        dictation.phase == .recording ? 1 + CGFloat(dictation.level) * amount : 1
    }

    private func micTapped() {
        // While writing, the button cancels; a model load keeps going.
        if dictation.phase == .transcribing {
            if dictation.isLoadingModel { loadingNote = true } else { dictation.cancelTranscription() }
            return
        }
        Task {
            guard await KothonApp.microphoneAllowed() else { return }
            if dictation.phase == .recording { dictation.stopRecording() } else { dictation.startRecording() }
        }
    }

    private var statusLine: String {
        if !installed { return "আগে একটা মডেল নামান" }
        switch dictation.phase {
        case .recording: return "শুনছি… শেষ হলে আবার চাপুন"
        case .transcribing:
            return loadingNote ? "মডেল লোড পেছনে চলছে, শেষ হলে লেখা আসবে" : "লিখছি… বাতিল করতে চাপুন"
        default:
            return "চাপুন আর বাংলায় বলুন"
        }
    }

    // MARK: Last result

    /// "শেষ লেখা · ১.১ সে.-এ" from the stats line "… → ১.১ সে.-এ লেখা (…)".
    private var lastLabel: String {
        guard let arrow = lastStats.range(of: "→ ") else { return "শেষ লেখা" }
        let rest = lastStats[arrow.upperBound...]
        let took = rest.components(separatedBy: " লেখা").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return took.isEmpty ? "শেষ লেখা" : "শেষ লেখা · \(took)"
    }

    private var lastCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lastLabel).font(.bn(.caption2)).foregroundStyle(.white.opacity(0.6))
            if let err = dictation.lastError {
                Text(err).font(.bn(.subheadline)).foregroundStyle(Brand.softRed)
            } else if dictation.lastResult.isEmpty {
                Text("এখনও কিছু লেখা হয়নি। মাইক চাপুন আর বলুন।")
                    .font(.bn(.subheadline)).foregroundStyle(.white.opacity(0.6))
            } else {
                ScrollView {
                    Text(dictation.lastResult)
                        .font(.bn(.body))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
    }

    // MARK: Tiles

    private var tiles: some View {
        HStack(spacing: 8) {
            tile("মডেল", "cpu", .models)
            tile("কিবোর্ড", "keyboard", .keyboard)
            tile("লেখার ধরন", "text.alignleft", .style)
        }
    }

    private func tile(_ title: String, _ symbol: String, _ target: HomeSheet) -> some View {
        Button { sheet = target } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium)).foregroundStyle(Brand.lilac)
                Text(title).font(.bn(.caption, .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Full width under the header while the model loads: what's happening,
/// how long so far, and for the one-time Neural Engine prepare, roughly how
/// much is left.
struct LoadingCard: View {
    @EnvironmentObject var dictation: DictationService

    var body: some View {
        if case .loading(let since) = dictation.engineStatus {
            TimelineView(.periodic(from: since, by: 1)) { context in
                let elapsed = context.date.timeIntervalSince(since)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView().tint(Brand.lilac)
                        Text(dictation.preparingAfterUpdate ? "Neural Engine-এর জন্য প্রস্তুত হচ্ছে" : "মডেল লোড হচ্ছে")
                            .font(.bn(.headline, .semibold))
                        Spacer(minLength: 0)
                        Text("\(DictationService.bn(elapsed, digits: 0)) সে.")
                            .font(.bn(.subheadline, .medium)).monospacedDigit()
                            .foregroundStyle(Brand.lilac)
                    }
                    if dictation.preparingAfterUpdate {
                        // About 2 minutes; never claims to be done before it is.
                        ProgressView(value: min(elapsed / 120, 0.95))
                            .tint(Brand.violetLight)
                        Text("প্রায় ২ মিনিট, একবারই লাগে। অ্যাপ খোলা রাখুন।")
                            .font(.bn(.footnote)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Brand.lilac.opacity(0.25)))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The top-right pill: is the selected model ready?
struct ModelStatusPill: View {
    @EnvironmentObject var dictation: DictationService
    @EnvironmentObject var models: ModelStore
    let openModels: () -> Void

    /// "নিখুঁত (Neural Engine)" → "নিখুঁত"
    private var shortLabel: String {
        models.selected.label.components(separatedBy: " (").first ?? models.selected.label
    }

    var body: some View {
        Group {
            if !models.isInstalled(models.selected) {
                Button(action: openModels) {
                    pill { Image(systemName: "arrow.down.circle"); Text("মডেল নামান") }
                }
            } else {
                switch dictation.engineStatus {
                case .notLoaded:
                    Button { dictation.preloadEngine() } label: {
                        pill { Circle().fill(.gray).frame(width: 8, height: 8); Text("লোড হয়নি") }
                    }
                    .accessibilityHint("চাপলে মডেল লোড হবে")
                case .loading(let since):
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        pill {
                            ProgressView().controlSize(.mini).tint(Brand.lilac)
                            Text(dictation.preparingAfterUpdate ? "প্রস্তুত হচ্ছে" : "লোড হচ্ছে")
                        }
                    }
                case .ready:
                    Button(action: openModels) {
                        pill { Circle().fill(Brand.readyGreen).frame(width: 8, height: 8); Text("\(shortLabel) তৈরি") }
                    }
                case .failed:
                    Button { dictation.preloadEngine() } label: {
                        pill { Circle().fill(Brand.softRed).frame(width: 8, height: 8); Text("লোড হয়নি · আবার") }
                    }
                    .foregroundStyle(Brand.softRed)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func pill<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) { content() }
            .font(.bn(.caption, .medium))
            .foregroundStyle(Brand.lilac)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(minHeight: 32)
            .background(Color.white.opacity(0.10), in: Capsule())
            .contentShape(Capsule())
            .padding(.vertical, 6)
    }
}

/// What the home tiles open.
private struct HomeSheetView: View {
    let which: HomeSheet
    @Environment(\.dismiss) private var dismiss
    @State private var showIntro = false
    @AppStorage("developerMode") private var developerMode = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    switch which {
                    case .models:
                        ModelCard()
                        if developerMode { BenchmarkCard() }
                    case .keyboard:
                        KeyboardSetupView(showIntro: $showIntro, developerMode: $developerMode)
                    case .style:
                        SettingsCard()
                        NavigationLink { CustomWordsView() } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "character.book.closed").font(.system(size: 17))
                                    .foregroundStyle(Brand.lilac).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("আমার শব্দ").font(.bn(.body, .semibold))
                                    Text("নাম আর ইংরেজি শব্দ ঠিকঠাক লিখতে").font(.bn(.caption))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 60)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Plain text, not a bordered pill.
                    Button { dismiss() } label: {
                        Text("হয়ে গেছে").font(.bn(.body, .semibold)).foregroundStyle(Brand.lilac)
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground { KothonBackdrop() }
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showIntro) {
            IntroSlidesView { showIntro = false }
        }
    }

    private var title: String {
        switch which {
        case .models: "মডেল"
        case .keyboard: "কিবোর্ড"
        case .style: "লেখার ধরন"
        }
    }
}

struct ModelCard: View {
    @EnvironmentObject var models: ModelStore
    @EnvironmentObject var dictation: DictationService

    var body: some View {
        GlassCard {
            Label("মডেল", systemImage: "cpu").font(.bn(.headline, .semibold))
            ForEach(SpeechModel.all) { model in
                ModelRow(model: model)
            }
            if models.isInstalled(models.selected) {
                EngineStatusRow()
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("যতিচিহ্ন (। , ?)").font(.bn(.subheadline, .medium))
                    Text("ঐচ্ছিক · \(PunctuationModel.sizeMB) MB").font(.bn(.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                if models.punctuationInstalled {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Button {
                        confirmDeletePunctuation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityLabel("যতিচিহ্ন মডেল মুছুন")
                } else if let p = models.progress[PunctuationModel.dirName] {
                    ProgressView(value: p).frame(width: 80)
                } else {
                    Button("নামান") { Task { await models.downloadPunctuation() } }
                        .buttonStyle(.bordered)
                }
            }
            if let err = models.lastError {
                Text(err).font(.bn(.caption)).foregroundStyle(.red)
            }
        }
        .confirmationDialog("যতিচিহ্ন মডেল মুছবেন?", isPresented: $confirmDeletePunctuation, titleVisibility: .visible) {
            Button("মুছুন", role: .destructive) {
                models.deletePunctuation()
                dictation.modelChanged()
            }
        } message: {
            Text("তখন লেখায় । , ? বসবে না। পরে আবার নামাতে পারবেন।")
        }
    }

    @State private var confirmDeletePunctuation = false
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
                    dictation.modelChanged()
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.label).font(.bn(.subheadline, .semibold))
                Text(model.detail).font(.bn(.caption)).foregroundStyle(.secondary)
            }
            Spacer()
            if models.isInstalled(model) {
                if models.selectedID == model.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    // Only models not in use can be deleted.
                    Button {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityLabel("\(model.label) মুছুন")
                }
            } else if let p = models.progress[model.id] {
                ProgressView(value: p).frame(width: 80)
            } else {
                Button("নামান") { Task { await models.download(model) } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .confirmationDialog("\(model.label) মুছবেন?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("মুছুন", role: .destructive) { models.delete(model) }
        } message: {
            Text("ফোনে জায়গা খালি হবে। পরে দরকার হলে আবার নামাতে পারবেন।")
        }
    }

    @State private var confirmDelete = false
}

/// Whether the selected model is in memory and ready to write.
struct EngineStatusRow: View {
    @EnvironmentObject var dictation: DictationService
    @EnvironmentObject var models: ModelStore

    var body: some View {
        HStack(spacing: 8) {
            switch dictation.engineStatus {
            case .notLoaded:
                Circle().fill(.gray).frame(width: 8, height: 8)
                Text("মডেল লোড হয়নি").foregroundStyle(.secondary)
                Spacer()
                Button("লোড করুন") { dictation.preloadEngine() }
                    .buttonStyle(.bordered).controlSize(.small)
            case .loading(let since):
                ProgressView().controlSize(.small)
                TimelineView(.periodic(from: since, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("মডেল লোড হচ্ছে… \(DictationService.bn(context.date.timeIntervalSince(since), digits: 0)) সে.")
                        if models.selected.isCoreML {
                            Text("প্রথমবার Neural Engine-এর জন্য তৈরি করতে ১–২ মিনিট লাগে, পরে কয়েক সেকেন্ড।")
                                .font(.bn(.caption2)).foregroundStyle(.secondary)
                        }
                    }
                }
            case .ready(let seconds):
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("মডেল তৈরি")
                Text("· লোডে \(DictationService.bn(seconds)) সে.").foregroundStyle(.secondary)
            case .failed(let message):
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("লোড হয়নি: \(message)").foregroundStyle(.red).lineLimit(2)
                Spacer()
                Button("আবার") { dictation.preloadEngine() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .font(.bn(.caption))
        .padding(.leading, 30)
    }
}

/// Speed of the last dictation, and re-running it on other chips.
struct BenchmarkCard: View {
    @EnvironmentObject var dictation: DictationService
    @State private var lastStats = ""

    var body: some View {
        Group {
        if !lastStats.isEmpty {
            GlassCard {
                Label("গতি", systemImage: "speedometer").font(.bn(.headline, .semibold))
                Text("শেষবার: \(lastStats)").font(.bn(.caption)).foregroundStyle(.secondary)
                Button(dictation.benchmarking ? "মাপছি… (নিখুঁত-এ ২ মিনিট পর্যন্ত)" : "গতি মাপুন") {
                    Task { await dictation.benchmark() }
                }
                .buttonStyle(.bordered)
                .disabled(dictation.benchmarking || dictation.phase == .recording)
                Text("শেষ রেকর্ডিংটা GPU আর CPU-তে আবার চালিয়ে দেখায়")
                    .font(.bn(.caption2)).foregroundStyle(.secondary)
                if !dictation.benchmarkResult.isEmpty {
                    Text(dictation.benchmarkResult).font(.bn(.caption)).textSelection(.enabled)
                }
            }
        }
        }
        .onAppear { lastStats = KothonShared.defaults.string(forKey: SharedKey.stats) ?? "" }
        .onChange(of: dictation.lastStats) { _, new in lastStats = new }
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

struct SettingsCard: View {
    @AppStorage("digits", store: KothonShared.defaults) private var digits = 0
    @AppStorage("removeFillers", store: KothonShared.defaults) private var removeFillers = true
    @AppStorage("englishWordsInEnglish", store: KothonShared.defaults) private var english = false
    @AppStorage("punctuation", store: KothonShared.defaults) private var punctuation = true

    var body: some View {
        GlassCard {
            Label("লেখার ধরন", systemImage: "text.alignleft").font(.bn(.headline, .semibold))
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
        .font(.bn(.subheadline))
    }
}
