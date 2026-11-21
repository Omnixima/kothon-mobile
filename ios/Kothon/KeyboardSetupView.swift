// The কিবোর্ড sheet: a live setup checklist, the Apple-mic tip, privacy,
// and links to the intro and licenses.

import SwiftUI

struct KeyboardSetupView: View {
    @Binding var showIntro: Bool
    @Binding var developerMode: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var added = false
    @State private var fullAccess = false
    @State private var tryText = ""
    @FocusState private var tryFocused: Bool
    /// Re-check every second while this screen shows: Settings changes and the
    /// keyboard's "I ran" mark arrive without telling the app.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var allDone: Bool { added && fullAccess }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            checklist
            if !allDone { openSettingsButton }
            micTip
            privacyBadge
            links
            if developerMode { DeveloperSection() }
            VersionLine(developerMode: $developerMode)
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .onReceive(tick) { _ in if !allDone { refresh() } }
    }

    /// Settings → Keyboards lists Kothon once it's added; the keyboard marks
    /// the App Group when it runs with Full Access (only possible then).
    private func refresh() {
        // Read the system keyboard list fresh: UserDefaults caches it, so a
        // keyboard added in Settings wouldn't show until the app restarted.
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let keyboards = (CFPreferencesCopyAppValue("AppleKeyboards" as CFString, kCFPreferencesAnyApplication) as? [String] ?? [])
            + (UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String] ?? [])
        // The keyboards iOS has turned on right now; Kothon's is the bn-BD one.
        let active = UITextInputMode.activeInputModes.contains { mode in
            mode.primaryLanguage == "bn-BD"
                || ((mode.value(forKey: "identifier") as? String)?.hasPrefix("com.kothon") ?? false)
        }
        KothonShared.defaults.synchronize()
        fullAccess = KothonShared.defaults.double(forKey: SharedKey.keyboardFullAccessSeen) > 0
        added = fullAccess || active || keyboards.contains { $0.hasPrefix("com.kothon.dictation.ios.keyboard") }
    }

    // MARK: Checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 16) {
            if allDone {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(Brand.readyGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("সব তৈরি").font(.bn(.title3, .bold))
                        Text("যেকোনো অ্যাপে 🌐 চেপে কথন বেছে নিন।").font(.bn(.footnote)).foregroundStyle(.white.opacity(0.65))
                    }
                }
            } else {
                Text("কথন কিবোর্ড চালু করুন").font(.bn(.title3, .bold))
            }
            VStack(alignment: .leading, spacing: 14) {
                step(1, done: added, "কিবোর্ড যোগ করুন",
                     "Settings → General → Keyboard → Keyboards → Add New Keyboard → কথন")
                step(2, done: fullAccess, "Full Access চালু করুন",
                     "Settings → General → Keyboard → Keyboards → কথন → Allow Full Access। লেখা কিবোর্ডে আনতে লাগে, কিছুই ইন্টারনেটে যায় না।")
                step(3, done: fullAccess, "কিবোর্ড একবার খুলে দেখুন",
                     fullAccess
                        ? "কথন কিবোর্ড ঠিকমতো চলছে। যেকোনো অ্যাপে 🌐 চেপে কথন বেছে নিন।"
                        : "নিচের বক্সে চাপুন, তারপর 🌐 চেপে কথন বেছে নিন। Full Access চালু থাকলে এখানে ✓ আসবে।")
                if added && !fullAccess { tryBox }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// A text field to bring up the keyboard right here. When Kothon's
    /// keyboard opens with Full Access it marks the App Group, and step 2
    /// and 3 tick within a second.
    private var tryBox: some View {
        TextField("", text: $tryText, prompt: Text("এখানে চাপুন, তারপর 🌐").foregroundStyle(.white.opacity(0.45)))
            .font(.bn(.body))
            .focused($tryFocused)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.lilac.opacity(0.4)))
            .padding(.leading, 40)
            .onChange(of: fullAccess) { _, on in if on { tryFocused = false } }
    }

    private func step(_ n: Int, done: Bool, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Brand.readyGreen : Color.white.opacity(0.12))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.plum)
                } else {
                    Text(DictationService.bn(Double(n), digits: 0)).font(.bn(.subheadline, .semibold))
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.bn(.body, .semibold))
                    .strikethrough(false)
                    .opacity(done ? 0.7 : 1)
                Text(detail).font(.bn(.caption)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "হয়ে গেছে" : "বাকি")
    }

    private var openSettingsButton: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        } label: {
            Text("সেটিংস খুলুন")
                .font(.bn(.headline, .semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Brand.violet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: Apple's mic vs Kothon's button

    private var micTip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("কোন বোতামে বলবেন?").font(.bn(.headline, .semibold))
            // A small drawing of the keyboard: Kothon's button on top,
            // Apple's grey mic under the keys.
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image("KothonMark").resizable().scaledToFit().frame(width: 16, height: 13)
                    Text("কথন-এ বলুন").font(.bn(size: 12, .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(Brand.micGradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 4) {
                            ForEach(0..<10, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.13)).frame(height: 14)
                            }
                        }
                    }
                }
                HStack {
                    Image(systemName: "globe").foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Image(systemName: "mic").foregroundStyle(.white.opacity(0.45))
                }
                .font(.system(size: 15))
                .padding(.horizontal, 6)
            }
            .padding(10)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                tag("কথন", Brand.violetLight).offset(x: -10, y: -10)
            }
            .overlay(alignment: .bottomTrailing) {
                tag("Apple", .gray).offset(x: -4, y: 12)
            }
            .accessibilityHidden(true)
            .padding(.bottom, 6)

            Text("বেগুনি \"কথন-এ বলুন\" কথনের। নিচের ধূসর মাইকটা Apple-এর, সেটা কথন নয়।")
                .font(.bn(.subheadline))
            Text("চাইলে Apple-এর ডিক্টেশন বন্ধ করতে পারেন: Settings → General → Keyboard → Enable Dictation")
                .font(.bn(.caption)).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.bn(size: 11, .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
    }

    // MARK: Privacy and links

    private var privacyBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(Brand.lilac)
            Text("সব কাজ ফোনেই হয়। কোনো শব্দ বা লেখা ইন্টারনেটে যায় না।")
                .font(.bn(.footnote, .medium))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.white.opacity(0.07), in: Capsule())
    }

    private var links: some View {
        VStack(spacing: 0) {
            Button { showIntro = true } label: {
                linkRow("questionmark.circle", "কীভাবে কাজ করে")
            }
            .buttonStyle(.plain)
            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 48)
            NavigationLink { OmniximaAboutView() } label: {
                linkRow("person.2", "Omnixima সম্পর্কে")
            }
            .buttonStyle(.plain)
            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 48)
            NavigationLink { AcknowledgementsView() } label: {
                linkRow("heart.text.square", "লাইসেন্স ও কৃতজ্ঞতা")
            }
            .buttonStyle(.plain)
        }
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func linkRow(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Brand.lilac).frame(width: 22)
            Text(title).font(.bn(.body))
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Developer mode only: share the last recording (AirDrop, Files) to test
/// models with real dictations. The file stays until the next dictation or
/// until developer mode is turned off.
private struct DeveloperSection: View {
    @EnvironmentObject var dictation: DictationService
    @State private var hasRecording = false
    @AppStorage(SharedKey.devHitAreas, store: KothonShared.defaults) private var showHitAreas = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ডেভেলপার").font(.bn(.headline, .semibold))
            Toggle("কিবোর্ডে প্রতিটা বোতামের ট্যাপ-এলাকা রঙ করে দেখান", isOn: $showHitAreas)
                .font(.bn(.subheadline))
                .tint(Brand.violet)
            if hasRecording {
                ShareLink(item: DictationService.lastRecordingURL) {
                    Label("শেষ রেকর্ডিং সেভ করুন", systemImage: "square.and.arrow.up")
                        .font(.bn(.body, .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Brand.violet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Text("শেষবার যা বলেছেন তার শব্দ, WAV ফাইল। AirDrop বা Files-এ পাঠাতে পারেন।")
                    .font(.bn(.caption)).foregroundStyle(.white.opacity(0.6))
            } else {
                Label("শেষ রেকর্ডিং সেভ করুন", systemImage: "square.and.arrow.up")
                    .font(.bn(.body, .semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white.opacity(0.4))
                Text("এখনো কোনো রেকর্ডিং নেই। ডেভেলপার মোড চালু রেখে একবার বলুন (অ্যাপে বা কিবোর্ডে), তারপর এখানে আসবে।")
                    .font(.bn(.caption)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear(perform: refresh)
        .onChange(of: dictation.lastStats) { _, _ in
            // The file is written in the background just after a dictation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: refresh)
        }
    }

    private func refresh() {
        hasRecording = FileManager.default.fileExists(atPath: DictationService.lastRecordingURL.path)
    }
}
