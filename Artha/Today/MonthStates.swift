import SwiftUI

/// Ahead of pace: amber, never red. Information, not a scolding.
struct AheadCard: View {
    @Environment(MonthModel.self) private var month

    var body: some View {
        StateCard(symbol: "arrow.up.right",
                  title: "Spending is running ahead",
                  detail: "You're past an even pace for \(month.monthName). Keeping to \(Money.whole(month.perDay, month.currencyCode)) a day still ends the month inside its budget.")
    }
}

/// Over budget: say it plainly, and say when it resets.
struct OverCard: View {
    @Environment(AppSession.self) private var session
    @Environment(MonthModel.self) private var month

    var body: some View {
        StateCard(symbol: "exclamationmark",
                  title: "\(month.monthName) is over budget",
                  detail: "Spending and the bills still due come to \(Money.whole(month.overBy, month.currencyCode)) more than the budget. \(month.nextMonthName)'s budget starts in \(month.daysLeft) \(month.daysLeft == 1 ? "day" : "days").",
                  action: "Change budget") { session.isEditingBudget = true }
    }
}

/// No budget yet, so there's nothing to be "safe" against.
struct NoBudgetCard: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        StateCard(symbol: "target",
                  title: "Set a monthly budget",
                  detail: "With a budget, Today shows what's safe to spend each day, after the bills still due.",
                  tint: Palette.accent,
                  action: "Set budget") { session.isEditingBudget = true }
    }
}

/// Purchases that logged themselves (Apple Pay) and haven't been looked
/// at. Optional by design: it never badges or nags, it just waits here.
struct ReviewCard: View {
    @Environment(AppSession.self) private var session
    @Environment(MonthModel.self) private var month

    var body: some View {
        let count = month.toReview
        StateCard(symbol: "checkmark.circle",
                  title: count == 1 ? "1 purchase to review" : "\(count) purchases to review",
                  detail: "Logged on their own with Apple Pay. A quick look keeps names and categories right.",
                  tint: Palette.accent,
                  action: "Review") { session.isReviewing = true }
    }
}

/// Charges that repeat like bills but aren't tracked. Plan lists them,
/// with Track it and Not a bill.
struct BillSuggestionsCard: View {
    @Environment(AppSession.self) private var session
    @Environment(MonthModel.self) private var month

    var body: some View {
        let count = month.billSuggestions
        StateCard(symbol: "repeat",
                  title: count == 1 ? "1 charge looks like a bill" : "\(count) charges look like bills",
                  detail: "They repeat like clockwork. Track them so Safe to Spend counts them before they hit.",
                  tint: Palette.accent,
                  action: "Take a look") { session.route = .plan }
    }
}

private struct StateCard: View {
    let symbol: String
    let title: String
    let detail: String
    var tint: Color = Palette.caution
    var action: String? = nil
    var perform: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Palette.raised, in: .rect(cornerRadius: Radius.small))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action, action: perform)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: 36)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
        .motionTransition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// A brand-new account: what to do first, then the month draws itself.
struct FirstDay: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Let's find your safe to spend")
                .font(.system(.title, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Palette.ink)
            Text("Two quick steps. After that, Artha does the math every day.")
                .font(.system(.callout))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 8)

            VStack(spacing: 0) {
                Button { session.isEditingBudget = true } label: {
                    StepRow(number: 1, title: "Set a monthly budget", detail: "Tap here. Artha suggests one from your spending")
                }
                .buttonStyle(.plain)
                Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1)
                StepRow(number: 2, title: "Add your first expense", detail: "Tap + below. It takes a few seconds")
            }
            .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
            .padding(.top, 22)

            if ThisDevice.canAutomateApplePay {
            Button { session.isShowingApplePaySetup = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "wave.3.right")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Optional: log Apple Pay on its own")
                            .font(.system(.callout, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Text("A one-time setup in Shortcuts. Then every tap to pay shows up here")
                            .font(.system(.subheadline))
                            .foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
            .padding(.top, 12)
            }

            VStack(spacing: 4) {
                Text("Your month will draw itself here")
                    .font(.system(.subheadline, weight: .semibold))
                Text("starting with your first expense")
                    .font(.system(.footnote))
            }
            .foregroundStyle(Palette.secondary)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: proxy.size.height - 10))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 10))
                    }
                    .stroke(Palette.ink.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                }
            }
            .padding(.top, 28)
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(Palette.secondary)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Palette.secondary.opacity(0.5), lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.system(.subheadline))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
        }
        .padding(16)
    }
}
