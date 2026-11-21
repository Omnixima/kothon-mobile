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
    /// Space; a quick second space becomes "। " or ". " (true = Bengali).
    let onSpace: (Bool) -> Void
    let onDelete: () -> Void
    let onReturn: () -> Void
    let onGlobe: () -> Void

    @State private var language: Language = KeyboardPrefs.language
    @State private var layer: Layer = .letters
    @State private var lastShiftTap = Date.distantPast
    @State private var recents: [String] = KeyboardPrefs.recents
    @State private var emojiCategory = "recent"
    /// The talking screen stays up between dictations until the user goes
    /// back to the letters.
    @State private var talkMode = UserDefaults.standard.bool(forKey: "talkMode")

    /// Each key row is 50 pt tall; the key face is inset, so taps between
    /// keys still land on one.
    private static let rowHeight: CGFloat = 50
    private static let rowsHeight: CGFloat = 3 * rowHeight
    private var dictating: Bool { model.phase == .recording || model.phase == .transcribing }

    var body: some View {
        VStack(spacing: 6) {
            if talkMode {
                talkPanel
            } else {
                VStack(spacing: 0) {
                    DictatePill(phase: model.phase, enabled: model.hasFullAccess, status: status) { pillTapped() }
                    if layer == .emoji {
                        VStack(spacing: 0) {
                            emojiPanel.frame(height: Self.rowsHeight)
                            emojiBottomRow
                        }
                        .padding(.top, 6)
                    } else {
                        // All typing keys, one UIKit view (see KeyGrid). The
                        // 6 pt gap under the button belongs to the first row.
                        KeyGrid(rows: gridRows, topGap: 6, showHitAreas: model.showHitAreas, onKey: keyTapped)
                            .frame(height: 6 + Self.rowsHeight + Self.rowHeight)
                    }
                }
            }
        }
        .padding(.horizontal, 1)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // MARK: Talking screen

    /// Speak, see it typed, speak again. Stays until "কিবোর্ড" is tapped,
    /// which works in every state (a model load goes on in the background).
    private var talkPanel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                BrandMark(size: 24)
                if model.modelLoading && model.phase != .recording {
                    // The one-time Neural Engine prepare: say it plainly.
                    VStack(alignment: .leading, spacing: 1) {
                        Text("মডেল লোড হচ্ছে, একটু অপেক্ষা করুন…")
                            .font(.bn(.subheadline, .semibold))
                            .foregroundStyle(.primary)
                        Text(model.modelPreparing ? "প্রথমবার ১-২ মিনিট লাগতে পারে, পরের বার এত সময় লাগবে না।" : "কয়েক সেকেন্ড")
                            .font(.bn(.caption))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(status.isEmpty ? "চাপুন আর বাংলায় বলুন" : status)
                        .font(.bn(.footnote, .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if model.phase == .recording || (model.phase == .transcribing && !model.modelLoading) {
                    Button("বাতিল", action: onCancel).font(.bn(.footnote, .medium))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            VStack(spacing: 0) {
                bigMic.frame(maxWidth: .infinity).frame(height: Self.rowsHeight)
                HStack(spacing: 0) {
                    SpecialKey(systemImage: "keyboard", label: "কিবোর্ড") { setTalkMode(false) }
                        .frame(width: 48)
                    SpecialKey(systemImage: "face.smiling", label: "ইমোজি") {
                        setTalkMode(false)
                        emojiCategory = recents.isEmpty ? "faces" : "recent"
                        layer = .emoji
                    }
                    .frame(width: 46)
                    SpecialKey(text: ",", label: "কমা") { onInsert(",") }.frame(width: 40)
                    LetterKey(label: language == .bengali ? "স্পেস" : "space", insert: false) {
                        onSpace(language == .bengali)
                    }
                    SpecialKey(text: language == .bengali ? "।" : ".", label: "দাঁড়ি") {
                        onInsert(language == .bengali ? "।" : ".")
                    }
                    .frame(width: 40)
                    SpecialKey(text: "?", label: "প্রশ্নবোধক চিহ্ন") { onInsert("?") }.frame(width: 40)
                    RepeatKey(systemImage: "delete.left", action: onDelete).frame(width: 48)
                    SpecialKey(systemImage: "return", label: "নতুন লাইন", action: onReturn).frame(width: 48)
                }
                .frame(height: Self.rowHeight)
            }
        }
    }

    private func pillTapped() {
        guard model.hasFullAccess else { return onMic() }  // explains Full Access
        setTalkMode(true)
        if model.phase == .transcribing { bigMicTapped() } else { onMic() }
    }

    private func setTalkMode(_ on: Bool) {
        talkMode = on
        UserDefaults.standard.set(on, forKey: "talkMode")
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

    // MARK: Key grid

    /// The four rows of the current layer, for KeyGrid.
    private var gridRows: [KeyRow] {
        let g = grid
        let lettersLayer = layer == .letters || layer == .shifted || layer == .capsLock
        func letters(_ keys: [String]) -> [KeySpec] { keys.map { KeySpec(id: "ch:" + $0, label: $0) } }

        var third: [KeySpec] = []
        switch (language, layer) {
        case (.bengali, .numbers), (.bengali, .symbols):
            third.append(KeySpec(id: "none", style: .blank, width: .fixed(48), accessibility: ""))
        case (.english, .numbers):
            third.append(KeySpec(id: "symbols", label: "#+=", style: .special, width: .fixed(48), accessibility: "আরও চিহ্ন"))
        case (.english, .symbols):
            third.append(KeySpec(id: "numbers", label: "123", style: .special, width: .fixed(48), accessibility: "সংখ্যা"))
        default:
            third.append(KeySpec(id: "shift",
                                 symbol: layer == .capsLock ? "capslock.fill" : layer == .shifted ? "shift.fill" : "shift",
                                 style: layer == .letters ? .special : .specialOn, width: .fixed(48),
                                 accessibility: layer == .capsLock ? "ক্যাপস লক" : "শিফট"))
        }
        third += letters(g[2])
        third.append(KeySpec(id: "del", symbol: "delete.left", style: .special, width: .fixed(48), repeats: true, accessibility: "মুছুন"))

        let numbersShown = layer == .numbers || layer == .symbols
        var bottom: [KeySpec] = [
            KeySpec(id: "layer", label: numbersShown ? (language == .bengali ? "কখগ" : "ABC") : (language == .bengali ? "১২৩" : "123"),
                    style: .special, width: .fixed(50), accessibility: numbersShown ? "অক্ষর" : "সংখ্যা"),
            KeySpec(id: "lang", label: language == .bengali ? "ABC" : "কখগ", style: .special, width: .fixed(50),
                    accessibility: language == .bengali ? "ইংরেজি কিবোর্ড" : "বাংলা কিবোর্ড"),
            KeySpec(id: "emoji", symbol: "face.smiling", style: .special, width: .fixed(46), accessibility: "ইমোজি"),
        ]
        if model.needsGlobe {
            bottom.append(KeySpec(id: "globe", symbol: "globe", style: .special, width: .fixed(46), accessibility: "পরের কিবোর্ড"))
        }
        bottom += [
            KeySpec(id: "space", label: language == .bengali ? "স্পেস" : "space", style: .space),
            KeySpec(id: "stop", label: language == .bengali ? "।" : ".", style: .special, width: .fixed(42), accessibility: "দাঁড়ি"),
            KeySpec(id: "return", symbol: "return", style: .special, width: .fixed(52), accessibility: "নতুন লাইন"),
        ]
        return [
            KeyRow(keys: letters(g[0])),
            KeyRow(keys: letters(g[1]), inset: language == .english && lettersLayer ? 18 : 0),
            KeyRow(keys: third),
            KeyRow(keys: bottom),
        ]
    }

    private func keyTapped(_ id: String) {
        // Compare Unicode scalars, not Characters: a vowel sign (া, ি …)
        // combines with the ":" before it into one Character, so
        // hasPrefix("ch:") would be false for those keys.
        let scalars = id.unicodeScalars
        if scalars.starts(with: "ch:".unicodeScalars) {
            onInsert(String(String.UnicodeScalarView(scalars.dropFirst(3))))
            // Shift is for one letter, like the system keyboard.
            if layer == .shifted { layer = .letters }
            return
        }
        switch id {
        case "shift": shiftTapped()
        case "del": onDelete()
        case "symbols": layer = .symbols
        case "numbers": layer = .numbers
        case "layer": layer = (layer == .numbers || layer == .symbols) ? .letters : .numbers
        case "lang": switchLanguage()
        case "emoji":
            emojiCategory = recents.isEmpty ? "faces" : "recent"
            layer = .emoji
        case "globe": onGlobe()
        case "space":
            onSpace(language == .bengali)
            if layer == .numbers || layer == .symbols { layer = .letters }
        case "stop": onInsert(language == .bengali ? "।" : ".")
        case "return": onReturn()
        default: break
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

    /// Under the emoji panel: back to letters, the category tabs, delete.
    private var emojiBottomRow: some View {
        HStack(spacing: 0) {
            SpecialKey(text: language == .bengali ? "কখগ" : "ABC", label: "অক্ষর") { layer = .letters }
                .frame(width: 54)
            emojiTabs
            RepeatKey(systemImage: "delete.left", action: onDelete).frame(width: 48)
        }
        .frame(height: Self.rowHeight)
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
                if model.phase == .transcribing && model.modelLoading {
                    // Waiting for the model: nothing to cancel here.
                    ProgressView().tint(.white).controlSize(.large)
                } else if model.phase == .transcribing {
                    VStack(spacing: 2) {
                        ProgressView().tint(.white)
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                } else if model.phase == .recording {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Image("KothonMark").resizable().scaledToFit().frame(width: 44)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 92, height: 92)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.phase == .recording ? "থামুন"
                            : model.phase == .transcribing ? "লেখা বাতিল করুন" : "কথন-এ বলুন")
    }

    /// Recording: stop. Writing: cancel, unless the model is still loading
    /// (that load is never cancelled; it goes on in the background).
    private func bigMicTapped() {
        guard model.phase == .transcribing else { return onMic() }
        if model.modelLoading {
            model.message = "মডেল লোড হচ্ছে, একটু অপেক্ষা করুন…"
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
            if model.modelPreparing { return "মডেল লোড হচ্ছে, একটু অপেক্ষা করুন… প্রথমবার ১-২ মিনিট লাগতে পারে, পরের বার এত সময় লাগবে না।" }
            return "মডেল লোড হচ্ছে, একটু অপেক্ষা করুন…"
        }
        switch model.phase {
        case .off, .ready: return ""
        case .recording: return "শুনছি… শেষ হলে থামুন"
        // The button says "লিখছি…" with a spinner; don't say it twice.
        case .transcribing: return "বাতিল করতে বোতামে চাপুন"
        }
    }
}

// MARK: Keys

private let keyCorner: CGFloat = 8

/// Kothon dictation: a full-width purple button with the Kothon mark,
/// "কথন-এ বলুন", and the status under it when there is one.
private struct DictatePill: View {
    let phase: DictationPhase
    let enabled: Bool
    let status: String
    let action: () -> Void

    var body: some View {
        Button {
            UIDevice.current.playInputClick()
            action()
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if phase == .transcribing {
                        ProgressView().tint(.white).frame(width: 26, height: 21)
                    } else {
                        Image("KothonMark").resizable().scaledToFit().frame(width: 26, height: 21)
                    }
                    Text(phase == .recording ? "থামুন" : phase == .transcribing ? "লিখছি…" : "কথন-এ বলুন")
                        .font(.bn(size: 17, .semibold))
                }
                if !status.isEmpty {
                    Text(status).font(.bn(size: 11)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Brand.micGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(enabled ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .accessibilityLabel(phase == .recording ? "থামুন" : "কথন-এ বলুন")
    }
}

/// Fires on touch-down, like the system keyboard, so fast typing and
/// rollover (a second finger landing before the first lifts) never drop a
/// key. Each key tracks only its own touch.
private struct TouchDownKey: ViewModifier {
    let action: () -> Void
    @Binding var pressed: Bool

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    action()
                    UIDevice.current.playInputClick()
                }
                .onEnded { _ in pressed = false })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// A letter: Noto Sans Bengali on the system key color. The whole cell is
/// tappable; the face is inset by the gap between keys.
private struct LetterKey: View {
    let label: String
    var insert = true
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Text(label)
            .font(.bn(size: insert ? 21 : 15))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(pressed ? Color(.systemGray3) : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: keyCorner, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
            .foregroundStyle(.primary)
            .padding(.horizontal, 2.5)
            .padding(.vertical, 4)
            .modifier(TouchDownKey(action: action, pressed: $pressed))
            .accessibilityLabel(label)
    }
}

/// Shift, ১২৩, ABC, 🌐, return: tinted with Kothon's violet.
private struct SpecialKey: View {
    var text: String?
    var systemImage: String?
    var highlighted = false
    let label: String
    let action: () -> Void
    @State private var pressed = false

    init(text: String, label: String, action: @escaping () -> Void) {
        self.text = text; self.label = label; self.action = action
    }

    init(text: String? = nil, systemImage: String, highlighted: Bool = false, label: String, action: @escaping () -> Void) {
        self.text = text; self.systemImage = systemImage; self.highlighted = highlighted; self.label = label; self.action = action
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            if let text { Text(text) }
        }
        .font(.bn(size: 15, .medium))
        .minimumScaleFactor(0.7)
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pressed || highlighted ? Brand.violet.opacity(0.45) : Brand.violet.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: keyCorner, style: .continuous))
        .foregroundStyle(.primary)
        .padding(.horizontal, 2.5)
        .padding(.vertical, 4)
        .modifier(TouchDownKey(action: action, pressed: $pressed))
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(timer != nil ? Brand.violet.opacity(0.45) : Brand.violet.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: keyCorner, style: .continuous))
            .padding(.horizontal, 2.5)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard timer == nil else { return }
                    action()
                    UIDevice.current.playInputClick()
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
            .accessibilityAction { action() }
    }
}
