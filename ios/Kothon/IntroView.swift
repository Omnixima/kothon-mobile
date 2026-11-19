// First impressions: a short branded launch animation, then (first launch
// only) four slides on how Kothon works and why it's private.

import SwiftUI

// MARK: - Launch animation

/// Design B: five sound bars move like speech, then gather into the mouth on
/// the mic button, and the wordmark rises in. It ends looking like the home
/// screen's mic, so the fade into home is seamless. About 1.9 s; with Reduce
/// Motion it's a plain fade.
struct LaunchAnimationView: View {
    let finished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var talking = false
    @State private var gathered = false
    @State private var markIn = false
    @State private var wordmarkIn = false

    private let barPeaks: [CGFloat] = [26, 46, 60, 40, 30]

    var body: some View {
        ZStack {
            KothonBackdrop()
            VStack(spacing: 30) {
                ZStack {
                    Circle().fill(Brand.violetLight.opacity(0.22))
                        .frame(width: 156, height: 156)
                        .scaleEffect(markIn ? 1 : 0.5)
                        .opacity(markIn ? 1 : 0)
                    Circle().fill(Brand.micGradient)
                        .frame(width: 120, height: 120)
                        .shadow(color: Brand.violet.opacity(0.9), radius: 20, y: 12)
                        .overlay(Image("KothonMark").resizable().scaledToFit()
                            .foregroundStyle(.white).frame(width: 58))
                        .scaleEffect(markIn ? 1 : 0.4)
                        .opacity(markIn ? 1 : 0)
                    HStack(spacing: 7) {
                        ForEach(barPeaks.indices, id: \.self) { i in
                            Capsule()
                                .fill(Brand.lilac)
                                .frame(width: 9, height: gathered ? 6 : (talking ? barPeaks[i] : 14))
                                .animation(reduceMotion ? nil :
                                    .easeInOut(duration: 0.22).repeatCount(3, autoreverses: true)
                                        .delay(Double(i) * 0.06), value: talking)
                        }
                    }
                    .scaleEffect(gathered ? 0.3 : 1)
                    .opacity(gathered ? 0 : 1)
                }
                .frame(width: 160, height: 160)

                VStack(spacing: 10) {
                    Image("KothonWordmark")
                        .resizable().scaledToFit()
                        .frame(height: 40)
                        .foregroundStyle(.white)
                    Text("বলুন, কথন লিখে দিবে।")
                        .font(.bn(.headline, .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .offset(y: wordmarkIn ? 0 : 14)
                .opacity(wordmarkIn ? 1 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("কথন")
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            gathered = true
            withAnimation(.easeOut(duration: 0.3)) { markIn = true; wordmarkIn = true }
            try? await Task.sleep(for: .seconds(0.9))
            finished()
            return
        }
        talking = true
        try? await Task.sleep(for: .seconds(0.85))
        withAnimation(.easeIn(duration: 0.25)) { gathered = true }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.12)) { markIn = true }
        try? await Task.sleep(for: .seconds(0.45))
        withAnimation(.easeOut(duration: 0.45)) { wordmarkIn = true }
        try? await Task.sleep(for: .seconds(0.9))
        finished()
    }
}

// MARK: - Intro slides

/// Design 2: three slides, each with a small animated scene. Shown on first
/// launch, and again from the keyboard sheet's "কীভাবে কাজ করে".
struct IntroSlidesView: View {
    let done: () -> Void
    @State private var page = 0
    private let count = 3

    var body: some View {
        ZStack {
            KothonBackdrop()
            VStack(spacing: 0) {
                HStack {
                    Wordmark(height: 30)
                    Spacer()
                    if page < count - 1 {
                        Button("এড়িয়ে যান", action: done)
                            .font(.bn(.subheadline, .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                TabView(selection: $page) {
                    SlidePage(title: "মাইক চাপুন, বলুন",
                              text: "কথন একটা কিবোর্ড। যেকোনো অ্যাপে বেগুনি মাইক বোতাম চাপুন, বাংলায় বলুন, লেখা নিজেই বসে যাবে।") {
                        ChatScene(active: page == 0)
                    }.tag(0)
                    SlidePage(title: "কিবোর্ড চালু করুন",
                              text: "সেটিংস → জেনারেল → কিবোর্ড → কিবোর্ড যোগ করুন → কথন। তারপর \"Allow Full Access\" চালু করুন, এটা শুধু কথন অ্যাপের সাথে লেখা আদান-প্রদানের জন্য।") {
                        SetupScene(active: page == 1)
                    }.tag(1)
                    SlidePage(title: "সবকিছু আপনার ফোনেই",
                              text: "কথা থেকে লেখা বানানোর পুরো কাজ ফোনের ভেতরেই হয়। আপনার কণ্ঠ বা লেখা কোনো সার্ভারে যায় না, আর মডেল নামানোর পর ইন্টারনেট ছাড়াই চলে।") {
                        PrivacyScene(active: page == 2)
                    }.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(page == i ? Brand.lilac : Color.white.opacity(0.22))
                            .frame(width: page == i ? 22 : 8, height: 8)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
                .padding(.bottom, 20)
                .accessibilityHidden(true)

                Button {
                    if page < count - 1 { withAnimation(.easeInOut) { page += 1 } } else { done() }
                } label: {
                    Text(page < count - 1 ? "পরবর্তী" : "শুরু করুন")
                        .font(.bn(.headline, .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Brand.micGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct SlidePage<Scene: View>: View {
    let title: String
    let text: String
    @ViewBuilder var scene: Scene

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                scene
                    .frame(height: 300)
                    .padding(.top, 20)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.bn(.title, .bold))
                    .multilineTextAlignment(.center)
                Text(text)
                    .font(.bn(.body))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// A frosted panel the scenes are drawn on.
private struct ScenePanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: 300)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
    }
}

/// Scene 1: a chat; the mic key glows and the reply types itself.
private struct ChatScene: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    @State private var listening = false
    private let reply = Array("আসছি, পাঁচটার মধ্যে পৌঁছাব 🙂")

    var body: some View {
        ScenePanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("আজ বিকেলে দেখা হবে?")
                    .font(.bn(.subheadline))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                HStack(spacing: 0) {
                    Spacer(minLength: 30)
                    HStack(spacing: 1) {
                        Text(String(reply.prefix(shown)))
                        Rectangle().fill(Brand.lilac).frame(width: 2, height: 18)
                            .opacity(shown < reply.count ? 1 : 0)
                    }
                    .font(.bn(.subheadline))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(minHeight: 38)
                    .background(Brand.violet.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(shown == 0 ? 0.4 : 1)
                }
                MiniKeyboard(listening: listening)
                    .padding(.top, 6)
            }
        }
        .task(id: active) { await loop() }
    }

    private func loop() async {
        guard active else { return }
        if reduceMotion { shown = reply.count; return }
        while !Task.isCancelled {
            shown = 0
            withAnimation(.easeInOut(duration: 0.3)) { listening = true }
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(.easeInOut(duration: 0.3)) { listening = false }
            while shown < reply.count && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(70))
                shown += 1
            }
            try? await Task.sleep(for: .seconds(1.8))
        }
    }
}

/// Three rows of blank keys with Kothon's mic key in the middle.
private struct MiniKeyboard: View {
    let listening: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) { ForEach(0..<8, id: \.self) { _ in key } }
            HStack(spacing: 5) {
                key; key
                ZStack {
                    Capsule().fill(Brand.violetLight.opacity(0.35))
                        .scaleEffect(listening ? 1.35 : 1)
                        .opacity(listening ? 0 : 1)
                        .animation(listening ? .easeOut(duration: 0.9).repeatForever(autoreverses: false) : .default,
                                   value: listening)
                    Capsule().fill(Brand.micGradient)
                    Image(systemName: listening ? "waveform" : "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 92, height: 28)
                key; key
            }
            HStack(spacing: 5) { key; RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.14)).frame(height: 24); key }
        }
    }

    private var key: some View {
        RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.14)).frame(height: 24)
    }
}

/// Scene 2: the Settings rows, switched on one after the other.
private struct SetupScene: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0

    var body: some View {
        ScenePanel {
            VStack(spacing: 0) {
                row(icon: "keyboard", title: "কিবোর্ড", trailing: AnyView(Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.5))))
                Divider().overlay(Color.white.opacity(0.1))
                row(icon: nil, title: "কথন", trailing: AnyView(toggle(on: step >= 1)), mark: true)
                Divider().overlay(Color.white.opacity(0.1))
                row(icon: "lock.open", title: "Allow Full Access", trailing: AnyView(toggle(on: step >= 2)))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white)
                .shadow(radius: 6)
                .offset(x: -18, y: step >= 2 ? 6 : -44)
                .opacity(step == 0 || step == 3 ? 0 : 1)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: step)
        }
        .task(id: active) { await loop() }
    }

    private func row(icon: String?, title: String, trailing: AnyView, mark: Bool = false) -> some View {
        HStack(spacing: 12) {
            if mark { BrandMark(size: 28) } else if let icon {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            Text(title).font(.bn(.subheadline, .medium))
            Spacer()
            trailing
        }
        .frame(minHeight: 52)
    }

    private func toggle(on: Bool) -> some View {
        Capsule().fill(on ? Brand.violet : Color.white.opacity(0.2))
            .frame(width: 46, height: 28)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 24, height: 24).padding(2)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: on)
    }

    private func loop() async {
        guard active else { return }
        if reduceMotion { step = 2; return }
        while !Task.isCancelled {
            step = 0
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation { step = 1 }
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation { step = 2 }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { step = 3 }
            try? await Task.sleep(for: .seconds(0.6))
        }
    }
}

