import SwiftUI

/// First name, last name and email, saved with the same rules as the web.
struct ProfileView: View {
    let user: APIUser

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("First name", text: $firstName)
                    .textContentType(.givenName)
                TextField("Last name", text: $lastName)
                    .textContentType(.familyName)
            }
            .listRowBackground(Palette.surface)
            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } footer: {
                FormFooter(error: error, note: "Password resets and the deletion email go here.")
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .navigationTitle("Name and email")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                SaveButton(isSaving: isSaving, enabled: changes.isEmpty == false, action: save)
            }
        }
        .onAppear {
            firstName = user.firstName ?? ""
            lastName = user.lastName ?? ""
            email = user.email ?? ""
        }
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
    }

    private var changes: [String: Any] {
        var changes: [String: Any] = [:]
        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last = lastName.trimmingCharacters(in: .whitespaces)
        let mail = email.trimmingCharacters(in: .whitespaces)
        if first != (user.firstName ?? "") { changes["first_name"] = first }
        if last != (user.lastName ?? "") { changes["last_name"] = last }
        if mail.lowercased() != (user.email ?? "") { changes["email"] = mail }
        return changes
    }

    private func save() {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await session.updateProfile(changes)
                dismiss()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't save that. Try again in a moment."
            }
        }
    }
}

/// A new password. The server signs every other device out; this one stays
/// signed in with a fresh key, and iOS offers to update the saved password.
struct PasswordView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                SecureField("Current password", text: $current)
                    .textContentType(.password)
                SecureField("New password", text: $new)
                    .textContentType(.newPassword)
            } footer: {
                FormFooter(error: error,
                           note: "At least 8 characters. Changing it signs Artha out everywhere else, on the web and other devices.")
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .navigationTitle("Password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                SaveButton(isSaving: isSaving, enabled: !current.isEmpty && new.count >= 8, action: save)
            }
        }
        .sensoryFeedback(.error, trigger: error) { _, value in value != nil }
    }

    private func save() {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await session.changePassword(current: current, new: new)
                dismiss()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't change your password. Try again in a moment."
            }
        }
    }
}

