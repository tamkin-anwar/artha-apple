import SwiftUI
import UIKit

/// Artha's colors, from the orb: cool graphite-navy in Dark, crisp white in
/// Light, orb blue for anything tappable, and color that changes only when
/// a status does (green on pace, amber ahead or over; never red).
enum Palette {
    static let ground = dynamic(light: 0xF4F6FA, dark: 0x0A0E17)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x121826)
    static let raised = dynamic(light: 0xE4E9F2, dark: 0x1A2233)
    static let ink = dynamic(light: 0x0B1020, dark: 0xF2F4F8)
    static let secondary = dynamic(light: 0x586174, dark: 0xA3ABBD)
    static let accent = dynamic(light: 0x2F5FD0, dark: 0x6E95FF)
    static let good = dynamic(light: 0x16804B, dark: 0x3DD68C)
    static let caution = dynamic(light: 0x9A5B00, dark: 0xF5B544)
    static let cautionLine = dynamic(light: 0xD98A0B, dark: 0xF5B544)
    static let band = dynamic(light: 0x1F2F57, dark: 0x16264F)
    static let inverse = dynamic(light: 0x0B1020, dark: 0xF2F4F8)
    static let onInverse = dynamic(light: 0xFFFFFF, dark: 0x0A0E17)

    static let orbLight = Color(hex: 0x5C90DE)
    static let orbMid = Color(hex: 0x3466C0)
    static let orbDeep = Color(hex: 0x1D3B8C)
    static let orbEdge = Color(hex: 0x142B68)
    static let sunCore = Color(hex: 0xFFF4D8)
    static let sunGlow = Color(hex: 0xFFD27A)
    static let sun = Color(hex: 0xF5A524)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    /// Figures are SF Rounded, the face Apple uses for the big numbers in
    /// Fitness and Health: friendly, native, and nothing like Corres's serif.
    static func figure(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

enum Money {
    private static let locale = Locale(identifier: "en_US")

    static func whole(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").locale(locale).precision(.fractionLength(0)))
    }

    static func cents(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").locale(locale).precision(.fractionLength(2)))
    }

    /// A single transaction shows its own native amount and currency, never
    /// a converted one (the converted equivalent goes on its own line).
    static func native(_ value: Decimal, code: String) -> String {
        switch code {
        case "BDT": "৳" + value.formatted(.number.locale(locale).precision(.fractionLength(0)))
        default: cents(value)
        }
    }
}
