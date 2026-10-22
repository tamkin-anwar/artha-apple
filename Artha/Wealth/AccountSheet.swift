import SwiftUI

/// Add an account, or update one. Updating a balance is the thing people do
/// most, so the balance comes first and is ready to type into; with nothing
/// changed, the button confirms the balance is still right instead.
struct AccountSheet: View {
    /// The account being changed, or nil to add one.
    let existing: APIAccount?
    /// The type a new account starts as (from the empty state's shortcuts).
    var startingType = "checking"

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type = "checking"
    @State private var currency = "USD"
    @State private var balanceText = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var confirmingDelete = false
    @FocusState private var balanceFocused: Bool

    private var wealth: WealthModel { session.wealth }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Palette.secondary)
                    .frame(minHeight: 44)
                Spacer()
                Text(existing?.name ?? "New account")
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer()
                Color.clear.frame(width: 52, height: 1)
            }

            AmountField(text: $balanceText, currencyCode: currency, size: 60, focus: $balanceFocused)
                .padding(.top, 30)

            Text(caption)
                .font(.system(.subheadline))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 6)

            VStack(spacing: 0) {
                Row("Name") {
                    TextField(namePlaceholder, text: $name)
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                }
                Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1)
                Row("Type") {
                    Picker("Type", selection: $type) {
                        Section("What you own") {
                            ForEach(wealth.accountTypes.filter { !$0.isLiability }) { Text($0.label).tag($0.key) }
                        }
                        Section("What you owe") {
                            ForEach(wealth.accountTypes.filter(\.isLiability)) { Text($0.label).tag($0.key) }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1)
                Row("Currency") {
                    CurrencyButton(selection: $currency, showsName: false)
                }
            }
            .font(.system(.callout))
            .tint(Palette.accent)
            .padding(.horizontal, 16)
            .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
            .padding(.top, 28)

            if let error {
                Text(error)
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.caution)
                    .padding(.top, 12)
                    .announcedWhenShown(error)
            }

            Spacer(minLength: 16)

            if let existing {
                Button("Delete account", role: .destructive) { confirmingDelete = true }
                    .font(.system(.subheadline, weight: .semibold))
                    .frame(minHeight: 44)
                    .disabled(isSaving)
                    .padding(.bottom, 6)
                    .confirmationDialog("Delete \(existing.name)? Your net worth history stays.",
                                        isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            run { try await wealth.deleteAccount(existing.id) }
                        }
                    }
            }

            Button(action: save) {
                ZStack {
                    if isSaving {
                        ProgressView().tint(Palette.onInverse)
                    } else {
                        Text(buttonTitle)
                    }
                }
                .font(.system(.body, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Palette.inverse, in: Capsule())
                .foregroundStyle(Palette.onInverse)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(Palette.ground)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .onAppear(perform: load)
    }

    // MARK: State

    private var isLiability: Bool {
        wealth.accountTypes.first { $0.key == type }?.isLiability ?? false
    }

    private var caption: String {
        isLiability ? "owed right now" : "in this account right now"
    }

    private var namePlaceholder: String {
        switch type {
        case "credit_card": "Visa card"
        case "loan": "Car loan"
        case "savings": "High-yield savings"
        case "investment": "Brokerage"
        case "real_estate": "Home"
        case "vehicle": "Car"
        default: "Chase checking"
        }
    }

    /// Zero is a real balance (a paid-off card), so only text that isn't a
    /// number blocks saving.
    private var balance: Decimal? {
        let cleaned = balanceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { return nil }
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), value >= 0 else { return nil }
        return value
    }

    private var changes: [String: Any] {
        guard let existing else { return [:] }
        var changes: [String: Any] = [:]
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed != existing.name { changes["name"] = trimmed }
        if type != existing.type { changes["account_type"] = type }
        if currency != existing.currency { changes["currency"] = currency }
        if let balance, balance != Decimal.api(existing.balance) {
            changes["current_balance"] = NSDecimalNumber(decimal: balance).stringValue
        }
        return changes
    }

    private var buttonTitle: String {
        guard existing != nil else { return "Add account" }
        return changes.isEmpty ? "Balance is still right" : "Save"
    }

    private var canSave: Bool {
        !isSaving && balance != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func load() {
        if let existing {
            name = existing.name
            type = existing.type
            currency = existing.currency
            balanceText = Decimal.api(existing.balance).entryText
        } else {
            type = startingType
            currency = wealth.currencyCode
        }
        balanceFocused = true
    }

    private func save() {
        guard canSave, let balance else { return }
        if let existing {
            var body = changes
            // Nothing changed: confirm the balance is still right, which
            // moves its "updated" date to today.
            if body["current_balance"] == nil { body["current_balance"] = NSDecimalNumber(decimal: balance).stringValue }
            run { try await wealth.updateAccount(existing.id, changes: body) }
        } else {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            run { try await wealth.addAccount(name: trimmed, type: type, currency: currency, balance: balance) }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await work()
                dismiss()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't save that. Try again in a moment."
            }
        }
    }
}

