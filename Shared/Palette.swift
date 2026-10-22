import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Artha's colors, from the orb: cool graphite-navy in Dark, crisp white in
/// Light, orb blue for anything tappable, and color that changes only when
/// a status does (green on pace, amber ahead or over; never red).
///
/// The light and dark values live in `Shared/Palette.xcassets` (one color
/// set per token, compiled into the app and the widgets; the comment on
/// each line repeats them, light / dark, to keep them in step with the
/// website's style.css). Asset-catalog colors resolve against SwiftUI's own
/// color scheme the moment it changes, where a UIColor trait closure lags a
/// layout pass behind (Corres hit that as cards staying the old color after
/// switching Appearance).
///
/// nonisolated: SwiftUI resolves these colors on its own render thread
/// during some animations, so the lookup must be callable from any thread.
/// Main-actor-only (this project's default) crashed the app the first time
/// Plan animated a change.
nonisolated enum Palette {
    static let ground = Color("arthaGround") // F4F6FA / 0A0E17
    static let surface = Color("arthaSurface") // FFFFFF / 121826
    static let raised = Color("arthaRaised") // E4E9F2 / 1A2233
    static let ink = Color("arthaInk") // 0B1020 / F2F4F8
    static let secondary = Color("arthaSecondary") // 586174 / A3ABBD
    static let accent = Color("arthaAccent") // 2F5FD0 / 6E95FF
    static let good = Color("arthaGood") // 16804B / 3DD68C
    static let caution = Color("arthaCaution") // 9A5B00 / F5B544
    static let cautionLine = Color("arthaCautionLine") // D98A0B / F5B544
    static let band = Color("arthaBand") // 1F2F57 / 16264F
    static let inverse = Color("arthaInverse") // 0B1020 / F2F4F8
    static let onInverse = Color("arthaOnInverse") // FFFFFF / 0A0E17

    static let orbLight = Color(hex: 0x5C90DE)
    static let orbMid = Color(hex: 0x3466C0)
    static let orbDeep = Color(hex: 0x1D3B8C)
    static let orbEdge = Color(hex: 0x142B68)
    static let sunCore = Color(hex: 0xFFF4D8)
    static let sunGlow = Color(hex: 0xFFD27A)
    static let sun = Color(hex: 0xF5A524)
}

#if canImport(UIKit)
extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
#else
extension NSColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
#endif

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
    /// Fixed size: for widgets and anywhere Dynamic Type can't apply. In the
    /// app, use `.figureFont(_:weight:)`, which scales with the person's
    /// text size.
    static func figure(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Corner radii: three, all continuous, so every surface reads as one
/// family (Corres uses the same 22 for its surfaces). `card` for anything
/// that sits on the ground (cards, lists, sheets' inner panels), `inner`
/// for a control or tile inside a card, `small` for icon tiles and chips.
nonisolated enum Radius {
    static let card: CGFloat = 22
    static let inner: CGFloat = 14
    static let small: CGFloat = 10
}

/// A figure at its designed size, scaled with Dynamic Type the way body
/// text scales (Apple's body sizes, xSmall 14 to AX5 53, over the default
/// 17). Big display figures grow less, so a hero number stays one line on
/// a phone at the largest text sizes; small ones grow fully.
nonisolated enum FigureScale {
    static func factor(for size: DynamicTypeSize) -> CGFloat {
        let body: CGFloat = switch size {
        case .xSmall: 14
        case .small: 15
        case .medium: 16
        case .large: 17
        case .xLarge: 19
        case .xxLarge: 21
        case .xxxLarge: 23
        case .accessibility1: 28
        case .accessibility2: 33
        case .accessibility3: 40
        case .accessibility4: 47
        case .accessibility5: 53
        @unknown default: 17
        }
        return body / 17
    }

    static func scaled(_ size: CGFloat, for typeSize: DynamicTypeSize) -> CGFloat {
        let factor = factor(for: typeSize)
        let cap: CGFloat = size >= 40 ? 1.3 : size >= 24 ? 1.7 : 3.2
        return (size * min(factor, cap)).rounded()
    }
}

private struct FigureFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.font(.system(size: FigureScale.scaled(size, for: typeSize), weight: weight, design: .rounded))
    }
}

extension View {
    /// SF Rounded money figures that scale with Dynamic Type.
    func figureFont(_ size: CGFloat, weight: Font.Weight = .heavy) -> some View {
        modifier(FigureFont(size: size, weight: weight))
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

    /// Short enough for a Lock Screen circle: $232, $1.2K, $154K, $1.3M.
    static func compact(_ value: Decimal, _ code: String) -> String {
        let symbol = symbols[code] ?? "\(code) "
        let number = (abs(value) as NSDecimalNumber).doubleValue
        let sign = value < 0 ? "−" : ""
        switch number {
        case ..<1_000: return sign + symbol + String(Int(number.rounded(.down)))
        case ..<10_000: return sign + symbol + String(format: "%.1fK", (number / 100).rounded(.down) / 10)
        case ..<1_000_000: return sign + symbol + "\(Int(number / 1_000))K"
        default: return sign + symbol + String(format: "%.1fM", (number / 100_000).rounded(.down) / 10)
        }
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
