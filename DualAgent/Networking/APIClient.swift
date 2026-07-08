import Foundation

/// A generic API client that wraps URLSession and handles authentication.
///
/// The client is a plain `final class` (not an `actor`) because all public
/// methods are already `async` and the underlying `URLSession` is itself
/// thread-safe. Treating it as an actor previously required `nonisolated(unsafe)`
/// on the singleton, which defeated the actor's protection without adding
/// any real isolation guarantees.
final class APIClient: @unchecked Sendable {
    /// Shared URL session configuration.
    static let shared = APIClient()

    private let session: URLSession
    private let configuration: URLSessionConfiguration

    private init() {
        configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        configuration.timeoutIntervalForRequest = AppConfig.requestTimeout
        configuration.timeoutIntervalForResource = AppConfig.requestTimeout
        configuration.waitsForConnectivity = false
        // Don't cache credentials / responses for an auth-bearing client.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    /// Auth credential to attach to outgoing requests. Set this on the shared
    /// instance when you have a cookie (Hermes) or a Bearer token (OpenClaw).
    var authorizationHeader: String? {
        get { session.configuration.httpAdditionalHeaders?["Authorization"] as? String }
        set {
            var headers = session.configuration.httpAdditionalHeaders ?? [:]
            if let v = newValue, !v.isEmpty {
                headers["Authorization"] = v
            } else {
                headers.removeValue(forKey: "Authorization")
            }
            session.configuration.httpAdditionalHeaders = headers
        }
    }

    /// Perform a request and decode the response.
    /// - Parameters:
    ///   - request: The URLRequest to perform.
    ///   - type: The type to decode the response into.
    /// - Returns: The decoded value.
    /// - Throws: APIError.network, .http, or .decoding.
    func request<T: Decodable>(_ request: URLRequest, decoding type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }

        try Self.validate(response: httpResponse, data: data)

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Perform a request that returns no data (e.g., DELETE).
    /// - Parameter request: The URLRequest to perform.
    /// - Throws: APIError.network or .http.
    func request(_ request: URLRequest) async throws {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }

        try Self.validate(response: httpResponse, data: data)
    }

    /// Perform a request and return raw data (e.g., for file downloads).
    /// - Parameter request: The URLRequest to perform.
    /// - Returns: The raw data received.
    /// - Throws: APIError.network or .http.
    func requestData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }

        try Self.validate(response: httpResponse, data: data)
        return data
    }

    private static func validate(response: HTTPURLResponse, data: Data) throws {
        let status = response.statusCode
        // 2xx — OK.
        if (200..<300).contains(status) { return }
        // 401 — surface a typed `unauthorized` so callers can route to login.
        if status == 401 {
            throw APIError.unauthorized
        }
        // 4xx/5xx — include the body in the error so the UI can show it.
        let body = String(data: data, encoding: .utf8) ?? ""
        throw APIError.http(status, body)
    }
}

/// Errors that can occur during API requests.
enum APIError: LocalizedError {
    case network(Error)
    case http(Int, String)
    case decoding(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .http(let status, let body):
            // Trim noisy HTML bodies down to one line for the UI.
            let trimmed = body
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .prefix(200)
            return "HTTP \(status): \(trimmed)"
        case .decoding(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized"
        }
    }
}