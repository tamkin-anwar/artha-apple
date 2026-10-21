import SwiftUI

/// Add an expense or income. The amount comes first and fills the screen;
/// Artha picks the category itself (remembered merchant, then keywords,
/// then AI, the same as the web app), so there's nothing else to choose.
struct AddSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(MonthModel.self) private var month
    @Environment(\.dismiss) private var dismiss

    private enum Kind: String, CaseIterable { case expense = "Expense", income = "Income" }
    private enum Field { case amount, description }

    @State private var kind: Kind = .expense
    @State private var amountText = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var showingApplePaySetup = false
    @FocusState private var focus: Field?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.secondary)
                    .frame(minHeight: 44)
                Spacer()
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Spacer()
                Color.clear.frame(width: 52, height: 1)
            }

            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Money.symbol(for: month.currencyCode))
                        .foregroundStyle(amountText.isEmpty ? Palette.secondary.opacity(0.5) : Palette.ink)
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(Palette.ink)
                        .fixedSize()
                        .focused($focus, equals: .amount)
                        .accessibilityLabel("Amount")
                }
                .font(.figure(76))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { focus = .amount }
                Text(month.currencyCode)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Palette.raised, in: Capsule())
                    .foregroundStyle(Palette.ink)
            }
            .padding(.top, 36)

            TextField(kind == .expense ? "What was it? (Blue Bottle Coffee)" : "Where's it from? (Salary)", text: $description)
                .font(.system(size: 17))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .background(Palette.surface, in: .rect(cornerRadius: 18))
                .focused($focus, equals: .description)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.top, 32)

            Text(kind == .expense
                 ? "Artha sorts it into a category for you, and remembers what you change."
                 : "Counts toward this month's income.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 10)

            if let error {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.caution)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 10)
            }

            Spacer(minLength: 20)

            Button { showingApplePaySetup = true } label: {
                Label("Log Apple Pay purchases automatically", systemImage: "wave.3.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
            }
            .padding(.bottom, 6)

            Button(action: save) {
                ZStack {
                    if isSaving {
                        ProgressView().tint(Palette.onInverse)
                    } else {
                        Text(amount.map { "Add \(Money.cents($0, month.currencyCode))" } ?? "Add")
                    }
                }
                .font(.system(size: 17, weight: .bold))
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
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .onAppear { focus = .amount }
        .sheet(isPresented: $showingApplePaySetup) { ApplePaySetupView() }
    }

    private var amount: Decimal? {
        let cleaned = amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        !isSaving && amount != nil && !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        guard canSave, let amount else { return }
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await session.addTransaction(description: description.trimmingCharacters(in: .whitespaces),
                                                 amount: amount,
                                                 type: kind == .expense ? "expense" : "income")
                dismiss()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't save that. Try again in a moment."
            }
        }
    }
}
