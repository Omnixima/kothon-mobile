// The keyboard: a full Bengali letter layout with a mic key for dictation.
// Typing works without Full Access; only dictation needs it (to hand the
// text over from the app). While dictating, the letter rows give way to a
// big mic button.
//
// The layout is Kothon's own, arranged by frequency: vowel signs and the
// common consonants on the base layer, independent vowels and the rest on
// shift, Bengali digits and punctuation on ১২৩.

import SwiftUI

private enum Layer { case letters, shifted, numbers }

private enum Layout {
    static let letters: [[String]] = [
        ["া", "ি", "ী", "ু", "ূ", "ৃ", "ে", "ৈ", "ো", "ৌ"],
        ["ক", "খ", "গ", "চ", "জ", "ট", "ড", "ত", "দ", "ন", "ব"],
        ["প", "ম", "য", "র", "ল", "শ", "স", "হ", "্"],
    ]
    static let shifted: [[String]] = [
        ["অ", "আ", "ই", "ঈ", "উ", "ঊ", "ঋ", "এ", "ঐ", "ও", "ঔ"],
        ["ঘ", "ঙ", "ছ", "ঝ", "ঞ", "ঠ", "ঢ", "ণ", "থ", "ধ", "ফ"],
        ["ভ", "ষ", "ড়", "ঢ়", "য়", "ৎ", "ং", "ঃ", "ঁ"],
    ]
    static let numbers: [[String]] = [
        ["১", "২", "৩", "৪", "৫", "৬", "৭", "৮", "৯", "০"],
        ["-", "/", ":", ";", "(", ")", "৳", "\"", "'", "@"],
        ["।", ",", "?", "!", ".", "…"],
    ]
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let onMic: () -> Void
    let onCancel: () -> Void
    let onInsert: (String) -> Void
    let onDelete: () -> Void
    let onReturn: () -> Void
    let onGlobe: () -> Void

    @State private var layer: Layer = .letters

    private var dictating: Bool { model.phase == .recording || model.phase == .transcribing }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                BrandMark(size: 20)
                Text(status).font(.bn(.footnote)).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                if model.phase == .recording || (model.phase == .transcribing && !model.modelLoading) {
                    Button("বাতিল", action: onCancel).font(.bn(.footnote, .medium))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)

