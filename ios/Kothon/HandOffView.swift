// Shown when the keyboard opened the app to start dictating. Recording has
// already started; the user swipes back to the app they were typing in
// (the "◀ app name" link at the top left), where the keyboard shows the
// recording and inserts the text.

import SwiftUI

struct HandOffView: View {
    @EnvironmentObject var dictation: DictationService
    let close: () -> Void

    var body: some View {
        ZStack {
            KothonBackdrop()
            VStack(spacing: 28) {
                HStack {
                    Image(systemName: "arrow.up.backward")
                        .font(.bn(.title2, .semibold))
                        .foregroundStyle(Brand.lilac)
                    Text("উপরের বাঁ কোণের লিংকে চেপে আগের অ্যাপে ফিরে যান")
                        .font(.bn(.subheadline))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                Wordmark(height: 48)
                MicButton(phase: dictation.phase, level: dictation.level, size: 120) {
                    if dictation.phase == .recording { dictation.stopRecording() }
                    else if dictation.phase == .ready { dictation.startRecording() }
                }
                Text(title).font(.bn(.title2, .semibold))
                Text("কথন এখন পেছনে শুনছে। আগের অ্যাপে ফিরে গিয়ে কথা বলুন, তারপর কিবোর্ডে থামুন চাপুন, লেখা চলে আসবে।")
                    .font(.bn(.body)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if let err = dictation.lastError {
                    Text(err).font(.bn(.footnote)).foregroundStyle(.red)
                }

                Spacer()
                Button("কথন অ্যাপেই থাকুন", action: close).buttonStyle(.bordered)
                    .padding(.bottom, 24)
            }
        }
    }

    private var title: String {
        switch dictation.phase {
        case .recording: return "শুনছি…"
        case .transcribing: return "লিখছি…"
        case .ready: return "প্রস্তুত"
        case .off: return "মাইক্রোফোন চালু হয়নি"
        }
    }
}
