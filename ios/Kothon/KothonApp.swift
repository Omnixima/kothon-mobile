import AVFoundation
import SwiftUI

@main
struct KothonApp: App {
    @StateObject private var dictation = DictationService.shared
    @StateObject private var models = ModelStore.shared
    @Environment(\.scenePhase) private var scenePhase
    /// Set when the keyboard opened the app to start dictating.
    @State private var fromKeyboard = false
    /// The branded launch animation; skipped when the keyboard opened the app.
    @State private var showLaunch = true
    /// The intro slides show once, on first launch. The key changes when the
    /// slides do, so everyone sees the new ones once.
    @AppStorage("introSeen.v2") private var introSeen = false
    /// First run, after the intro: pick a model, then set up the keyboard.
    @AppStorage("modelStepDone") private var modelStepDone = false
    @AppStorage("keyboardStepDone") private var keyboardStepDone = false

    /// Show the model step only to someone with no model and no download.
    private var needsModelStep: Bool {
        !modelStepDone && !SpeechModel.all.contains { models.isInstalled($0) } && models.progress.isEmpty
    }

    /// Show the keyboard step unless the keyboard has already run with Full Access.
    private var needsKeyboardStep: Bool {
        !keyboardStepDone && KothonShared.defaults.double(forKey: SharedKey.keyboardFullAccessSeen) == 0
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView()
                if introSeen && !fromKeyboard && needsModelStep {
                    ModelSetupView(done: { withAnimation(.easeInOut(duration: 0.35)) { modelStepDone = true } })
                        .transition(.opacity)
                        .zIndex(0.8)
                } else if introSeen && !fromKeyboard && !needsModelStep && needsKeyboardStep {
                    KeyboardSetupStep(done: { withAnimation(.easeInOut(duration: 0.35)) { keyboardStepDone = true } })
                        .transition(.opacity)
                        .zIndex(0.8)
                }
                if !introSeen && !fromKeyboard {
                    IntroSlidesView {
                        withAnimation(.easeInOut(duration: 0.35)) { introSeen = true }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
                if showLaunch && !fromKeyboard {
                    LaunchAnimationView {
                        withAnimation(.easeInOut(duration: 0.4)) { showLaunch = false }
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }
                if fromKeyboard {
                    HandOffView { fromKeyboard = false }
                        .transition(.opacity)
                        .zIndex(3)
                }
            }
            .environmentObject(dictation)
            .environmentObject(models)
            .tint(Color.accentColor)
            .font(.bn(.body))
            // Kothon's screens are plum (home design B), so the app is always dark.
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                guard url.scheme == "kothon", url.host == "dictate" else { return }
                // The keyboard only opens the app with Full Access on: tick the checklist.
                UserDefaults.standard.set(true, forKey: "keyboardHandOffSeen")
                fromKeyboard = true
                showLaunch = false
                Task { await startFromKeyboard() }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                // The keyboard hand-off loads the model itself (startRecording).
                if phase == .active { models.resumePendingDownload() }
                if phase == .active && !fromKeyboard { dictation.prepareEngineIfNeeded() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                dictation.unloadEngine()
            }
        }
    }

    private func startFromKeyboard() async {
        guard await Self.microphoneAllowed() else { return }
        // Get the model ready while the person speaks.
        dictation.prepareEngineIfNeeded()
        dictation.startRecording()
    }

    static func microphoneAllowed() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }
}
