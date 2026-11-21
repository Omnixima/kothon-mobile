// The Kothon keyboard. It can't record (iOS keeps the microphone away from
// keyboards), so the mic key asks the Kothon app to: directly if a session
// is running in the background, or by opening the app to start one.
//
// The keyboard loads no model and links no engine, so it stays far under
// the ~60 MB memory limit iOS gives keyboards.

import SwiftUI
import UIKit

final class KeyboardModel: ObservableObject {
    @Published var phase: DictationPhase = .off
    @Published var level: Float = 0
    /// The app is still loading the speech model.
    @Published var modelLoading = false
    /// ...and it is the one-time compile after an app update.
    @Published var modelPreparing = false
    @Published var message: String?
    @Published var hasFullAccess = true
    /// Developer mode in the app: tint each key's tap area.
    @Published var showHitAreas = false
    @Published var needsGlobe = true
}

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var shared: UserDefaults { KothonShared.defaults }
    private var lastResultID = 0
    /// True between our start signal and the result, so a result made by
    /// dictating inside the app isn't typed into this text field.
    private var awaitingResult = false
    /// The error count when this dictation was asked for: only a newer
    /// error belongs to it.
    private var lastErrorID = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = KeyboardView(
            model: model,
            onMic: { [weak self] in self?.micTapped() },
            onCancel: { [weak self] in self?.cancelTapped() },
            onInsert: { [weak self] in self?.textDocumentProxy.insertText($0) },
            onSpace: { [weak self] in self?.space(bengali: $0) },
            onDelete: { [weak self] in self?.textDocumentProxy.deleteBackward() },
            onReturn: { [weak self] in self?.textDocumentProxy.insertText("\n") },
            onGlobe: { [weak self] in self?.advanceToNextInputMode() })
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.heightAnchor.constraint(equalToConstant: 262),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        model.showHitAreas = shared.bool(forKey: SharedKey.devHitAreas)
        // Tells the app's setup screen that the keyboard is added and has
        // Full Access (the App Group is only writable with Full Access).
        markFullAccess()
        model.needsGlobe = needsInputModeSwitchKey
        lastResultID = shared.integer(forKey: SharedKey.resultID)
        lastErrorID = shared.integer(forKey: SharedKey.errorID)
        // Coming back from the app after it started recording for us.
        if shared.bool(forKey: SharedKey.startOnOpen) {
            shared.set(false, forKey: SharedKey.startOnOpen)
            awaitingResult = true
            // Errors since the mic tap that opened the app belong to it.
            lastErrorID = shared.integer(forKey: "startErrorID")
        }
        DarwinCenter.shared.observe(.changed) { [weak self] in self?.refresh() }
        refresh()
    }

    /// Tells the app's setup checklist that the keyboard runs with Full
    /// Access (the App Group is only writable then).
    private func markFullAccess() {
        model.hasFullAccess = hasFullAccess
        guard hasFullAccess else { return }
        shared.set(Date().timeIntervalSince1970, forKey: SharedKey.keyboardFullAccessSeen)
        shared.synchronize()
        DarwinCenter.shared.post(.changed)
    }

    /// Ask iOS to let the keys have touches at the screen edges first.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.left, .right, .bottom] }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        removeSystemTouchDelays()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // hasFullAccess can read false this early in viewWillAppear; mark again.
        markFullAccess()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        removeSystemTouchDelays()
    }

    /// iOS adds its edge and home-indicator gesture recognizers to the
    /// keyboard's window; stop them delaying touches to the keys (see KeyGrid).
    private func removeSystemTouchDelays() {
        var v: UIView? = view
        while let current = v {
            for g in current.gestureRecognizers ?? [] {
                g.delaysTouchesBegan = false
                g.delaysTouchesEnded = false
            }
            v = current.superview
        }
        view.window?.gestureRecognizers?.forEach {
            $0.delaysTouchesBegan = false
            $0.delaysTouchesEnded = false
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DarwinCenter.shared.removeAll()
    }

    // MARK: Actions

    private func micTapped() {
        guard hasFullAccess else {
            model.message = "সেটিংসে কথন কিবোর্ডের \"Allow Full Access\" চালু করুন"
            return
        }
        model.message = nil
        switch (shared.sessionAlive, shared.dictationPhase) {
        case (true, .recording):
            DarwinCenter.shared.post(.stop)
            model.phase = .transcribing
        case (true, .ready):
            awaitingResult = true
            lastResultID = shared.integer(forKey: SharedKey.resultID)
            lastErrorID = shared.integer(forKey: SharedKey.errorID)
            DarwinCenter.shared.post(.start)
            model.phase = .recording
        case (true, .transcribing):
            break
        default:
            // No session: open the app, which starts one and begins recording.
            shared.set(true, forKey: SharedKey.startOnOpen)
            shared.set(shared.integer(forKey: SharedKey.errorID), forKey: "startErrorID")
            awaitingResult = true
            lastResultID = shared.integer(forKey: SharedKey.resultID)
            lastErrorID = shared.integer(forKey: SharedKey.errorID)
            openApp(KothonShared.dictateURL) { [weak self] opened in
                guard let self, !opened else { return }
                self.shared.set(false, forKey: SharedKey.startOnOpen)
                self.awaitingResult = false
                self.model.message = "কথন অ্যাপ খুলে মাইক চাপুন"
            }
        }
    }

    private func cancelTapped() {
        awaitingResult = false
        DarwinCenter.shared.post(.cancel)
        model.phase = .ready
    }

    private func refresh() {
        let alive = shared.sessionAlive
        model.phase = alive ? shared.dictationPhase : .off
        model.level = shared.float(forKey: SharedKey.level)
        model.modelLoading = alive && shared.bool(forKey: SharedKey.modelLoading)
        model.modelPreparing = model.modelLoading && shared.bool(forKey: SharedKey.modelPreparing)

        let id = shared.integer(forKey: SharedKey.resultID)
        if id != lastResultID {
            lastResultID = id
            if awaitingResult, let text = shared.string(forKey: SharedKey.resultText), !text.isEmpty {
                insert(text)
            }
            awaitingResult = false
        }
        let errorID = shared.integer(forKey: SharedKey.errorID)
        if errorID != lastErrorID {
            lastErrorID = errorID
            if awaitingResult, let err = shared.string(forKey: SharedKey.errorText), model.phase != .recording {
                model.message = err
                awaitingResult = false
            }
        }
    }

    private var lastSpace = Date.distantPast

    /// Space, or "। " / ". " for a quick double space after a word, like
    /// the system keyboard. Not after a digit or punctuation.
    private func space(bengali: Bool) {
        let now = Date()
        defer { lastSpace = now }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if now.timeIntervalSince(lastSpace) < 0.6, before.hasSuffix(" "),
           let prev = before.dropLast().last,
           !prev.isWhitespace, !prev.isPunctuation, !prev.isNumber, !prev.isSymbol {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(bengali ? "। " : ". ")
            lastSpace = .distantPast
            return
        }
        textDocumentProxy.insertText(" ")
    }

    /// Insert with a space between dictations, as people expect.
    private func insert(_ text: String) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let needsSpace = !before.isEmpty && !(before.last?.isWhitespace ?? true)
        textDocumentProxy.insertText((needsSpace ? " " : "") + text)
    }

    /// Keyboards can't open URLs through the public API, so walk the
    /// responder chain to the app and call open(_:options:completionHandler:)
    /// through the runtime, the way Wispr Flow and others do. `done` gets
    /// false if that isn't possible or iOS refuses, so the keyboard can say so.
    private func openApp(_ url: URL, done: @escaping (Bool) -> Void) {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: selector), r.isKind(of: NSClassFromString("UIApplication")!) {
                typealias OpenURL = @convention(c) (
                    AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
                ) -> Void
                let imp = r.method(for: selector)
                let open = unsafeBitCast(imp, to: OpenURL.self)
                let completion: @convention(block) (Bool) -> Void = { ok in
                    DispatchQueue.main.async { done(ok) }
                }
                open(r, selector, url as NSURL, NSDictionary(), completion)
                return
            }
            responder = r.next
        }
        done(false)
    }
}
