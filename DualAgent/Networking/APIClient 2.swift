import Foundation

/// A generic API client that wraps URLSession and handles authentication.
actor APIClient {
    /// Shared URL session configuration.
    nonisolated(unsafe) static let shared = APIClient()
    
    private let session: URLSession
    private let configuration: URLSessionConfiguration
    
    private init() {
        configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        configuration.timeoutIntervalForRequest = AppConfig.requestTimeout
        configuration.timeoutIntervalForResource = AppConfig.requestTimeout
        session = URLSession(configuration: configuration)
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
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(httpResponse.statusCode, body)
        }
        
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
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let data = try? await session.data(for: request)
            let body = String(data: data?.0 ?? Data ?? .utf8) ?? ""
            throw APIError.http(httpResponse.statusCode, body)
        }
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
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(httpResponse.statusCode, body)
        }
        
        return data
    }
}

/// Errors that can occur during API requests.
enum APIError: LocalizedError {
    case network(Error)
    case http(Int, String)
    case decoding(Error)
    
    var errorDescription: String? {
        switch self {
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .http(let status, let body):
            return "HTTP \(status): \(body)"
        case .decoding(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}