// The মডেল sheet: what's running now, the two speech models, punctuation,
// and how much space Kothon's models take.

import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var models: ModelStore
    @EnvironmentObject var dictation: DictationService
    @AppStorage("developerMode") private var developerMode = false
    @AppStorage("punctuation", store: KothonShared.defaults) private var punctuation = true
    @State private var confirmDelete: SpeechModel?
    @State private var confirmDeletePunctuation = false

    /// What people choose between. The GGUF নিখুঁত (GPU/CPU) is only for
    /// developer mode: on current iPhones the Neural Engine one is faster
    /// from the keyboard and as accurate.
    private var choices: [SpeechModel] {
        developerMode ? [.accurateNeuralEngine, .fast, .accurate] : [.accurateNeuralEngine, .fast]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            NowRunningCard()
            section("কথা থেকে লেখা") {
                ForEach(Array(choices.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { divider }
                    row(m)
                }
            }
            section("যতিচিহ্ন") { punctuationRow }
            if let err = models.lastError {
                Text(err).font(.bn(.footnote)).foregroundStyle(Brand.softRed)
            }
            footer
            if developerMode { BenchmarkCard() }
        }
        .confirmationDialog("\(confirmDelete?.label ?? "") মুছবেন?",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("মুছুন", role: .destructive) {
                if let m = confirmDelete { models.delete(m) }
                confirmDelete = nil
            }
        } message: {
            Text("ফোনে জায়গা খালি হবে। পরে দরকার হলে আবার ডাউনলোড করতে পারবেন।")
        }
        .confirmationDialog("যতিচিহ্ন মডেল মুছবেন?", isPresented: $confirmDeletePunctuation, titleVisibility: .visible) {
            Button("মুছুন", role: .destructive) {
                models.deletePunctuation()
                dictation.modelChanged()
            }
        } message: {
            Text("তখন লেখায় । , ? বসবে না। পরে আবার ডাউনলোড করতে পারবেন।")
        }
    }

    // MARK: Pieces

    private var divider: some View {
        Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 52)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.bn(.footnote, .semibold)).foregroundStyle(.white.opacity(0.6))
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func description(_ m: SpeechModel) -> String {
        switch m {
        case .fast: "ছোট আর দ্রুত, একটু বেশি ভুল"
        case .accurateNeuralEngine: "সবচেয়ে কম ভুল, কিবোর্ড থেকেও দ্রুত"
        default: "নিখুঁত, GPU/CPU-তে (ডেভেলপার)"
        }
    }

    private func title(_ m: SpeechModel) -> String {
        m == .accurate ? "নিখুঁত (GPU)" : (m.label.components(separatedBy: " (").first ?? m.label)
    }

    private func row(_ m: SpeechModel) -> some View {
        let installed = models.isInstalled(m)
        let selected = models.selectedID == m.id
        return HStack(spacing: 14) {
            Image(systemName: selected && installed ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(selected && installed ? Brand.lilac : .white.opacity(0.35))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title(m)).font(.bn(.body, .semibold))
                    if m == ModelStore.recommended {
                        Text("প্রস্তাবিত").font(.bn(.caption2, .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Brand.violet, in: Capsule())
                    }
                }
                Text("\(description(m)) · \(DictationService.bn(Double(m.sizeMB), digits: 0)) MB")
                    .font(.bn(.caption)).foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 8)
            trailing(m, installed: installed, selected: selected)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .onTapGesture {
            guard installed, !selected else { return }
            models.selectedID = m.id
            dictation.modelChanged()
            dictation.prepareEngineIfNeeded()
        }
        .contextMenu {
            if installed && !selected {
                Button("মুছুন", systemImage: "trash", role: .destructive) { confirmDelete = m }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func trailing(_ m: SpeechModel, installed: Bool, selected: Bool) -> some View {
        if let p = models.progress[m.id] {
            ProgressRing(fraction: p)
        } else if !installed {
            Button("ডাউনলোড") {
                Task {
                    await models.download(m)
                    if models.isInstalled(m) && !models.isInstalled(models.selected) {
                        models.selectedID = m.id
                        dictation.modelChanged()
                        dictation.prepareEngineIfNeeded()
                    }
                }
            }
            .font(.bn(.subheadline, .semibold))
            .buttonStyle(.borderedProminent)
            .tint(Brand.violet)
            .disabled(models.roomProblem(m) != nil)
        } else if selected {
            Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Brand.readyGreen)
        }
    }

    private var punctuationRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.questionmark").font(.system(size: 18)).foregroundStyle(Brand.lilac).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("যতিচিহ্ন বসান (। , ?)").font(.bn(.body, .semibold))
                Text(models.punctuationInstalled
                     ? "ফোনে আছে · \(DictationService.bn(Double(PunctuationModel.sizeMB), digits: 0)) MB"
                     : "চালু করলে \(DictationService.bn(Double(PunctuationModel.sizeMB), digits: 0)) MB ডাউনলোড হবে")
                    .font(.bn(.caption)).foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 8)
            if let p = models.progress[PunctuationModel.dirName] {
                ProgressRing(fraction: p)
            } else {
                Toggle("", isOn: Binding(
                    get: { punctuation && models.punctuationInstalled },
                    set: { on in
                        punctuation = on
                        if on && !models.punctuationInstalled {
                            Task { await models.downloadPunctuation(); dictation.modelChanged() }
                        } else {
                            dictation.modelChanged()
                        }
                    }))
                    .labelsHidden()
                    .tint(Brand.violet)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .contextMenu {
            if models.punctuationInstalled {
                Button("মুছুন", systemImage: "trash", role: .destructive) { confirmDeletePunctuation = true }
            }
        }
    }

    private var footer: some View {
        let usedMB = SpeechModel.all.filter { models.isInstalled($0) }.reduce(0) { $0 + $1.sizeMB }
            + (models.punctuationInstalled ? PunctuationModel.sizeMB : 0)
        var parts = ["কথনের মডেল মোট \(DictationService.bn(Double(usedMB), digits: 0)) MB"]
        if let free = models.freeMB { parts.append("ফোনে খালি \(DictationService.bn(Double(free) / 1000)) GB") }
        return VStack(alignment: .leading, spacing: 4) {
            Text(parts.joined(separator: " · ")).font(.bn(.footnote)).foregroundStyle(.white.opacity(0.6))
            Text("মুছতে কোনো মডেলে আঙুল চেপে ধরুন।").font(.bn(.caption)).foregroundStyle(.white.opacity(0.45))
        }
        .padding(.leading, 4)
    }
}

