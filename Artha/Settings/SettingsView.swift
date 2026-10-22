import SwiftUI

/// Everything about the account, opened from your initials on Today. Apple's
/// guidance is that settings belong in an account view: easy to find, never
/// in the way. Only what someone would actually change lives here; the
/// time zone follows the iPhone on its own, the way the website follows
/// the browser, so it's shown but never asked for.
struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(MonthModel.self) private var month
    @Environment(\.dismiss) private var dismiss

    @State private var isChangingCurrency = false
    @State private var currencyError: String?
    @State private var showingApplePay = false
    @State private var showingDelete = false

    var body: some View {
        NavigationStack {
            List {
                if let user = session.user {
                    header(user)
                    account(user)
                    money(user)
                }
                applePay
                about
                signOut
            }
            .scrollContentBackground(.hidden)
            .background(Palette.ground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await session.refreshUser() }
        .sheet(isPresented: $showingApplePay) { ApplePaySetupView() }
        .sheet(isPresented: $showingDelete) { DeleteAccountView() }
        .presentationDragIndicator(.visible)
    }

    // MARK: Sections

    private func header(_ user: APIUser) -> some View {
        Section {
            VStack(spacing: 10) {
                Text(user.initials)
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 72, height: 72)
                    .background(Palette.raised, in: Circle())
                    .foregroundStyle(Palette.ink)
                VStack(spacing: 2) {
                    Text(user.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text(user.email ?? user.username)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        }
    }

    private func account(_ user: APIUser) -> some View {
        Section("Account") {
            NavigationLink {
                ProfileView(user: user)
            } label: {
                SettingsRow(symbol: "person", title: "Name and email")
            }
            NavigationLink {
                PasswordView()
            } label: {
                SettingsRow(symbol: "key", title: "Password")
            }
            NavigationLink {
                TwoFactorView()
            } label: {
                SettingsRow(symbol: "lock.shield", title: "Two-factor sign-in",
                            value: user.twoFactorEnabled ? "On" : "Off")
            }
        }
        .listRowBackground(Palette.surface)
    }

    private func money(_ user: APIUser) -> some View {
        Section {
            Picker(selection: Binding(get: { user.currency }, set: { change(currency: $0) })) {
                ForEach(SignUpView.currencies, id: \.self) { code in
                    Text(Self.currencyName(code)).tag(code)
                }
            } label: {
                SettingsRow(symbol: "dollarsign.circle", title: "Currency")
            }
            .pickerStyle(.menu)
            .tint(Palette.secondary)
            .disabled(isChangingCurrency)

            HStack {
                SettingsRow(symbol: "globe", title: "Time zone")
                Spacer()
                Text(TimeZone.current.localizedName(for: .generic, locale: .current) ?? TimeZone.current.identifier)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
        } header: {
            Text("Money")
        } footer: {
            if let currencyError {
                Text(currencyError).foregroundStyle(Palette.caution)
            } else {
                Text("Totals, budgets and Safe to Spend show in this currency. Each purchase keeps the currency it was paid in. The time zone follows your iPhone.")
            }
        }
        .listRowBackground(Palette.surface)
    }

    private var applePay: some View {
        Section {
            Button { showingApplePay = true } label: {
                HStack {
                    SettingsRow(symbol: "wave.3.right", title: "Apple Pay logging")
                    Spacer()
                    Text(month.applePay == nil ? "Not set up" : "On")
                        .foregroundStyle(Palette.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.secondary.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Palette.surface)
    }

    private var about: some View {
        Section {
            Link(destination: URL(string: "https://arthaapp.com/privacy")!) {
                SettingsRow(symbol: "hand.raised", title: "Privacy and security", external: true)
            }
            Link(destination: URL(string: "https://arthaapp.com")!) {
                SettingsRow(symbol: "safari", title: "Artha on the web", external: true)
            }
            HStack {
                SettingsRow(symbol: "info.circle", title: "Version")
                Spacer()
                Text(Self.version)
                    .foregroundStyle(Palette.secondary)
                    .monospacedDigit()
            }
        }
        .listRowBackground(Palette.surface)
    }

    private var signOut: some View {
        Section {
            Button("Sign out") {
                dismiss()
                Task { await session.signOut() }
            }
            .foregroundStyle(Palette.accent)
            Button("Delete account", role: .destructive) { showingDelete = true }
        }
        .listRowBackground(Palette.surface)
    }

    // MARK: Actions

    private func change(currency code: String) {
        guard code != session.user?.currency else { return }
        isChangingCurrency = true
        currencyError = nil
        Task {
            defer { isChangingCurrency = false }
            do {
                try await session.updateProfile(["currency": code])
            } catch let failure as APIError {
                currencyError = failure.message
            } catch {
                currencyError = "Artha couldn't change the currency. Try again in a moment."
            }
        }
    }

    static func currencyName(_ code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(name) (\(code))"
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(short) (\(build))"
    }
}

/// A settings row: a symbol in the accent color and a title, with an
/// optional value on the right.
struct SettingsRow: View {
    let symbol: String
    let title: String
    var value: String?
    var external = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(Palette.ink)
            if let value {
                Spacer()
                Text(value)
                    .foregroundStyle(Palette.secondary)
            }
            if external {
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.secondary.opacity(0.6))
            }
        }
    }
}

extension APIUser {
    /// "Tamkin Anwar", or the username when no name is set.
    var displayName: String {
        let name = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ")
        return name.isEmpty ? username : name
    }
}
