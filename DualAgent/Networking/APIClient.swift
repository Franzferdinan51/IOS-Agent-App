import Foundation

/// A generic API client that wraps URLSession and provides request/response handling.
actor APIClient {
    /// The shared URLSession configuration.
    private let session: URLSession
    
    /// Base URL for the API (without trailing slash).
    private let baseURL: URL
    
    /// Optional: a delegate to handle authentication challenges (e.g., for self-signed certs in dev).
    weak var delegate: URLSessionDelegate?
    
    /// Initialize the APIClient.
    /// - Parameters:
    ///   - baseURL: The base URL of the API (e.g., https://example.com).
    ///   - configuration: Optional URLSessionConfiguration. If nil, uses the default.
    ///   - delegate: Optional URLSessionDelegate for custom handling (e.g., SSL pinning).
    init(baseURL: URL, configuration: URLSessionConfiguration? = nil, delegate: URLSessionDelegate? = nil) {
        self.baseURL = baseURL
        let config = configuration ?? URLSessionConfiguration.default
        // We want to handle cookies automatically (for HMAC auth in Hermes).
        // The default configuration already accepts cookies, but we ensure it's set.
        config.httpCookieAcceptPolicy = .always
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
    
    /// Deinitialize and invalidate the session.
    deinit {
        // Invalidate the session to cancel any ongoing tasks.
        self.session.invalidateAndCancel()
    }
    
    /// Perform a request and decode the response.
    /// - Parameters:
    ///   - endpoint: The endpoint to call (will be appended to baseURL).
    ///   - method: The HTTP method.
    ///   - headers: Additional HTTP headers.
    ///   - body: The body to encode and send (for POST, PUT, etc.).
    ///   - queryItems: URL query parameters.
    ///   - responseType: The type to decode the response into.
    /// - Returns: The decoded response.
    /// - Throws: An error if the request fails or decoding fails.
    func request<Response: Decodable>(
        to endpoint: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Encodable? = nil,
        queryItems: [URLQueryItem] = [],
        responseType: Response.Type = Response.self
    ) async throws -> Response {
        // Build the URL.
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(epochPath: endpoint), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems
        }
        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }
        
        // Create the request.
        var request = URLRequest(url: url)
        request.httpMethod = method
        // Add headers.
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Encode body if provided.
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
            // Ensure content-type is set if not already present.
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        
        // Perform the request.
        let (data, response) = try await session.data(for: request)
        
        // Check for HTTP error.
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        // Handle non-2xx status codes.
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to decode error message if possible.
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
        
        // Decode the response.
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
    
    /// Perform a request that returns raw data (e.g., for file downloads or SSE).
    /// - Parameters: same as `request` but without decoding.
    /// - Returns: The raw data received.
    /// - Throws: An error if the request fails.
    func rawRequest(
        to endpoint: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Encodable? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> Data {
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(epochPath: endpoint), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems
        }
        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
        return data
    }
    
    /// Helper to append a path component safely (avoids double slashes).
    private extension URL {
        func appendingPathComponent(epochPath: String) -> URL {
            // Ensure we don't end up with a double slash if the base URL already has a trailing slash.
            var path = epochPath
            if path.hasPrefix("/") {
                path.removeFirst()
            }
            return appendingPathComponent(path)
        }
    }
}

/// Errors that can occur during API requests.
enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data)
    case decodingError(Error)
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let data):
            if let str = String(data: data, encoding: .utf8) {
                return "HTTP error \(statusCode): \(str)"
            } else {
                return "HTTP error \(statusCode)"
            }
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .unknownError(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}