import AppIntents
import SwiftUI

/// "What's safe to spend in Artha?" Answers out loud and shows the same
/// card as the widget, without opening the app: Siri, Spotlight, the
/// Action button, and Shortcuts, where the amount is also handed on for a
/// custom shortcut (a morning summary, say). Read-only, so it never asks
/// to confirm anything.
///
/// Spoken in full for AirPods or a HomePod (no screen); with a screen the
/// card carries the number and the dialog only adds what it doesn't say.
/// Like LogPurchaseIntent, nothing here says "Apple" (ITMS-90626).
struct CheckNumberIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Safe to Spend"
    static let description = IntentDescription(
        "Tells you what's safe to spend today and how the month is pacing. Or pick spent this month or net worth.",
        categoryName: "Spending"
    )
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Show", default: .safeToSpend)
    var metric: GlanceMetric

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$metric)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentCurrencyAmount> & ProvidesDialog & ShowsSnippetView {
        let summary: TodaySummary
        let fresh: Bool
        switch await TodayNumbers.load() {
        case .ready(let loaded, let isFresh):
            summary = loaded
            fresh = isFresh
        case .signedOut:
            throw Failure.signedOut
        case .unavailable:
            throw Failure.unavailable
        }

        let glance = Glance(summary: summary, metric: metric, date: .now)
        let answer = Answer(glance: glance, asked: metric, fresh: fresh)
        return .result(
            value: IntentCurrencyAmount(amount: glance.value, currencyCode: glance.code),
            dialog: IntentDialog(full: LocalizedStringResource(stringLiteral: answer.spoken),
                                 supporting: LocalizedStringResource(stringLiteral: answer.shown)),
            view: GlanceSnippet(glance: glance)
        )
    }

    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case signedOut, unavailable

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .signedOut: "Sign in to Artha on this device first, then ask again."
            case .unavailable: "Artha couldn't load your numbers. Check your connection and try again."
            }
        }
    }
}

/// What Siri says. `spoken` stands on its own with no screen; `shown` sits
/// above the card, which already has the number, label, detail and status,
/// so it says what they mean instead of repeating them.
struct Answer {
    let spoken: String
    let shown: String

    init(glance: Glance, asked: GlanceMetric, fresh: Bool) {
        let code = glance.code
        let amount = Money.whole(glance.value, code)
        let month = glance.summary.month.name
        var sentences: [String] = []

        // Asked for a number that doesn't exist yet: say so, then answer
        // with the one the card falls back to.
        var fallback: String?
        if asked == .safeToSpend, glance.effectiveMetric != .safeToSpend {
            fallback = "There's no budget set yet, so here's your spending."
        } else if asked == .netWorth, glance.effectiveMetric != .netWorth {
            fallback = "There are no accounts in Artha yet."
        }
        if let fallback { sentences.append(fallback) }

        switch glance.effectiveMetric {
        case .safeToSpend:
            switch glance.status {
            case .over:
                sentences.append("You're over your \(month) budget by \(Money.whole(glance.overBy, code)).")
            case .ahead:
                sentences.append("You can spend \(amount) and stay on plan this month, \(glance.detail). You're spending ahead of pace.")
            case .onPace:
                sentences.append("You can spend \(amount) and stay on plan this month, \(glance.detail).")
            }
        case .spent:
            if let cap = glance.cap {
                sentences.append("You've spent \(amount) in \(month), of your \(Money.whole(cap, code)) budget.")
            } else {
                sentences.append("You've spent \(amount) so far in \(month).")
            }
        case .netWorth:
            sentences.append("Your net worth is \(amount), \(glance.detail).")
        }

        let stale = fresh ? nil : "These are the last numbers Artha saved."
        spoken = (sentences + [stale].compactMap { $0 }).joined(separator: " ")

        let meaning: String
        switch glance.effectiveMetric {
        case .safeToSpend:
            let perDay = Money.whole(glance.perDay, code)
            switch glance.status {
            case .onPace: meaning = "Up to \(perDay) a day keeps \(month) on plan."
            case .ahead: meaning = "You're ahead of pace. Up to \(perDay) a day gets \(month) back on plan."
            case .over: meaning = "\(month) has gone past its budget."
            }
        case .spent:
            meaning = "Everything you've spent in \(month) so far."
        case .netWorth:
            meaning = "What you own, minus what you owe."
        }
        shown = ([fallback ?? meaning] + [stale].compactMap { $0 }).joined(separator: " ")
    }
}

/// The card under Siri's answer: the small widget's layout, with the
/// month's pace beside it when there's room for it.
struct GlanceSnippet: View {
    let glance: Glance

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SmallGlance(glance: glance)
            if glance.effectiveMetric != .netWorth, glance.points.count > 1 {
                MiniPace(glance: glance)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 132)
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}
