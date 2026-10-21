import AppIntents
import Foundation

/// Logs a purchase in Artha without opening it. Built for the Wallet
/// "Transaction" automation in Shortcuts: every Apple Pay tap hands this
/// the amount (with its currency) and the merchant, and the purchase lands
/// in Artha, categorized the same way as one added by hand. Works in any
/// country with Apple Pay, unlike FinanceKit (US and UK only, and only
/// with an entitlement Apple grants per app).
///
/// Its title, description and phrases never say "Apple": App Store Connect
/// rejects any App Intent metadata containing the word (ITMS-90626, which
/// failed build 1). The in-app guide can still say Apple Pay; that's
/// ordinary interface text, not Siri metadata.
struct LogPurchaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Purchase"
    static let description = IntentDescription(
        "Adds a purchase to Artha. Use it in a Wallet transaction automation in Shortcuts and every tap to pay logs itself.",
        categoryName: "Spending"
    )
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Amount", description: "The purchase amount. In a Wallet automation, choose Shortcut Input, then Amount.")
    var amount: IntentCurrencyAmount

    @Parameter(title: "Merchant", description: "Where it was bought. In a Wallet automation, choose Shortcut Input, then Merchant.")
    var merchant: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let purchase = try await PurchaseLogger.log(amount: amount.amount,
                                                    currencyCode: amount.currencyCode,
                                                    merchant: merchant)
        return .result(dialog: IntentDialog(stringLiteral: purchase))
    }
}

/// Siri and Spotlight phrases, and what makes the action easy to find
/// when building the Wallet automation in Shortcuts.
struct ArthaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogPurchaseIntent(),
            phrases: [
                "Log a purchase in \(.applicationName)",
                "Add a purchase to \(.applicationName)",
            ],
            shortTitle: "Log Purchase",
            systemImageName: "creditcard"
        )
    }
}

/// The work behind LogPurchaseIntent, kept apart so it can be reasoned
/// about (and tested) without the App Intents machinery.
enum PurchaseLogger {
    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case signedOut
        case noAmount
        case rejected(String)

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .signedOut:
                "Sign in to Artha on this iPhone first, then your Apple Pay purchases will log themselves."
            case .noAmount:
                "Wallet didn't pass along an amount for this purchase, so Artha didn't log it. Add it by hand if it's missing."
            case .rejected(let message):
                LocalizedStringResource(stringLiteral: message)
            }
        }
    }

    /// The same purchase arriving twice within this window is the
    /// automation firing twice, not two purchases.
    static let duplicateWindow: TimeInterval = 120
    private static let lastLogKey = "applePay.lastLogged"

    /// Returns what to tell the person, e.g. "Logged $6.75 at Blue Bottle
    /// Coffee, under Dining."
    @MainActor
    static func log(amount rawAmount: Decimal, currencyCode rawCurrency: String, merchant rawMerchant: String?) async throws -> String {
        guard let token = Keychain.read(account: Keychain.tokenAccount) else { throw Failure.signedOut }

        // Wallet occasionally hands automations a blank merchant and a zero
        // amount. A zero purchase is never logged; a missing name gets a
        // plain one that can be renamed in Activity.
        let amount = abs(rawAmount)
        guard amount > 0 else { throw Failure.noAmount }
        let merchant = rawMerchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let description = merchant.isEmpty ? "Apple Pay purchase" : merchant
        let currency = rawCurrency.trimmingCharacters(in: .whitespaces).uppercased()

        let key = "\(description)|\(amount)|\(currency)"
        let defaults = UserDefaults.standard
        if let last = defaults.dictionary(forKey: lastLogKey),
           last["key"] as? String == key,
           let at = last["at"] as? Double,
           Date.now.timeIntervalSince1970 - at < duplicateWindow {
            return "Already logged \(Money.cents(amount, currency)) at \(description)."
        }

        let api = APIClient()
        api.token = token
        var body: [String: Any] = [
            "description": description,
            "amount": NSDecimalNumber(decimal: amount).stringValue,
            "type": "expense",
            "source": "apple_pay",
        ]
        if !currency.isEmpty { body["currency"] = currency }

        let envelope: TransactionEnvelope
        do {
            envelope = try await api.post("transactions", body: body)
        } catch APIError.unauthorized {
            throw Failure.signedOut
        } catch let error as APIError {
            throw Failure.rejected(error.message)
        }

        defaults.set(["key": key, "at": Date.now.timeIntervalSince1970], forKey: lastLogKey)

        // Safe to Spend just changed: hand the widgets the new number now,
        // so it's right by the time the phone is back in a pocket.
        if let (_, today): (TodaySummary, Data) = try? await api.fetch("today") {
            AppSession.publishToWidgets(today)
        }

        let tx = envelope.transaction
        let logged = "Logged \(Money.cents(Decimal.api(tx.amount), tx.currency)) at \(tx.description)"
        return tx.category == nil ? "\(logged)." : "\(logged), under \(tx.categoryLabel)."
    }
}
