// Kothon's brand, shared by the app and the keyboard: colors from the app
// icon and the desktop app, the bundled Noto Sans Bengali, and the mark.

import SwiftUI

enum Brand {
    /// The app icon's plum; the mark's tile.
    static let plum = Color(red: 0x3F / 255, green: 0x01 / 255, blue: 0x59 / 255)
    static let violet = Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)
    static let violetLight = Color(red: 0xA7 / 255, green: 0x8B / 255, blue: 0xFA / 255)
    static let lilac = Color(red: 0xE9 / 255, green: 0xD5 / 255, blue: 0xFF / 255)
    static let softRed = Color(red: 0xFC / 255, green: 0xA5 / 255, blue: 0xA5 / 255)
    static let readyGreen = Color(red: 0x86 / 255, green: 0xEF / 255, blue: 0xAC / 255)
    /// The wordmark on a light surface: violet, lighter in dark mode (as on desktop).
    static let wordmark = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xA7 / 255, green: 0x8B / 255, blue: 0xFA / 255, alpha: 1)
        : UIColor(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255, alpha: 1) })
    /// The home screen's background: a deep plum glow.
    static let backdrop = RadialGradient(
        stops: [
            .init(color: Color(red: 0x5B / 255, green: 0x1A / 255, blue: 0x85 / 255), location: 0),
            .init(color: Color(red: 0x2A / 255, green: 0x00 / 255, blue: 0x40 / 255), location: 0.62),
            .init(color: Color(red: 0x16 / 255, green: 0x09 / 255, blue: 0x1F / 255), location: 1),
        ],
        center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 560)
    /// The mic button's fill.
    static let micGradient = LinearGradient(colors: [violetLight, violet],
                                            startPoint: .topLeading, endPoint: .bottomTrailing)
    static let fontName = "Noto Sans Bengali"
}

extension Font {
    /// Noto Sans Bengali at a text style's size, scaling with Dynamic Type.
    static func bn(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .custom(Brand.fontName, size: style.pointSize, relativeTo: style).weight(weight)
    }

    /// Noto Sans Bengali at a fixed size (still scales with Dynamic Type).
    static func bn(size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(Brand.fontName, size: size, relativeTo: .body).weight(weight)
    }
}

private extension Font.TextStyle {
    /// iOS default sizes at the standard Dynamic Type setting.
    var pointSize: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}

/// The mouth mark, white on a plum rounded-square tile, as on the app icon
/// and the desktop app.
struct BrandMark: View {
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Brand.plum)
            .frame(width: size, height: size)
            .overlay(
                Image("KothonMark").resizable().scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: size * 0.62, height: size * 0.62))
            .accessibilityHidden(true)
    }
}

/// The "Beta" badge.
struct BetaBadge: View {
    var onDark = true

    var body: some View {
        Text("Beta")
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(onDark ? Color.white.opacity(0.14) : Brand.violet.opacity(0.13), in: Capsule())
            .foregroundStyle(onDark ? Brand.lilac : Brand.violet)
    }
}
