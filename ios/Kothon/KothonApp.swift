import AVFoundation
import SwiftUI

@main
struct KothonApp: App {
    @StateObject private var dictation = DictationService.shared
    @StateObject private var models = ModelStore.shared
    /// Set when the keyboard opened the app to start dictating.
    @State private var fromKeyboard = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView()
                if fromKeyboard {
                    HandOffView { fromKeyboard = false }
                        .transition(.opacity)
                }
            }
            .environmentObject(dictation)
            .environmentObject(models)
            .tint(Color.accentColor)
            .onOpenURL { url in
                guard url.scheme == "kothon", url.host == "dictate" else { return }
                fromKeyboard = true
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
