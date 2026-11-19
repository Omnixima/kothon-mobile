// The keyboard: Bengali and English layouts, emoji, and Kothon dictation.
// Typing works without Full Access; only dictation needs it (to hand the
// text over from the app).
//
// Dictation starts from the purple "কথন-এ বলুন" pill in the top bar, with
// the Kothon mark, so it can't be mistaken for Apple's grey dictation mic
// that iOS draws under every keyboard. While dictating, the letter rows
// give way to a big stop button.
//
// The Bengali layout is Kothon's own, arranged by frequency: vowel signs
// and common consonants on the base layer, independent vowels and the rest
// on shift, Bengali digits and punctuation on ১২৩.

import SwiftUI

private enum Language: String { case bengali, english }

private enum Layer: Equatable {
    case letters        // Bengali or English letters
    case shifted        // Bengali shift, or English one-letter shift
    case capsLock       // English only
    case numbers
    case symbols        // English #+=
    case emoji
}

private enum Layout {
    static let bnLetters: [[String]] = [
        ["া", "ি", "ী", "ু", "ূ", "ৃ", "ে", "ৈ", "ো", "ৌ"],
        ["ক", "খ", "গ", "চ", "জ", "ট", "ড", "ত", "দ", "ন", "ব"],
        ["প", "ম", "য", "র", "ল", "শ", "স", "হ", "্"],
    ]
    static let bnShifted: [[String]] = [
        ["অ", "আ", "ই", "ঈ", "উ", "ঊ", "ঋ", "এ", "ঐ", "ও", "ঔ"],
        ["ঘ", "ঙ", "ছ", "ঝ", "ঞ", "ঠ", "ঢ", "ণ", "থ", "ধ", "ফ"],
        ["ভ", "ষ", "ড়", "ঢ়", "য়", "ৎ", "ং", "ঃ", "ঁ"],
    ]
    static let bnNumbers: [[String]] = [
        ["১", "২", "৩", "৪", "৫", "৬", "৭", "৮", "৯", "০"],
        ["-", "/", ":", ";", "(", ")", "৳", "\"", "'", "@"],
        ["।", ",", "?", "!", ".", "…"],
    ]
    static let enLetters: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]
    static let enNumbers: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]
    static let enSymbols: [[String]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
        [".", ",", "?", "!", "'"],
    ]
}

/// Keyboard-only preferences, kept in the keyboard's own defaults so they
/// work without Full Access.
private enum KeyboardPrefs {
    static let defaults = UserDefaults.standard
    static let languageKey = "keyboardLanguage"
    static let recentsKey = "recentEmoji"

    static var language: Language {
        get { Language(rawValue: defaults.string(forKey: languageKey) ?? "") ?? .bengali }
        set { defaults.set(newValue.rawValue, forKey: languageKey) }
    }

    static var recents: [String] {
        get { defaults.stringArray(forKey: recentsKey) ?? [] }
        set { defaults.set(Array(newValue.prefix(24)), forKey: recentsKey) }
    }
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let onMic: () -> Void
    let onCancel: () -> Void
    let onInsert: (String) -> Void
    let onDelete: () -> Void
    let onReturn: () -> Void
    let onGlobe: () -> Void

    @State private var language: Language = KeyboardPrefs.language
    @State private var layer: Layer = .letters
    @State private var lastShiftTap = Date.distantPast
    @State private var recents: [String] = KeyboardPrefs.recents
    @State private var emojiCategory = "recent"

    private static let rowsHeight: CGFloat = 3 * 42 + 2 * 8
    private var dictating: Bool { model.phase == .recording || model.phase == .transcribing }

