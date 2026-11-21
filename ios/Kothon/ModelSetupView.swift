// First run, after the intro: pick a model and start the download, then
// set up the keyboard. Also opened from home while no model is installed.

import SwiftUI

/// "একটা মডেল বেছে নিন": two cards (দ্রুত, নিখুঁত), none chosen up front, free space,
/// optional punctuation, one "ডাউনলোড" button. The download carries on while
/// the user moves on; home shows its progress.
struct ModelSetupView: View {
    @EnvironmentObject var models: ModelStore
    @EnvironmentObject var dictation: DictationService
    let done: () -> Void
    var showSkip = true

    /// The plum at the bottom of the backdrop, behind the bottom buttons.
    static let barColor = Color(red: 0x1A / 255, green: 0x08 / 255, blue: 0x26 / 255)

    /// Nothing is chosen for the user: they pick, then download.
    @State private var choice: SpeechModel?
    @State private var punctuation = true
    /// Smaller first.
    private let options: [SpeechModel] = [.fast, ModelStore.accurateForThisPhone]

    var body: some View {
        ZStack {
            KothonBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Wordmark(height: 30).padding(.top, 12)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("একটা মডেল বেছে নিন").font(.bn(.title, .bold))
                        Text("কথা থেকে লেখা বানানোর জন্য একবার ডাউনলোড করতে হয়। তারপর সব ফোনেই চলে, ইন্টারনেট ছাড়াই।")
                            .font(.bn(.body)).foregroundStyle(.white.opacity(0.72))
                    }
                    VStack(spacing: 12) {
                        ForEach(options) { m in card(m) }
                    }
                    Toggle(isOn: $punctuation) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("যতিচিহ্ন বসানো (। , ?)").font(.bn(.body, .semibold))
                            Text("ঐচ্ছিক · \(DictationService.bn(Double(PunctuationModel.sizeMB), digits: 0)) MB")
                                .font(.bn(.caption)).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .tint(Brand.violet)
                    .padding(16)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    if let free = models.freeMB {
                        Label("ফোনে খালি আছে \(DictationService.bn(Double(free) / 1000)) GB", systemImage: "internaldrive")
                            .font(.bn(.footnote)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button(action: start) {
                        Text(choice.map { "\($0 == .fast ? "দ্রুত" : "নিখুঁত") ডাউনলোড করুন" } ?? "একটা মডেল বেছে নিন")
                            .font(.bn(.headline, .semibold))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Brand.micGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(choice == nil || choice.flatMap(models.roomProblem) != nil)
                    .opacity(choice != nil && choice.flatMap(models.roomProblem) == nil ? 1 : 0.5)
                    if showSkip {
                        Button("পরে করব", action: done)
                            .font(.bn(.subheadline, .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(minHeight: 36)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .background(Self.barColor.ignoresSafeArea())
            }
        }
        .foregroundStyle(.white)
        
    }

    private func card(_ m: SpeechModel) -> some View {
        let selected = choice == m
        let problem = models.roomProblem(m)
        return Button { if problem == nil { choice = m } } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22)).foregroundStyle(selected ? Brand.lilac : .white.opacity(0.4))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(m == .fast ? "দ্রুত" : "নিখুঁত").font(.bn(.title3, .bold))
                    }
                    Text(m == .fast
                         ? "ছোট, কয়েক মিনিটেই নেমে যায়। মাঝে মাঝে বানান ভুল হতে পারে।"
                         : ModelStore.olderChip
                            ? "সবচেয়ে কম ভুল, তবে বড়। এই ফোনে কিবোর্ড থেকে একটু ধীর।"
                            : "সবচেয়ে কম ভুল, তবে বড়। ভালো ওয়াইফাইতে নামানো ভালো।")
                        .font(.bn(.subheadline)).foregroundStyle(.white.opacity(0.75))
                    Text("\(DictationService.bn(Double(m.sizeMB), digits: 0)) MB")
                        .font(.bn(.caption, .semibold)).foregroundStyle(.white.opacity(0.55))
                    if let problem {
                        Text(problem).font(.bn(.caption, .medium)).foregroundStyle(Brand.softRed)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color.white.opacity(selected ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? Brand.lilac.opacity(0.7) : Color.white.opacity(0.08), lineWidth: selected ? 2 : 1))
            .opacity(problem == nil ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Start the downloads and move on; they continue while the app is open,
    /// and the model is selected and prepared as soon as it lands.
    private func start() {
        guard let m = choice else { return }
        let withPunctuation = punctuation && !models.punctuationInstalled
        // With nothing on the phone yet, show this download on home. If it
        // fails, dictation falls back to any installed model
        // (ModelStore.usableModel), so this choice never blocks the keyboard.
        if !SpeechModel.all.contains(where: models.isInstalled) { models.selectedID = m.id }
        Task {
            await models.download(m)
            if models.isInstalled(m) {
                models.selectedID = m.id
                dictation.modelChanged()
                dictation.prepareEngineIfNeeded()
            }
        }
        if withPunctuation { Task { await models.downloadPunctuation() } }
        done()
    }
}

/// First run, after the model: the keyboard checklist, skippable.
struct KeyboardSetupStep: View {
    let done: () -> Void
    @State private var showIntro = false
    @AppStorage("developerMode") private var developerMode = false

    var body: some View {
        NavigationStack {
        ZStack {
            KothonBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Wordmark(height: 30).padding(.top, 12)
                    KeyboardSetupView(showIntro: $showIntro, developerMode: $developerMode)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: done) {
                    Text("এগিয়ে যান")
                        .font(.bn(.headline, .semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(ModelSetupView.barColor.ignoresSafeArea())
            }
        }
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showIntro) { IntroSlidesView { showIntro = false } }
    }
}
