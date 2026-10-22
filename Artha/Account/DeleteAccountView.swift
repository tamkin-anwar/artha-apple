import SwiftUI

/// Deleting an account from inside the app (App Store guideline 5.1.1(v)
/// requires it for any app that lets you create one). It works exactly like
/// the web: confirm with the password, every device is signed out, and
/// there's a 30-day window where signing back in cancels it.
struct DeleteAccountView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    @FocusState private var passwordFocused: Bool

    private let points: [(symbol: String, text: String)] = [
        ("calendar", "Your account and everything in it is erased for good after 30 days."),
        ("arrow.uturn.backward", "Changed your mind? Sign in any time before then and nothing is lost."),
        ("iphone.and.arrow.forward", "Every device is signed out, this \(ThisDevice.name) included."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Delete your account")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Palette.ink)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(points, id: \.symbol) { point in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: point.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Palette.secondary)
                                    .frame(width: 22)
                                Text(point.text)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 18)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($passwordFocused)
                        .submitLabel(.done)
                        .onSubmit(submit)
                        .fieldStyle()
                        .background(Palette.surface, in: .rect(cornerRadius: 18))
                        .padding(.top, 28)
                    Text("Enter your password to confirm.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    if let error {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.caution)
                            .padding(.horizontal, 4)
                            .padding(.top, 14)
                            .transition(.opacity)
                    }

                    Button(role: .destructive, action: submit) {
                        ZStack {
                            if isWorking {
                                ProgressView().tint(.white)
                            } else {
                                Text("Delete account")
                            }
                        }
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.red, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)
                    .padding(.top, 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.snappy(duration: 0.3), value: error)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.ground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .interactiveDismissDisabled(isWorking)
        .presentationDragIndicator(.visible)
    }

    private var canSubmit: Bool { !isWorking && !password.isEmpty }

    private func submit() {
        guard canSubmit else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                // On success the session signs out, which closes this sheet
                // along with everything else.
                try await session.deleteAccount(password: password)
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't delete your account. Try again in a moment."
            }
        }
    }
}
