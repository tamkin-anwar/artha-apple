import SwiftUI
import UIKit

/// Artha's colors, from the orb: cool graphite-navy in Dark, crisp white in
/// Light, orb blue for anything tappable, and color that changes only when
/// a status does (green on pace, amber ahead or over; never red).
///
/// nonisolated: SwiftUI resolves these colors on its own render thread
/// during some animations, so the light/dark lookup must be callable from
/// any thread. Main-actor-only (this project's default) crashed the app the
/// first time Plan animated a change.
nonisolated enum Palette {
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
        Color(UIColor { @Sendable traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    nonisolated init(hex: UInt32) {
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

/// Money as Artha shows it: the currency's own symbol (the same six the web
/// app supports, with the same symbols as utils.CURRENCY_SYMBOLS) and
/// grouped digits. Totals use the person's display currency; a single
/// transaction always uses its own.
enum Money {
    private static let locale = Locale(identifier: "en_US")
    private static let symbols = ["USD": "$", "GBP": "£", "EUR": "€", "BDT": "৳", "CAD": "$", "AUD": "$"]

    static func symbol(for code: String) -> String {
        symbols[code] ?? code
    }

    static func whole(_ value: Decimal, _ code: String) -> String {
        format(value, code, fractionDigits: 0)
    }

    static func cents(_ value: Decimal, _ code: String) -> String {
        format(value, code, fractionDigits: 2)
    }

    /// Whole units when the amount is whole (Rent, $1,650), cents when it
    /// isn't (Spotify, $11.99).
    static func natural(_ value: Decimal, _ code: String) -> String {
        format(value, code, fractionDigits: value == value.rounded(0) ? 0 : 2)
    }

    private static func format(_ value: Decimal, _ code: String, fractionDigits: Int) -> String {
        let symbol = symbols[code] ?? "\(code) "
        let number = abs(value).formatted(.number.locale(locale).precision(.fractionLength(fractionDigits)))
        return (value < 0 ? "−" : "") + symbol + number
    }
}

extension Decimal {
    func rounded(_ scale: Int, _ mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }
}

extension Decimal {
    /// What someone typed into an amount field ("1,250.5"), or nil when
    /// it isn't a positive number.
    static func entry(_ text: String) -> Decimal? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }

    /// Rounded up to a friendly step, for suggesting a budget from what
    /// someone usually spends ($2,812 becomes $2,850 with a step of 50).
    func roundedUp(toStep step: Decimal) -> Decimal {
        guard step > 0 else { return self }
        return (self / step).rounded(0, .up) * step
    }

    /// Plain digits for an editable field: "1650" or "11.99", no symbol or grouping.
    var entryText: String {
        let value = self == rounded(0) ? rounded(0) : rounded(2)
        return NSDecimalNumber(decimal: value).stringValue
    }
}
