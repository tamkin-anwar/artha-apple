import SwiftUI

/// Create an Artha account without leaving the app. Asks for the same
/// things the web Register form does, plus the currency to show money in,
/// guessed from the phone's region. The password field is marked as a new
/// password, so iOS offers a strong one and saves it to Passwords for
/// arthaapp.com (the server's apple-app-site-association links the two),
/// and the same login then works on the web.
struct SignUpView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// The currencies Artha supports (utils.CURRENCY_CODES on the server).
    static let currencies = ["USD", "EUR", "GBP", "CAD", "AUD", "BDT"]

    private enum Field { case firstName, email, username, password }

    @State private var firstName = ""
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var currency = SignUpView.regionCurrency
    @State private var isWorking = false
    @State private var error: String?
    @FocusState private var focus: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Create your account")
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Palette.ink)
                    Text("No bank login and no ads. The same account works on arthaapp.com.")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)

                    VStack(spacing: 0) {
                        TextField("First name", text: $firstName)
                            .textContentType(.givenName)
                            .capitalizeWords()
                            .focused($focus, equals: .firstName)
                            .submitLabel(.next)
                            .onSubmit { focus = .email }
                            .fieldStyle()
                        Divider().padding(.leading, 16)
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboard(.email)
                            .autocorrectionDisabled()
                            .noAutocapitalization()
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .username }
                            .fieldStyle()
                        Divider().padding(.leading, 16)
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .noAutocapitalization()
                            .focused($focus, equals: .username)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                            .fieldStyle()
                        Divider().padding(.leading, 16)
                        SecureField("Password", text: $password)
                            .textContentType(.newPassword)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            .fieldStyle()
                    }
                    .background(Palette.surface, in: .rect(cornerRadius: 18))
                    .padding(.top, 28)

                    Text("At least 8 characters.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    HStack {
                        Text("Currency")
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Picker("Currency", selection: $currency) {
                            ForEach(Self.currencies, id: \.self) { code in
                                Text(Self.label(for: code)).tag(code)
                            }
                        }
                        .labelsHidden()
                        .tint(Palette.accent)
                        .fixedSize()
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 6)
                    .frame(minHeight: 54)
                    .background(Palette.surface, in: .rect(cornerRadius: 18))
                    .padding(.top, 20)

                    Text("Totals and budgets show in this currency. You can change it later on arthaapp.com.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    if let error {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.caution)
                            .padding(.horizontal, 4)
                            .padding(.top, 16)
                            .transition(.opacity)
                    }

                    Button(action: submit) {
                        ZStack {
                            if isWorking {
                                ProgressView().tint(Palette.onInverse)
                            } else {
                                Text("Create account")
                            }
                        }
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Palette.inverse, in: Capsule())
                        .foregroundStyle(Palette.onInverse)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)
                    .padding(.top, 24)

                    Link("How Artha handles your data", destination: URL(string: "https://arthaapp.com/privacy")!)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
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
        .onAppear { focus = .firstName }
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }
    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespaces) }

    private var canSubmit: Bool {
        !isWorking && !trimmedEmail.isEmpty && !trimmedUsername.isEmpty && password.count >= 8
    }

    private func submit() {
        guard canSubmit else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try await session.signUp(firstName: firstName.trimmingCharacters(in: .whitespaces),
                                         email: trimmedEmail, username: trimmedUsername,
                                         password: password, currency: currency)
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't create your account. Try again in a moment."
            }
        }
    }

    /// The phone region's currency when Artha supports it, otherwise USD.
    private static var regionCurrency: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return currencies.contains(code) ? code : "USD"
    }

    private static func label(for code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(name) (\(code))"
    }
}