    var body: some View {
        VStack(spacing: 8) {
            topBar
            if dictating {
                bigMic.frame(maxWidth: .infinity).frame(height: Self.rowsHeight)
            } else if layer == .emoji {
                emojiPanel.frame(height: Self.rowsHeight)
            } else {
                rows
            }
            bottomRow
        }
        .padding(.horizontal, 3)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            DictatePill(phase: model.phase, enabled: model.hasFullAccess) {
                if model.phase == .transcribing { bigMicTapped() } else { onMic() }
            }
            Text(status)
                .font(.bn(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if model.phase == .recording || (model.phase == .transcribing && !model.modelLoading) {
                Button("বাতিল", action: onCancel).font(.bn(.footnote, .medium))
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
    }

    // MARK: Letter rows

    private var grid: [[String]] {
        switch (language, layer) {
        case (.bengali, .shifted), (.bengali, .capsLock): Layout.bnShifted
        case (.bengali, .numbers), (.bengali, .symbols): Layout.bnNumbers
        case (.bengali, _): Layout.bnLetters
        case (.english, .numbers): Layout.enNumbers
        case (.english, .symbols): Layout.enSymbols
        case (.english, .shifted), (.english, .capsLock): Layout.enLetters.map { $0.map { $0.uppercased() } }
        case (.english, _): Layout.enLetters
        }
    }

    private var rows: some View {
        let g = grid
        return VStack(spacing: 8) {
            row(g[0])
            if language == .english && (layer == .letters || layer == .shifted || layer == .capsLock) {
                // QWERTY's middle row is inset, as people expect.
                row(g[1]).padding(.horizontal, 18)
            } else {
                row(g[1])
            }
            HStack(spacing: 5) {
                leftOfThirdRow.frame(width: 44)
                row(g[2])
                RepeatKey(systemImage: "delete.left", action: onDelete).frame(width: 44)
            }
        }
    }

    @ViewBuilder private var leftOfThirdRow: some View {
        switch (language, layer) {
        case (.bengali, .numbers), (.bengali, .symbols):
            Color.clear
        case (.english, .numbers):
            SpecialKey(text: "#+=", label: "আরও চিহ্ন") { layer = .symbols }
        case (.english, .symbols):
            SpecialKey(text: "123", label: "সংখ্যা") { layer = .numbers }
        default:
            SpecialKey(systemImage: layer == .capsLock ? "capslock.fill" : layer == .shifted ? "shift.fill" : "shift",
                       highlighted: layer != .letters,
                       label: layer == .capsLock ? "ক্যাপস লক" : "শিফট") { shiftTapped() }
        }
    }

    private func shiftTapped() {
        let now = Date()
        defer { lastShiftTap = now }
        switch layer {
        case .letters:
            layer = .shifted
        case .shifted:
            // A quick second tap locks capitals (English only).
            if language == .english && now.timeIntervalSince(lastShiftTap) < 0.35 {
                layer = .capsLock
            } else {
                layer = .letters
            }
        default:
            layer = .letters
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

    // MARK: Emoji

    private var emojiPanel: some View {
        let cats = EmojiData.categories
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 4), spacing: 4) {
                    // The first emoji of each group carries the group's id, for the tabs.
                    ForEach(Array(recents.enumerated()), id: \.offset) { i, e in
                        emojiKey(e).id(i == 0 ? "recent" : "recent-\(i)")
                    }
                    ForEach(cats) { cat in
                        ForEach(Array(cat.emoji.enumerated()), id: \.offset) { i, e in
                            emojiKey(e).id(i == 0 ? cat.id : "\(cat.id)-\(i)")
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: emojiCategory) { _, id in
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .leading) }
            }
        }
    }

    private func emojiKey(_ e: String) -> some View {
        Button {
            UIDevice.current.playInputClick()
            onInsert(e)
            var r = recents.filter { $0 != e }
            r.insert(e, at: 0)
            recents = Array(r.prefix(24))
            KeyboardPrefs.recents = recents
        } label: {
            Text(e).font(.system(size: 27)).frame(width: 36, height: 32)
        }
        .buttonStyle(.plain)
    }

    private var emojiTabs: some View {
        HStack(spacing: 0) {
            if !recents.isEmpty { tab("recent", "clock", "সাম্প্রতিক") }
            ForEach(EmojiData.categories) { tab($0.id, $0.symbol, $0.name) }
        }
    }

    private func tab(_ id: String, _ symbol: String, _ name: String) -> some View {
        Button { emojiCategory = id } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(emojiCategory == id ? Brand.violet : .secondary)
                .frame(maxWidth: .infinity, minHeight: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }

    // MARK: Bottom row

    private var bottomRow: some View {
        HStack(spacing: 5) {
            if layer == .emoji {
                SpecialKey(text: language == .bengali ? "কখগ" : "ABC", label: "অক্ষর") { layer = .letters }
                    .frame(width: 52)
                emojiTabs
                RepeatKey(systemImage: "delete.left", action: onDelete).frame(width: 44)
            } else {
                SpecialKey(text: language == .bengali ? "ABC" : "বাং",
                           label: language == .bengali ? "ইংরেজি কিবোর্ড" : "বাংলা কিবোর্ড") { switchLanguage() }
                    .frame(width: 46)
                SpecialKey(text: layer == .numbers || layer == .symbols
                                ? (language == .bengali ? "কখগ" : "ABC")
                                : (language == .bengali ? "১২৩" : "123"),
                           label: layer == .numbers || layer == .symbols ? "অক্ষর" : "সংখ্যা") {
                    layer = (layer == .numbers || layer == .symbols) ? .letters : .numbers
                }
                .frame(width: 46)
                SpecialKey(systemImage: "face.smiling", label: "ইমোজি") {
                    emojiCategory = recents.isEmpty ? "faces" : "recent"
                    layer = .emoji
                }
                .frame(width: 42)
                if model.needsGlobe {
                    SpecialKey(systemImage: "globe", label: "পরের কিবোর্ড", action: onGlobe).frame(width: 42)
                }
                LetterKey(label: language == .bengali ? "স্পেস" : "space", insert: false) {
                    onInsert(" ")
                    if layer == .numbers || layer == .symbols { layer = .letters }
                }
                if language == .bengali {
                    SpecialKey(text: "।", label: "দাঁড়ি") { onInsert("।") }.frame(width: 38)
                } else {
                    SpecialKey(text: ".", label: "দাঁড়ি") { onInsert(".") }.frame(width: 38)
                }
                SpecialKey(systemImage: "return", label: "নতুন লাইন", action: onReturn).frame(width: 48)
            }
        }
    }

    private func switchLanguage() {
        language = language == .bengali ? .english : .bengali
        KeyboardPrefs.language = language
        layer = .letters
    }

    // MARK: Dictation

    /// While dictating: one big button to stop (or cancel while writing),
    /// with the live level.
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
            return "বলতে Settings-এ কথন → Allow Full Access চালু করুন"
        }
        if model.modelLoading, model.phase != .recording {
            if model.modelPreparing { return "কথন প্রস্তুত হচ্ছে… একটু অপেক্ষা করুন" }
            return "মডেল লোড হচ্ছে…"
        }
        switch model.phase {
        case .off, .ready: return ""
        case .recording: return "শুনছি… শেষ হলে থামুন"
        case .transcribing: return "লিখছি…"
        }
    }
}

// MARK: Keys

private let keyCorner: CGFloat = 8

/// Kothon dictation: the mouth mark on a purple pill, "কথন-এ বলুন".
private struct DictatePill: View {
    let phase: DictationPhase
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIDevice.current.playInputClick()
            action()
        } label: {
            HStack(spacing: 6) {
                Image("KothonMark").resizable().scaledToFit().frame(width: 18, height: 15)
                Text(phase == .recording ? "থামুন" : phase == .transcribing ? "লিখছি…" : "কথন-এ বলুন")
                    .font(.bn(size: 14, .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Brand.micGradient, in: Capsule())
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(phase == .recording ? "থামুন" : "কথন-এ বলুন")
    }
}

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

/// Shift, ১২৩, ABC, 🌐, return: tinted with Kothon's violet.
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
            .font(.bn(size: 15, .medium))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
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
