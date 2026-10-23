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
/// token. In the simulator, and in a debug build of the Mac app (both run
/// on the development Mac), that's the local dev server; on a real iPhone
/// or iPad, and in the Mac app people download, it's arthaapp.com.
@MainActor
final class APIClient {
    static let baseURL: URL = {
        #if targetEnvironment(simulator) || (os(macOS) && DEBUG)
        URL(string: "http://localhost:5050/api/v1/")!
        #else
        URL(string: "https://arthaapp.com/api/v1/")!
        #endif
    }()

    var token: String?

    /// No URL cache: the system's shared one would keep copies of people's
    /// financial responses on disk outside our protected ResponseCache, and
    /// could hand back a stale month. Every request goes to the server;
    /// ResponseCache is what makes launch instant.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func get<T: Decodable>(_ path: String) async throws -> T {
        try decoder.decode(T.self, from: try await send(path, method: "GET"))
    }

    /// Like `get`, but also hands back the raw response so it can be kept
    /// on disk (ResponseCache) and shown instantly on the next launch.
    func fetch<T: Decodable>(_ path: String) async throws -> (T, Data) {
        let data = try await send(path, method: "GET")
        return (try decoder.decode(T.self, from: data), data)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder.decode(type, from: data)
    }

    func put(_ path: String, body: [String: Any]) async throws {
        _ = try await send(path, method: "PUT", body: body)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try decoder.decode(T.self, from: try await send(path, method: "POST", body: body))
    }

    /// A POST whose answer has no body worth reading (204 No Content).
    func post(_ path: String, body: [String: Any]) async throws {
        _ = try await send(path, method: "POST", body: body)
    }

    func patch<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try decoder.decode(T.self, from: try await send(path, method: "PATCH", body: body))
    }

    /// Like `patch`, but also hands back the raw response to keep on disk.
    func patchKeeping<T: Decodable>(_ path: String, body: [String: Any]) async throws -> (T, Data) {
        let data = try await send(path, method: "PATCH", body: body)
        return (try decoder.decode(T.self, from: data), data)
    }

    func delete(_ path: String) async throws {
        _ = try await send(path, method: "DELETE")
    }

    func delete<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try decoder.decode(T.self, from: try await send(path, method: "DELETE", body: body))
    }

    /// Uploads one file as multipart/form-data (a bank statement), with any
    /// plain form fields alongside. The file goes straight from memory into
    /// the request; nothing is written to disk on the way.
    func upload<T: Decodable>(_ path: String, file: Data, field: String, filename: String, mimeType: String,
                              fields: [String: String] = [:]) async throws -> T {
        let boundary = "artha-\(UUID().uuidString)"
        var body = Data()
        func line(_ text: String) { body.append(Data((text + "\r\n").utf8)) }
        for (name, value) in fields {
            line("--\(boundary)")
            line("Content-Disposition: form-data; name=\"\(name)\"")
            line("")
            line(value)
        }
        let safeName = filename.replacingOccurrences(of: "\"", with: "")
        line("--\(boundary)")
        line("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(safeName)\"")
        line("Content-Type: \(mimeType)")
        line("")
        body.append(file)
        line("")
        line("--\(boundary)--")
        let data = try await send(path, method: "POST", raw: (body, "multipart/form-data; boundary=\(boundary)"), timeout: 90)
        return try decoder.decode(T.self, from: data)
    }

    private func send(_ path: String, method: String, body: [String: Any]? = nil,
                      raw: (Data, String)? = nil, timeout: TimeInterval = 20) async throws -> Data {
        // `path` may carry its own query string ("transactions?q=coffee"),
        // which appending(path:) would percent-encode into the path itself.
        guard let url = URL(string: path, relativeTo: Self.baseURL) else { throw APIError.offline }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if let (data, contentType) = raw {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
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
