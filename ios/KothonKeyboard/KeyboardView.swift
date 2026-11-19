// The keyboard's layout: a big mic key, Bengali punctuation, and the keys
// every keyboard needs. For typing letters, 🌐 switches to the iPhone's
// own Bangla keyboard; a full Bengali layout can come later.

import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let onMic: () -> Void
    let onCancel: () -> Void
    let onInsert: (String) -> Void
    let onDelete: () -> Void
    let onReturn: () -> Void
    let onGlobe: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                BrandMark(size: 20)
                Text(status).font(.bn(.footnote)).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if model.phase == .recording {
                    Button("বাতিল", action: onCancel).font(.bn(.footnote))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer(minLength: 0)
            mic
            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if model.needsGlobe {
                    Key(systemImage: "globe", action: onGlobe).frame(width: 44)
                }
                ForEach(["।", ",", "?"], id: \.self) { mark in
                    Key(label: mark) { onInsert(mark) }.frame(width: 40)
                }
                Key(label: "স্পেস") { onInsert(" ") }
                RepeatKey(systemImage: "delete.left", action: onDelete).frame(width: 52)
                Key(systemImage: "return", action: onReturn).frame(width: 52)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
    }

    private var mic: some View {
        Button(action: onMic) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .scaleEffect(model.phase == .recording ? 1 + CGFloat(model.level) * 0.45 : 1)
                    .animation(.easeOut(duration: 0.1), value: model.level)
                Circle().fill(Color.accentColor).padding(9)
                if model.phase == .transcribing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: model.phase == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 92, height: 92)
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .transcribing)
        .accessibilityLabel(model.phase == .recording ? "থামুন" : "বলুন")
    }

    private var status: String {
        if let m = model.message { return m }
        if model.modelLoading, model.phase != .recording {
            if model.modelPreparing { return "কথন প্রস্তুত হচ্ছে… একটু অপেক্ষা করুন" }
            return "মডেল লোড হচ্ছে… প্রথমবার একটু সময় লাগে"
        }
        switch model.phase {
        case .off: return "মাইক চাপুন, কথন খুলে শুনতে শুরু করবে"
        case .ready: return "মাইক চাপুন, তারপর বলুন"
        case .recording: return "শুনছি… শেষ হলে থামুন চাপুন"
        case .transcribing: return "লিখছি…"
        }
    }
}

private struct Key: View {
    var label: String?
    var systemImage: String?
    let action: () -> Void

    init(label: String, action: @escaping () -> Void) {
        self.label = label; self.action = action
    }

    init(systemImage: String, action: @escaping () -> Void) {
        self.systemImage = systemImage; self.action = action
    }

    var body: some View {
        Button {
            UIDevice.current.playInputClick()
            action()
        } label: {
            Group {
                if let systemImage { Image(systemName: systemImage) } else { Text(label ?? "") }
            }
            .font(.bn(size: 17))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

/// Delete repeats while held, like the system keyboard.
private struct RepeatKey: View {
    let systemImage: String
    let action: () -> Void
    @State private var timer: Timer?

    var body: some View {
        Image(systemName: systemImage)
            .font(.bn(size: 17))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard timer == nil else { return }
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
