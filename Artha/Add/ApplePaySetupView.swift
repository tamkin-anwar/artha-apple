import SwiftUI

/// How to make every Apple Pay tap log itself. iOS doesn't let an app
/// create the Wallet automation for someone, so this walks through the
/// one-time setup in Shortcuts with the exact names on screen (iOS 26
/// renamed the trigger from Transaction to Wallet), and once a purchase
/// has come through it says so, instead of leaving people to wonder.
struct ApplePaySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(MonthModel.self) private var month

    private let steps: [(title: String, detail: String)] = [
        ("Start a new automation",
         "In Shortcuts, tap Automation at the bottom, then the plus button."),
        ("Choose Wallet",
         "It's called Transaction before iOS 26. Pick the cards to include, choose Run Immediately, then tap Next."),
        ("Add Artha's Log Purchase",
         "Tap New Blank Automation, then Add Action. Search for Artha and tap Log Purchase."),
        ("Connect Amount and Merchant",
         "Tap Amount and choose Shortcut Input, then Amount. Tap Merchant and choose Shortcut Input, then Merchant."),
        ("Tap Done",
         "If your iPhone asks whether Artha can run, choose Always Allow. Your next tap to pay shows up on Today, ready for a quick review."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    Text("Log Apple Pay purchases automatically")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 14)
                    Text("Set it up once in Shortcuts. After that, every tap with Apple Pay logs itself in Artha, in the currency you paid in, without opening the app. It takes about two minutes.")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    if let status = month.applePay {
                        WorkingBanner(status: status)
                            .padding(.top, 20)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 14) {
                                Text("\(index + 1)")
                                    .font(.system(size: 14, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.onInverse)
                                    .frame(width: 28, height: 28)
                                    .background(Palette.inverse, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(step.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Palette.ink)
                                    Text(step.detail)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Palette.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 12)
                            .accessibilityElement(children: .combine)
                            if index < steps.count - 1 {
                                Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1).padding(.leading, 42)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(Palette.surface, in: .rect(cornerRadius: 20))
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 10) {
                        Tip(symbol: "antenna.radiowaves.left.and.right",
                            text: "If a purchase doesn't show up, check Settings, then Cellular, and make sure Wallet can use cellular data.")
                        Tip(symbol: "dollarsign.arrow.circlepath",
                            text: "A purchase in a currency Artha doesn't support yet isn't logged, so nothing is ever recorded in the wrong currency.")
                        Tip(symbol: "hand.raised",
                            text: "If Artha asks for permission each time you pay, edit the automation and make sure Run Immediately is on.")
                        Tip(symbol: "lock",
                            text: "Artha only receives the amount and merchant Wallet shares with the automation. It never sees your card number.")
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Palette.ground)
            .safeAreaInset(edge: .bottom) {
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Text("Open Shortcuts")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(Palette.inverse, in: Capsule())
                        .foregroundStyle(Palette.onInverse)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(Palette.ground)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    /// Proof it works: the newest purchase Apple Pay logged on its own.
    private struct WorkingBanner: View {
        let status: TodaySummary.ApplePayStatus

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.good)
                VStack(alignment: .leading, spacing: 2) {
                    Text("It's working")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Palette.good.opacity(0.12), in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .combine)
        }

        private var detail: String {
            let day = Date.apiDay(status.date ?? "")?.formatted(.dateTime.month(.abbreviated).day()) ?? ""
            let last = day.isEmpty ? "Last logged \(status.description)." : "Last logged \(status.description) on \(day)."
            return status.count == 1 ? "\(last) 1 purchase so far." : "\(last) \(status.count) purchases so far."
        }
    }

    private struct Tip: View {
        let symbol: String
        let text: String

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 20)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
