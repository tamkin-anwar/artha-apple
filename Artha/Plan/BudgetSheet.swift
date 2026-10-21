import SwiftUI

/// Set or change the monthly budget. Suggests one from what this person
/// actually spent over the last few months, so nobody has to guess.
struct BudgetSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var plan: PlanModel { session.plan }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Palette.secondary)
                    .frame(minHeight: 44)
                Spacer()
                Text("Monthly budget")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Color.clear.frame(width: 52, height: 1)
            }

            AmountField(text: $text, currencyCode: plan.currencyCode, size: 68, focus: $focused)
                .padding(.top, 40)

            Text("for everything you spend in a month, bills included")
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 6)

            if let suggestion = plan.suggestedBudget, suggestion != amount,
               let usual = plan.summary?.typical.map({ Decimal.api($0.overall) }) {
                SuggestionChip(text: "You usually spend \(Money.whole(usual, plan.currencyCode)). Use \(Money.whole(suggestion, plan.currencyCode))") {
                    text = suggestion.entryText
                }
                .padding(.top, 22)
            }

            if let error {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.caution)
                    .padding(.top, 14)
            }

            Spacer(minLength: 20)

            if plan.cap != nil {
                Button("Remove budget", role: .destructive) { save(nil) }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(minHeight: 44)
                    .disabled(isSaving)
                    .padding(.bottom, 6)
            }

            Button { save(amount) } label: {
                ZStack {
                    if isSaving {
                        ProgressView().tint(Palette.onInverse)
                    } else {
                        Text(plan.cap == nil ? "Set budget" : "Save")
                    }
                }
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Palette.inverse, in: Capsule())
                .foregroundStyle(Palette.onInverse)
            }
            .buttonStyle(.plain)
            .disabled(amount == nil || isSaving)
            .opacity(amount == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(Palette.ground)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .task {
            if plan.summary == nil { await plan.load() }
            if text.isEmpty, let cap = plan.cap { text = cap.entryText }
            focused = true
        }
    }

    private var amount: Decimal? { Decimal.entry(text) }

    private func save(_ value: Decimal?) {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await plan.saveBudget(value)
                dismiss()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't save your budget. Try again in a moment."
            }
        }
    }
}
