import Foundation
import Observation

/// Whether this device is signed in, who to, and the calls that change
/// that. Owns the API client and the month Today shows.
@Observable
final class AppSession {
    enum Phase { case checking, signedOut, signedIn }

    private(set) var phase: Phase = .checking
    private(set) var user: APIUser?
    private(set) var isRefreshing = false
    /// Shown on Today when the latest refresh failed; the last good data
    /// stays on screen underneath it.
    private(set) var refreshError: String?
    /// One-time note after a sign-in that canceled a pending deletion.
    var notice: String?

    let month = MonthModel()
    private let api = APIClient()

    func start() async {
        guard phase == .checking else { return }
        guard let token = Keychain.read(account: Keychain.tokenAccount) else {
            phase = .signedOut
            return
        }
        api.token = token
        phase = .signedIn
        await refresh()
    }

    /// Throws `.twoFactorRequired` when the account needs a code; call
    /// again with `code` set.
    func signIn(username: String, password: String, code: String?) async throws {
        var body: [String: Any] = ["username": username, "password": password, "device_name": deviceName]
        if let code, !code.isEmpty { body["code"] = code }
        let response: SessionResponse = try await api.post("sessions", body: body)
        Keychain.save(response.token, account: Keychain.tokenAccount)
        api.token = response.token
        user = response.user
        if response.deletionCanceled {
            notice = "Welcome back. Your account deletion has been canceled."
        }
        phase = .signedIn
        await refresh()
    }

    func signOut() async {
        try? await api.delete("sessions/current")
        signOutLocally()
    }

    func refresh() async {
        guard phase == .signedIn else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if user == nil {
                let envelope: UserEnvelope = try await api.get("me")
                user = envelope.user
            }
            let summary: TodaySummary = try await api.get("today")
            month.apply(summary)
            refreshError = nil
        } catch APIError.unauthorized {
            signOutLocally()
        } catch let error as APIError {
            refreshError = error.message
        } catch {
            refreshError = "Artha couldn't read today's numbers. Pull down to try again."
        }
    }

    func addTransaction(description: String, amount: Decimal, type: String) async throws {
        let body: [String: Any] = [
            "description": description,
            "amount": NSDecimalNumber(decimal: amount).stringValue,
            "type": type,
            "currency": month.currencyCode,
        ]
        let _: TransactionEnvelope = try await api.post("transactions", body: body)
        month.noteAdded()
        await refresh()
    }

    private func signOutLocally() {
        Keychain.delete(account: Keychain.tokenAccount)
        api.token = nil
        user = nil
        month.clear()
        refreshError = nil
        phase = .signedOut
    }

    private var deviceName: String {
        #if targetEnvironment(simulator)
        "iPhone Simulator"
        #else
        "iPhone"
        #endif
    }
}