/// Two-factor sign-in, on or off. Turning it on hands the setup link to
/// the iPhone's Passwords app (or another authenticator), which then
/// fills in the codes when signing in, so it costs nothing day to day.
struct TwoFactorView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.openURL) private var openURL

    @State private var setup: TwoFactorSetup?
    @State private var code = ""
    @State private var password = ""
    @State private var recoveryCodes: [String]?
    @State private var isWorking = false
    @State private var error: String?
    @State private var copied = false

    private var isOn: Bool { session.user?.twoFactorEnabled ?? false }

    var body: some View {
        Form {
            if let recoveryCodes {
                codesSection(recoveryCodes)
            } else if isOn {
                turnOffSection
            } else if let setup {
                setupSection(setup)
            } else {
                introSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .navigationTitle("Two-factor sign-in")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.error, trigger: error) { _, value in value != nil }
        .sensoryFeedback(.success, trigger: recoveryCodes != nil)
        .animation(.snappy(duration: 0.3), value: setup?.secret)
        .animation(.snappy(duration: 0.3), value: recoveryCodes)
    }

    // MARK: Off

    private var introSection: some View {
        Section {
            Text("Signing in will also ask for a six-digit code from your phone, so a stolen password alone can't get in. The Passwords app on your iPhone can hold the code and fill it in for you.")
                .foregroundStyle(Palette.ink)
                .padding(.vertical, 4)
            Button(action: start) {
                ProgressLabel(title: "Turn on", isWorking: isWorking)
            }
            .disabled(isWorking)
        } footer: {
            FormFooter(error: error, note: nil)
        }
        .listRowBackground(Palette.surface)
    }

    private func setupSection(_ setup: TwoFactorSetup) -> some View {
        Group {
            Section {
                Button {
                    if let url = URL(string: setup.uri) { openURL(url) }
                } label: {
                    Label("Add to Passwords", systemImage: "key.viewfinder")
                }
                Button {
                    UIPasteboard.general.string = setup.secret
                    copied = true
                } label: {
                    Label(copied ? "Setup key copied" : "Copy setup key", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Text(Self.grouped(setup.secret))
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Palette.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("1. Add Artha to an authenticator")
            } footer: {
                Text("Add to Passwords opens your iPhone's Passwords app, or another authenticator if you use one. You can also paste the setup key into it.")
            }
            .listRowBackground(Palette.surface)

            Section {
                TextField("6-digit code", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                Button(action: confirm) {
                    ProgressLabel(title: "Turn on", isWorking: isWorking)
                }
                .disabled(isWorking || code.trimmingCharacters(in: .whitespaces).count < 6)
            } header: {
                Text("2. Enter the code it shows")
            } footer: {
                FormFooter(error: error, note: nil)
            }
            .listRowBackground(Palette.surface)
        }
    }

    private func codesSection(_ codes: [String]) -> some View {
        Section {
            Text("Two-factor sign-in is on. If you ever lose your phone, each of these codes signs you in once. Keep them somewhere safe; Artha won't show them again.")
                .foregroundStyle(Palette.ink)
                .padding(.vertical, 4)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(codes, id: \.self) { code in
                    Text(code)
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                }
            }
            .padding(.vertical, 6)
            .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = codes.joined(separator: "\n")
                copied = true
            } label: {
                Label(copied ? "Codes copied" : "Copy codes", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            ShareLink(item: "Artha recovery codes\n" + codes.joined(separator: "\n")) {
                Label("Save or share", systemImage: "square.and.arrow.up")
            }
        }
        .listRowBackground(Palette.surface)
        .onAppear { copied = false }
    }

    // MARK: On

    private var turnOffSection: some View {
        Section {
            Text("Two-factor sign-in is on. To turn it off, confirm with your password and a current code, or one of your recovery codes.")
                .foregroundStyle(Palette.ink)
                .padding(.vertical, 4)
            SecureField("Password", text: $password)
                .textContentType(.password)
            TextField("Code or recovery code", text: $code)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button(role: .destructive, action: turnOff) {
                ProgressLabel(title: "Turn off", isWorking: isWorking)
            }
            .disabled(isWorking || password.isEmpty || code.trimmingCharacters(in: .whitespaces).isEmpty)
        } footer: {
            FormFooter(error: error, note: nil)
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: Actions

    private func start() {
        run {
            setup = try await session.startTwoFactor()
            copied = false
        }
    }

    private func confirm() {
        guard let setup else { return }
        run {
            recoveryCodes = try await session.enableTwoFactor(secret: setup.secret,
                                                              code: code.trimmingCharacters(in: .whitespaces))
            copied = false
            code = ""
        }
    }

    private func turnOff() {
        run {
            try await session.disableTwoFactor(password: password, code: code.trimmingCharacters(in: .whitespaces))
            password = ""
            code = ""
            setup = nil
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try await work()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn't do that. Try again in a moment."
            }
        }
    }

    /// "ABCD EFGH IJKL ..." so the key can be read or typed in chunks.
    static func grouped(_ key: String) -> String {
        stride(from: 0, to: key.count, by: 4).map { start in
            let lower = key.index(key.startIndex, offsetBy: start)
            let upper = key.index(lower, offsetBy: 4, limitedBy: key.endIndex) ?? key.endIndex
            return String(key[lower..<upper])
        }.joined(separator: " ")
    }
}

// MARK: - Pieces

private struct FormFooter: View {
    let error: String?
    let note: String?

    var body: some View {
        if let error {
            Text(error).foregroundStyle(Palette.caution)
        } else if let note {
            Text(note)
        }
    }
}

private struct SaveButton: View {
    let isSaving: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        if isSaving {
            ProgressView()
        } else {
            Button("Save", action: action)
                .disabled(!enabled)
        }
    }
}

private struct ProgressLabel: View {
    let title: String
    let isWorking: Bool

    var body: some View {
        HStack {
            Text(title)
            if isWorking {
                Spacer()
                ProgressView()
            }
        }
    }
}
