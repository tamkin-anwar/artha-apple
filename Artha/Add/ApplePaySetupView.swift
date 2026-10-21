import SwiftUI

/// How to make every Apple Pay tap log itself. iOS doesn't let an app
/// create the Wallet automation for someone, so this walks through the
/// one-time setup in Shortcuts as plainly as possible.
struct ApplePaySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let steps: [(title: String, detail: String)] = [
        ("Open Shortcuts and start an automation",
         "Go to the Automation tab and tap the plus button."),
        ("Choose Transaction",
         "Pick the cards to include, then choose Run Immediately so it never asks first."),
        ("Add Artha's action",
         "Start a new blank automation, search for Artha, and add Log Apple Pay Purchase."),
        ("Fill in Amount and Merchant",
         "Tap Amount and choose Shortcut Input, then Amount. Do the same for Merchant."),
        ("Tap Done",
         "Your next Apple Pay purchase shows up in Activity, already sorted into a category."),
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
                    Text("Set it up once in Shortcuts. After that, every tap with Apple Pay logs itself in Artha, in the currency you paid in, without opening the app.")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

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