/// "এখন চলছে": the active model and whether it's ready.
private struct NowRunningCard: View {
    @EnvironmentObject var models: ModelStore
    @EnvironmentObject var dictation: DictationService

    private var name: String {
        models.selected.label.components(separatedBy: " (").first ?? models.selected.label
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Brand.micGradient).frame(width: 44, height: 44)
                Image("KothonMark").resizable().scaledToFit().frame(width: 22).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("এখন চলছে").font(.bn(.caption, .medium)).foregroundStyle(.white.opacity(0.6))
                Text(models.isInstalled(models.selected) || models.progress[models.selected.id] != nil ? name : "কোনো মডেল নেই")
                    .font(.bn(.title3, .bold))
                state
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private var state: some View {
        if let p = models.progress[models.selected.id] {
            label("ডাউনলোড হচ্ছে… \(DictationService.bn(p * 100, digits: 0))%", Brand.lilac, spinner: true)
        } else if !models.isInstalled(models.selected) {
            label("নিচ থেকে একটা মডেল ডাউনলোড করুন", .white.opacity(0.6))
        } else {
            switch dictation.engineStatus {
            case .ready:
                label("তৈরি", Brand.readyGreen, dot: true)
            case .loading(let since):
                TimelineView(.periodic(from: since, by: 1)) { ctx in
                    label("\(dictation.preparingAfterUpdate ? "প্রস্তুত হচ্ছে" : "লোড হচ্ছে")… \(DictationService.bn(ctx.date.timeIntervalSince(since), digits: 0)) সে.",
                          Brand.lilac, spinner: true)
                }
            case .notLoaded:
                Button { dictation.preloadEngine() } label: {
                    label("লোড হয়নি · চাপুন", .white.opacity(0.7), dot: true)
                }
                .buttonStyle(.plain)
            case .failed(let msg):
                Button { dictation.preloadEngine() } label: {
                    label("লোড হয়নি: \(msg) · আবার চেষ্টা", Brand.softRed, dot: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func label(_ text: String, _ color: Color, dot: Bool = false, spinner: Bool = false) -> some View {
        HStack(spacing: 6) {
            if spinner { ProgressView().controlSize(.mini).tint(color) }
            if dot { Circle().fill(color).frame(width: 8, height: 8) }
            Text(text).font(.bn(.footnote, .medium)).foregroundStyle(color).lineLimit(2)
        }
    }
}

/// A small download progress ring with the percentage.
struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle().trim(from: 0, to: max(0.02, fraction))
                .stroke(Brand.violetLight, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(DictationService.bn(fraction * 100, digits: 0))").font(.bn(size: 10, .semibold))
        }
        .frame(width: 34, height: 34)
        .accessibilityLabel("ডাউনলোড \(Int(fraction * 100))%")
    }
}
