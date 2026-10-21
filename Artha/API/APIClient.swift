import Foundation

/// What can go wrong talking to Artha, with a message written for the
/// person. The server's own messages are already safe to show as-is.
nonisolated enum APIError: Error, Sendable {
    case unauthorized(String)
    case twoFactorRequired(String)
    case invalidCode(String)
    case rejected(code: String, message: String)
    case offline

    var message: String {
        switch self {
        case .unauthorized(let message), .twoFactorRequired(let message), .invalidCode(let message):
            message
        case .rejected(_, let message):
            message
        case .offline:
            "Artha can't reach the server. Check your connection and try again."
        }
    }
}

/// Talks to the Artha server's /api/v1 with the signed-in device's bearer
/// token. In the simulator that's the local dev server (the Mac's own
/// localhost); on a real iPhone it's arthaapp.com.
@MainActor
final class APIClient {
    static let baseURL: URL = {
        #if targetEnvironment(simulator)
        URL(string: "http://localhost:5050/api/v1/")!
        #else
        URL(string: "https://arthaapp.com/api/v1/")!
        #endif
    }()

    var token: String?

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func get<T: Decodable>(_ path: String) async throws -> T {
        try decoder.decode(T.self, from: try await send(path, method: "GET"))
    }

    func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try decoder.decode(T.self, from: try await send(path, method: "POST", body: body))
    }

    func delete(_ path: String) async throws {
        _ = try await send(path, method: "DELETE")
    }

    private func send(_ path: String, method: String, body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.offline
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200..<300).contains(status) else { return data }

        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = payload?["error"] as? String ?? "server_error"
        let message = payload?["message"] as? String ?? "Something went wrong on Artha's side. Try again in a moment."
        switch (status, code) {
        case (401, "two_factor_required"): throw APIError.twoFactorRequired(message)
        case (401, "invalid_code"): throw APIError.invalidCode(message)
        case (401, "unauthorized"): throw APIError.unauthorized(message)
        default: throw APIError.rejected(code: code, message: message)
        }
    }
}