/// Scene 3: speech stays inside the phone; the cloud is crossed out.
private struct PrivacyScene: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(Brand.lilac.opacity(0.5), lineWidth: 2))
                .frame(width: 150, height: 270)
                .overlay {
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .strokeBorder(Brand.lilac.opacity(0.45), lineWidth: 1.5)
                                .frame(width: 60, height: 60)
                                .scaleEffect(pulse ? 2.1 : 0.9)
                                .opacity(pulse ? 0 : 0.9)
                                .animation(reduceMotion ? nil :
                                    .easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(Double(i) * 0.6),
                                           value: pulse)
                        }
                        Circle().fill(Brand.micGradient).frame(width: 64, height: 64)
                            .overlay(Image("KothonMark").resizable().scaledToFit()
                                .foregroundStyle(.white).frame(width: 32))
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(8)
                            .background(Brand.plum, in: Circle())
                            .overlay(Circle().strokeBorder(Brand.lilac.opacity(0.5)))
                            .offset(x: 26, y: 26)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                }
            Image(systemName: "icloud.slash")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Brand.lilac.opacity(0.75))
                .offset(x: 110, y: -110)
            Image(systemName: "wifi.slash")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Brand.lilac.opacity(0.55))
                .offset(x: -105, y: 95)
        }
        .onChange(of: active, initial: true) { _, isActive in pulse = isActive }
    }
}
