import SwiftUI

/// Sign in with an existing Artha account, or start a new one (SignUpView).
/// An account with two-factor sign-in gets a code step after the password,
/// the same order as the web login.
struct SignInView: View {
    @Environment(AppSession.self) private var session

    private enum Field { case username, password, code }

    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @State private var isWorking = false
    @State private var error: String?
    @State private var isSigningUp = false
    @FocusState private var focus: Field?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                OrbMark()
                    .frame(width: 84, height: 84)
                    .padding(.top, 72)
                Text("Artha")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 18)
                Text(needsCode ? "Enter the code from your authenticator app." : "Sign in with your Artha account.")
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)

                VStack(spacing: 0) {
                    if needsCode {
                        TextField("6-digit code or recovery code", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.asciiCapable)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focus, equals: .code)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            .fieldStyle()
                    } else {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focus, equals: .username)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                            .fieldStyle()
                        Divider().padding(.leading, 16)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            .fieldStyle()
                    }
                }
                .background(Palette.surface, in: .rect(cornerRadius: 18))
                .padding(.top, 32)

                if let error {
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.caution)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .padding(.top, 12)
                        .transition(.opacity)
                }

                Button(action: submit) {
                    ZStack {
                        if isWorking {
                            ProgressView().tint(Palette.onInverse)
                        } else {
                            Text(needsCode ? "Verify" : "Sign in")
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
                .padding(.top, 20)

                if needsCode {
                    Button("Use a different account") {
                        needsCode = false
                        code = ""
                        error = nil
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
                    .padding(.top, 8)
                } else {
                    HStack(spacing: 4) {
                        Text("New to Artha?")
                            .foregroundStyle(Palette.secondary)
                        Button("Create an account") { isSigningUp = true }
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.accent)
                    }
                    .font(.system(size: 15))
                    .frame(minHeight: 44)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 24)
            .animation(.snappy(duration: 0.3), value: needsCode)
            .animation(.snappy(duration: 0.3), value: error)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.ground)
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .sheet(isPresented: $isSigningUp) { SignUpView() }
        .alert("Artha", isPresented: noticeShown) {
            Button("OK") { session.notice = nil }
        } message: {
            Text(session.notice ?? "")
        }
    }

    /// A deletion that just started explains itself here, since deleting
    /// signs this iPhone out.
    private var noticeShown: Binding<Bool> {
        Binding(get: { session.notice != nil }, set: { if !$0 { session.notice = nil } })
    }

    private var canSubmit: Bool {
        guard !isWorking else { return false }
        return needsCode ? !code.trimmingCharacters(in: .whitespaces).isEmpty
                         : !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try await session.signIn(username: username.trimmingCharacters(in: .whitespaces),
                                         password: password,
                                         code: needsCode ? code.trimmingCharacters(in: .whitespaces) : nil)
            } catch APIError.twoFactorRequired {
                needsCode = true
                focus = .code
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't sign you in. Try again in a moment."
            }
        }
    }
}

extension View {
    /// A row in the grouped field cards on Sign In and Sign Up.
    func fieldStyle() -> some View {
        font(.system(size: 17))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
    }
}