private struct Row<Control: View>: View {
    let label: String
    let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(Palette.secondary)
            Spacer(minLength: 8)
            control.foregroundStyle(Palette.ink)
        }
        .frame(minHeight: 52)
    }
}

/// Walks through every balance that's over a month old, one at a time:
/// confirm it's still right with one tap, or type the new one. The fix for
/// the one real weakness of tracking balances by hand, which is that they
/// quietly go stale.
struct ReviewBalancesSheet: View {
    let accounts: [APIAccount]

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var text = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var savedCount = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Done") { dismiss() }
                    .foregroundStyle(Palette.secondary)
                    .frame(minHeight: 44)
                Spacer()
                Text("\(min(index + 1, accounts.count)) of \(accounts.count)")
                    .font(.system(.callout, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Spacer()
                Button("Skip") { advance() }
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
                    .disabled(isSaving)
            }

            if let account = current {
                VStack(spacing: 6) {
                    Image(systemName: AccountStyle.symbol(for: account.type))
                        .font(.system(.title3, weight: .medium))
                        .frame(width: 52, height: 52)
                        .background(Palette.raised, in: .rect(cornerRadius: Radius.inner))
                        .foregroundStyle(Palette.ink)
                    Text(account.name)
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text("\(account.typeLabel) · \(AccountStyle.updatedLabel(days: account.daysSinceUpdate))")
                        .font(.system(.subheadline))
                        .foregroundStyle(Palette.secondary)
                }
                .padding(.top, 24)
                .id(account.id)
                .motionTransition(.push(from: .trailing))

                AmountField(text: $text, currencyCode: account.currency, size: 60, focus: $focused)
                    .padding(.top, 24)

                Text(account.isLiability ? "owed right now" : "in this account right now")
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.secondary)
                    .padding(.top, 6)
            }

            if let error {
                Text(error)
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.caution)
                    .padding(.top, 12)
                    .announcedWhenShown(error)
            }

            Spacer(minLength: 16)

            Button(action: save) {
                ZStack {
                    if isSaving {
                        ProgressView().tint(Palette.onInverse)
                    } else {
                        Text(isUnchanged ? "Still right" : "Save")
                    }
                }
                .font(.system(.body, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Palette.inverse, in: Capsule())
                .foregroundStyle(Palette.onInverse)
            }
            .buttonStyle(.plain)
            .disabled(isSaving || amount == nil)
            .opacity(amount == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(Palette.ground)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: savedCount)
        .animation(.snappy(duration: 0.35), value: index)
        .onAppear { fill(); focused = true }
    }

    private var current: APIAccount? { accounts.indices.contains(index) ? accounts[index] : nil }

    private var amount: Decimal? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), value >= 0 else { return nil }
        return value
    }

    private var isUnchanged: Bool {
        guard let current, let amount else { return true }
        return amount == Decimal.api(current.balance)
    }

    private func fill() {
        text = current.map { Decimal.api($0.balance).entryText } ?? ""
    }

    private func advance() {
        if index + 1 >= accounts.count {
            dismiss()
        } else {
            index += 1
            fill()
        }
    }

    private func save() {
        guard let current, let amount else { return }
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await session.wealth.updateAccount(current.id, changes: [
                    "current_balance": NSDecimalNumber(decimal: amount).stringValue,
                ])
                savedCount += 1
                advance()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't save that. Try again in a moment."
            }
        }
    }
}
