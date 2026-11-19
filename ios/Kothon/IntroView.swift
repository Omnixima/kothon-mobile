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

private struct IntroSlide: Identifiable {
    let id: Int
    let symbol: String
    let title: String
    let body: String
    var points: [(String, String)] = []
}

private let slides: [IntroSlide] = [
    IntroSlide(
        id: 0, symbol: "waveform",
        title: "বলুন, কথন লিখে দিবে",
        body: "বাংলায় কথা বলুন, যেকোনো অ্যাপে লেখা চলে আসবে। মেসেজ, নোট, ইমেইল, সব জায়গায়।"),
    IntroSlide(
        id: 1, symbol: "keyboard",
        title: "কিবোর্ড থেকেই",
        body: "কথন একটা কিবোর্ড। লেখার সময় মাইক বোতামে চাপুন।",
        points: [
            ("1.circle.fill", "সেটিংস → জেনারেল → কিবোর্ড → কিবোর্ড যোগ করুন → কথন"),
            ("2.circle.fill", "প্রথমবার কথন অ্যাপ খুলে মাইক চালু করবে, তারপর আগের অ্যাপে ফিরে যান"),
            ("3.circle.fill", "কথা শেষে থামুন চাপুন, লেখা নিজেই বসে যাবে"),
        ]),
    IntroSlide(
        id: 2, symbol: "lock.shield",
        title: "সবকিছু আপনার ফোনেই",
        body: "কথা থেকে লেখা বানানোর পুরো কাজ ফোনের ভেতরেই হয়।",
        points: [
            ("iphone", "আপনার কণ্ঠ বা লেখা কোনো সার্ভারে যায় না"),
            ("wifi.slash", "মডেল একবার নামানোর পর ইন্টারনেট ছাড়াই চলে"),
            ("hand.raised", "কিবোর্ড নিজে কোনো নেটওয়ার্কে যোগাযোগ করে না। \"Full Access\" শুধু কথন অ্যাপের সাথে লেখা আদান-প্রদানের জন্য"),
        ]),
    IntroSlide(
        id: 3, symbol: "arrow.down.circle",
        title: "মডেল বেছে নিন",
        body: "শুরু করতে একটা মডেল নামিয়ে নিন। দ্রুত মডেল ছোট ও তাড়াতাড়ি চলে, নিখুঁত মডেল আরও সঠিক। পরে যেকোনো সময় বদলাতে বা মুছে ফেলতে পারবেন।"),
]

/// Shown on first launch, and again from the home screen's "কীভাবে কাজ করে".
struct IntroSlidesView: View {
    let done: () -> Void
    @State private var page = 0

    var body: some View {
        ZStack {
            KothonBackdrop()
            VStack(spacing: 0) {
                HStack {
                    Wordmark(height: 30)
                    Spacer()
                    if page < slides.count - 1 {
                        Button("এড়িয়ে যান", action: done)
                            .font(.bn(.subheadline, .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                TabView(selection: $page) {
                    ForEach(slides) { slide in
                        SlidePage(slide: slide, active: page == slide.id)
                            .tag(slide.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(slides) { slide in
                        Capsule()
                            .fill(page == slide.id ? Brand.lilac : Color.white.opacity(0.22))
                            .frame(width: page == slide.id ? 22 : 8, height: 8)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
                .padding(.bottom, 20)
                .accessibilityHidden(true)

                Button {
                    if page < slides.count - 1 {
                        withAnimation(.easeInOut) { page += 1 }
                    } else {
                        done()
                    }
                } label: {
                    Text(page < slides.count - 1 ? "পরবর্তী" : "শুরু করুন")
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
    }
}

private struct SlidePage: View {
    let slide: IntroSlide
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Brand.violetLight.opacity(0.22))
                        .frame(width: 150, height: 150)
                    Circle()
                        .strokeBorder(Brand.lilac.opacity(0.26), lineWidth: 1.5)
                        .frame(width: 186, height: 186)
                    Image(systemName: slide.symbol)
                        .font(.system(size: 60, weight: .medium))
                        .foregroundStyle(Brand.lilac)
                        .symbolEffect(.bounce, value: active && !reduceMotion)
                }
                .scaleEffect(active || reduceMotion ? 1 : 0.85)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: active)
                .padding(.top, 36)
                .accessibilityHidden(true)

                Text(slide.title)
                    .font(.bn(.title, .bold))
                    .multilineTextAlignment(.center)
                Text(slide.body)
                    .font(.bn(.body))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)

                if !slide.points.isEmpty {
                    GlassCard {
                        ForEach(Array(slide.points.enumerated()), id: \.offset) { _, point in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: point.0)
                                    .font(.title3)
                                    .foregroundStyle(Brand.lilac)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                Text(point.1)
                                    .font(.bn(.subheadline))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
