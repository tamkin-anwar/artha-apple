import SwiftUI

/// Ahead of pace: name what's driving it and offer one useful next step.
/// Amber, never red: this is information, not a scolding.
struct AheadCard: View {
    @Environment(MonthModel.self) private var month

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.caution)
                    .frame(width: 38, height: 38)
                    .background(Palette.raised, in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dining is running high")
                        .font(.system(size: 16, weight: .semibold))
                    Text("$446 so far, about $160 more than a usual October by now. At \(Money.whole(month.perDay)) a day, October still ends inside its budget.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Button("See dining") {}
                    .buttonStyle(CapsuleButtonStyle())
                Button("Set a dining limit") {}
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(16)
        .background(Palette.surface, in: .rect(cornerRadius: 20))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Over budget: two choices with their effects spelled out. Nothing
/// changes until one is picked.
struct OverOptions: View {
    @Environment(MonthModel.self) private var month

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Two ways to handle it")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 4)
            OptionRow(title: "Carry \(Money.whole(month.overBy)) into November",
                      detail: "November's safe to spend starts \(Money.whole(month.overBy)) lower")
            OptionRow(title: "Raise October's budget to \(Money.whole(month.budget + month.overBy))",
                      detail: "November stays as planned")
            Text("Nothing changes until you pick one.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
                .padding(.horizontal, 4)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct OptionRow: View {
    let title: String
    let detail: String

    var body: some View {
        Button {} label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Palette.surface, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

/// A brand-new account: three steps, then the month draws itself.
struct FirstDay: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Let's find your safe to spend")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Palette.ink)
            Text("Three quick steps. After that, Artha does the math every day.")
                .font(.system(size: 16))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 8)

            VStack(spacing: 0) {
                StepRow(number: 1, title: "Monthly budget", detail: "$3,400 a month", done: true, action: "Edit")
                Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1)
                StepRow(number: 2, title: "Bills you pay every month", detail: "Rent, phone, subscriptions", done: false, action: "Add")
                Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1)
                StepRow(number: 3, title: "Log Apple Pay automatically", detail: "Every tap becomes an expense", done: false, action: "Turn on")
            }
            .background(Palette.surface, in: .rect(cornerRadius: 22))
            .padding(.top, 22)

            VStack(spacing: 4) {
                Text("Your month will draw itself here")
                    .font(.system(size: 15, weight: .semibold))
                Text("starting with your first expense")
                    .font(.system(size: 13))
            }
            .foregroundStyle(Palette.secondary)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(alignment: .bottom) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 140))
                    path.addLine(to: CGPoint(x: 358, y: 10))
                }
                .stroke(Palette.ink.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
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
    let done: Bool
    let action: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if done {
                    Circle().fill(Palette.good)
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(Palette.secondary.opacity(0.5), lineWidth: 2)
                    Text("\(number)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            Button(action) {}
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(done ? Color.clear : (number == 2 ? Palette.inverse : Palette.raised), in: Capsule())
                .foregroundStyle(done ? Palette.accent : (number == 2 ? Palette.onInverse : Palette.ink))
        }
        .padding(16)
    }
}
