import AVFoundation
import SwiftUI

@main
struct KothonApp: App {
    @StateObject private var dictation = DictationService.shared
    @StateObject private var models = ModelStore.shared
    /// Set when the keyboard opened the app to start dictating.
    @State private var fromKeyboard = false
    /// The branded launch animation; skipped when the keyboard opened the app.
    @State private var showLaunch = true
    /// The intro slides show once, on first launch. The key changes when the
    /// slides do, so everyone sees the new ones once.
    @AppStorage("introSeen.v2") private var introSeen = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView()
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
                fromKeyboard = true
                showLaunch = false
                Task { await startFromKeyboard() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                dictation.unloadEngine()
            }
        }
    }

    private func startFromKeyboard() async {
        guard await Self.microphoneAllowed() else { return }
        dictation.startRecording()
    }

    static func microphoneAllowed() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }
}
