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
    @Published var message: String?
    @Published var hasFullAccess = true
    @Published var needsGlobe = true
}

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var shared: UserDefaults { KothonShared.defaults }
    private var lastResultID = 0
    /// True between our start signal and the result, so a result made by
    /// dictating inside the app isn't typed into this text field.
    private var awaitingResult = false

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = KeyboardView(
            model: model,
            onMic: { [weak self] in self?.micTapped() },
            onCancel: { [weak self] in self?.cancelTapped() },
            onInsert: { [weak self] in self?.textDocumentProxy.insertText($0) },
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
            host.view.heightAnchor.constraint(equalToConstant: 236),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        model.needsGlobe = needsInputModeSwitchKey
        lastResultID = shared.integer(forKey: SharedKey.resultID)
        // Coming back from the app after it started recording for us.
        if shared.bool(forKey: SharedKey.startOnOpen) {
            shared.set(false, forKey: SharedKey.startOnOpen)
            awaitingResult = true
        }
        DarwinCenter.shared.observe(.changed) { [weak self] in self?.refresh() }
        refresh()
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
            DarwinCenter.shared.post(.start)
            model.phase = .recording
        case (true, .transcribing):
            break
        default:
            // No session: open the app, which starts one and begins recording.
            shared.set(true, forKey: SharedKey.startOnOpen)
            awaitingResult = true
            lastResultID = shared.integer(forKey: SharedKey.resultID)
            if !openApp(KothonShared.dictateURL) {
                model.message = "কথন অ্যাপ খুলে মাইক চাপুন"
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

        let id = shared.integer(forKey: SharedKey.resultID)
        if id != lastResultID {
            lastResultID = id
            if awaitingResult, let text = shared.string(forKey: SharedKey.resultText), !text.isEmpty {
                insert(text)
            }
            awaitingResult = false
        }
        if awaitingResult, let err = shared.string(forKey: SharedKey.errorText), model.phase != .recording {
            model.message = err
            awaitingResult = false
        }
    }

    /// Insert with a space between dictations, as people expect.
    private func insert(_ text: String) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let needsSpace = !before.isEmpty && !(before.last?.isWhitespace ?? true)
        textDocumentProxy.insertText((needsSpace ? " " : "") + text)
    }

    /// Keyboards can't open URLs through the public API, so walk the
    /// responder chain to the app and call open(_:options:completionHandler:)
    /// through the runtime, the way Wispr Flow and others do.
    private func openApp(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: selector), r.isKind(of: NSClassFromString("UIApplication")!) {
                typealias OpenURL = @convention(c) (
                    AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
                ) -> Void
                let imp = r.method(for: selector)
                let open = unsafeBitCast(imp, to: OpenURL.self)
                open(r, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = r.next
        }
        return false
    }
}
