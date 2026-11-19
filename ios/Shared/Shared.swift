// Shared between the Kothon app and the Kothon keyboard.
//
// The keyboard can't use the microphone, so dictation runs in the app. The
// two talk through the App Group: small values in shared UserDefaults, and
// Darwin notifications to say "something changed, look now".

import Foundation

enum KothonShared {
    static let appGroup = "group.com.kothon.dictation"
    /// The keyboard opens this to start a session when none is running.
    static let dictateURL = URL(string: "kothon://dictate")!

    static let defaults = UserDefaults(suiteName: appGroup) ?? .standard

    /// A session counts as alive while the app's heartbeat is this fresh.
    static let heartbeatTimeout: TimeInterval = 4
}

/// What the dictation session is doing. The app writes it; the keyboard reads it.
enum DictationPhase: String {
    /// No session: the keyboard must open the app to start one.
    case off
    /// Session running in the background, microphone ready, not recording.
    case ready
    case recording
    case transcribing
}

/// Keys in the shared defaults.
enum SharedKey {
    static let phase = "phase"
    static let heartbeat = "heartbeat"
    static let resultText = "resultText"
    /// Bumped with every new result, so the keyboard inserts each one once.
    static let resultID = "resultID"
    static let errorText = "errorText"
    /// The keyboard sets this before opening the app: start recording right away.
    static let startOnOpen = "startOnOpen"
    /// When the keyboard last ran with Full Access (for the setup checklist).
    static let keyboardFullAccessSeen = "keyboardFullAccessSeen"
    /// Live microphone level 0...1, for the keyboard's meter.
    static let level = "level"
    /// How long the last dictation took, shown in the app.
    static let stats = "stats"
    /// True while the app loads the speech model into memory.
    static let modelLoading = "modelLoading"
    /// True while that load is the one-time Neural Engine compile after an
    /// app update (about 2 minutes).
    static let modelPreparing = "modelPreparing"
}

extension UserDefaults {
    var dictationPhase: DictationPhase {
        get { DictationPhase(rawValue: string(forKey: SharedKey.phase) ?? "") ?? .off }
        set { set(newValue.rawValue, forKey: SharedKey.phase) }
    }

    /// True while the app is running a session (fresh heartbeat).
    var sessionAlive: Bool {
        guard dictationPhase != .off else { return false }
        let beat = double(forKey: SharedKey.heartbeat)
        return Date().timeIntervalSince1970 - beat < KothonShared.heartbeatTimeout
    }
}

/// Signals between the app and the keyboard.
enum KothonSignal: String, CaseIterable {
    /// Keyboard → app
    case start = "com.kothon.dictation.start"
    case stop = "com.kothon.dictation.stop"
    case cancel = "com.kothon.dictation.cancel"
    /// App → keyboard: phase, level or result changed.
    case changed = "com.kothon.dictation.changed"
}

/// Darwin notifications cross the process boundary but carry no payload, so
/// the data itself lives in the shared defaults.
final class DarwinCenter {
    static let shared = DarwinCenter()

    private var handlers: [String: () -> Void] = [:]
    private let lock = NSLock()

    func post(_ signal: KothonSignal) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(signal.rawValue as CFString), nil, nil, true)
    }

    /// Calls `handler` on the main queue each time `signal` is posted.
    func observe(_ signal: KothonSignal, _ handler: @escaping () -> Void) {
        lock.lock()
        let first = handlers[signal.rawValue] == nil
        handlers[signal.rawValue] = handler
        lock.unlock()
        guard first else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, name, _, _ in
                guard let observer, let name else { return }
                let center = Unmanaged<DarwinCenter>.fromOpaque(observer).takeUnretainedValue()
                center.fire(name.rawValue as String)
            },
            signal.rawValue as CFString, nil, .deliverImmediately)
    }

    func removeAll() {
        lock.lock()
        handlers.removeAll()
        lock.unlock()
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque())
    }

    private func fire(_ name: String) {
        lock.lock()
        let handler = handlers[name]
        lock.unlock()
        guard let handler else { return }
        DispatchQueue.main.async(execute: handler)
    }
}

/// Kothon's colors, from the desktop theme (src/styles/theme.css).
enum KothonColor {
    static let purpleLight = (r: 0x7C, g: 0x3A, b: 0xED)
    static let purpleDark = (r: 0xA7, g: 0x8B, b: 0xFA)
    static let plum = (r: 0x3F, g: 0x01, b: 0x59)
}