            if dictating {
                bigMic.frame(maxWidth: .infinity).frame(height: 3 * 42 + 2 * 8)
            } else {
                rows
            }
            bottomRow
        }
        .padding(.horizontal, 3)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: Letter rows

    private var rows: some View {
        let grid: [[String]] = switch layer {
        case .letters: Layout.letters
        case .shifted: Layout.shifted
        case .numbers: Layout.numbers
        }
        return VStack(spacing: 8) {
            row(grid[0])
            row(grid[1])
            HStack(spacing: 5) {
                if layer == .numbers {
                    Spacer(minLength: 0).frame(width: 44)
                } else {
                    SpecialKey(systemImage: layer == .shifted ? "shift.fill" : "shift",
                               highlighted: layer == .shifted,
                               label: "শিফট") {
                        layer = layer == .shifted ? .letters : .shifted
                    }
                    .frame(width: 44)
                }
                row(grid[2])
                RepeatKey(systemImage: "delete.left", action: onDelete).frame(width: 44)
            }
        }
    }

    private func row(_ keys: [String]) -> some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { k in
                LetterKey(label: k) {
                    onInsert(k)
                    // Shift is for one letter, like the system keyboard.
                    if layer == .shifted { layer = .letters }
                }
            }
        }
    }

    // MARK: Bottom row

    private var bottomRow: some View {
        HStack(spacing: 5) {
            SpecialKey(text: layer == .numbers ? "কখগ" : "১২৩", label: layer == .numbers ? "অক্ষর" : "সংখ্যা") {
                layer = layer == .numbers ? .letters : .numbers
            }
            .frame(width: 52)
            if model.needsGlobe {
                SpecialKey(systemImage: "globe", label: "পরের কিবোর্ড", action: onGlobe).frame(width: 44)
            }
            micKey.frame(width: 56)
            LetterKey(label: "স্পেস", insert: false) { onInsert(" ") }
            SpecialKey(text: "।", label: "দাঁড়ি") { onInsert("।") }.frame(width: 40)
            SpecialKey(systemImage: "return", label: "নতুন লাইন", action: onReturn).frame(width: 52)
        }
    }

    private var micKey: some View {
        Button {
            UIDevice.current.playInputClick()
            onMic()
        } label: {
            Image(systemName: model.phase == .recording ? "stop.fill" : "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Brand.micGradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(model.hasFullAccess ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .transcribing)
        .accessibilityLabel(model.phase == .recording ? "থামুন" : "বলুন")
    }

    /// While dictating: one big button to stop, with the live level.
    private var bigMic: some View {
        Button(action: bigMicTapped) {
            ZStack {
                Circle()
                    .fill(Brand.violetLight.opacity(0.25))
                    .scaleEffect(model.phase == .recording ? 1 + CGFloat(model.level) * 0.45 : 1)
                    .animation(.easeOut(duration: 0.1), value: model.level)
                Circle().fill(Brand.micGradient).padding(9)
                if model.phase == .transcribing {
                    VStack(spacing: 2) {
                        ProgressView().tint(.white)
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                } else {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 92, height: 92)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.phase == .recording ? "থামুন" : "লেখা বাতিল করুন")
    }

    /// Recording: stop. Writing: cancel, unless the model is still loading
    /// (that load is never cancelled; it goes on in the background).
    private func bigMicTapped() {
        guard model.phase == .transcribing else { return onMic() }
        if model.modelLoading {
            model.message = "মডেল লোড পেছনে চলছে, শেষ হলে লেখা আসবে"
        } else {
            onCancel()
        }
    }

    private var status: String {
        if let m = model.message { return m }
        if !model.hasFullAccess {
            return "মাইক ব্যবহারে Settings-এ কথন → Allow Full Access চালু করুন"
        }
        if model.modelLoading, model.phase != .recording {
            if model.modelPreparing { return "কথন প্রস্তুত হচ্ছে… একটু অপেক্ষা করুন" }
            return "মডেল লোড হচ্ছে… প্রথমবার একটু সময় লাগে"
        }
        switch model.phase {
        case .off: return "মাইক চাপুন, কথন খুলে শুনতে শুরু করবে"
        case .ready: return "মাইক চাপুন, তারপর বলুন"
        case .recording: return "শুনছি… শেষ হলে থামুন চাপুন"
        case .transcribing: return "লিখছি… বাতিল করতে বোতামে চাপুন"
        }
    }
}

// MARK: Keys

private let keyCorner: CGFloat = 8

/// A letter: Noto Sans Bengali on the system key color.
private struct LetterKey: View {
    let label: String
    var insert = true
    let action: () -> Void

    var body: some View {
        Button {
            UIDevice.current.playInputClick()
            action()
        } label: {
            Text(label)
                .font(.bn(size: insert ? 21 : 15))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: keyCorner, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Shift, ১২৩, 🌐, return: tinted with Kothon's violet.
private struct SpecialKey: View {
    var text: String?
    var systemImage: String?
    var highlighted = false
    let label: String
    let action: () -> Void

    init(text: String, label: String, action: @escaping () -> Void) {
        self.text = text; self.label = label; self.action = action
    }

    init(systemImage: String, highlighted: Bool = false, label: String, action: @escaping () -> Void) {
        self.systemImage = systemImage; self.highlighted = highlighted; self.label = label; self.action = action
    }

    var body: some View {
        Button {
            UIDevice.current.playInputClick()
            action()
        } label: {
            Group {
                if let systemImage { Image(systemName: systemImage) } else { Text(text ?? "") }
            }
            .font(.bn(size: 16, .medium))
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(highlighted ? Brand.violet.opacity(0.45) : Brand.violet.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: keyCorner, style: .continuous))
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Delete repeats while held, like the system keyboard.
private struct RepeatKey: View {
    let systemImage: String
    let action: () -> Void
    @State private var timer: Timer?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(Brand.violet.opacity(0.16), in: RoundedRectangle(cornerRadius: keyCorner, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard timer == nil else { return }
                    UIDevice.current.playInputClick()
                    action()
                    timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in action() }
                    }
                }
                .onEnded { _ in
                    timer?.invalidate()
                    timer = nil
                })
            .accessibilityLabel("মুছুন")
            .accessibilityAddTraits(.isButton)
    }
}
