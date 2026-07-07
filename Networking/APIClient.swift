//
//  APIClient.swift
//  DualAgent
//
//  Created by Hermes Agent on 2026-07-06.
//

import Foundation

/// An actor that wraps URLSession with automatic cookie handling.
actor APIClient {
    /// Shared URLSession configured to store cookies in the shared HTTPCookieStorage.
    nonisolated let session: URLSession
    
    /// Creates an APIClient with a URLSession configured for cookie storage.
    nonisolated init() {
        let configuration = URLSessionConfiguration.default
        // Ensure cookies are stored in the shared HTTPCookieStorage (used by Alamofire, etc.)
        // and are accepted from the server.
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.httpShouldUsePipelining = true
        // Optional: configure timeouts, caching, etc.
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        
        session = URLSession(configuration: configuration)
    }
    
    /// Performs a data task and returns the decoded response.
    /// - Parameters:
    ///   - request: The URLRequest to perform.
    ///   - type: The type to decode the response data into.
    /// - Returns: The decoded object.
    /// - Throws: APIError.network, .http, or .decoding if the request fails.
    func decode<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            
            // Check for HTTP errors
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.network(URLError(.badServerResponse))
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.http(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            
            // Decode the response
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }
    
    /// Performs a data task and returns the raw data.
    /// - Parameter request: The URLRequest to perform.
    /// - Returns: The response data.
    /// - Throws: APIError.network or .http if the request fails.
    func data(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.network(URLError(.badServerResponse))
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.http(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }
    
    /// Performs a data task and returns nothing (for endpoints that return empty success).
    /// - Parameter request: The URLRequest to perform.
    /// - Throws: APIError.network or .http if the request fails.
    func run(_ request: URLRequest) async throws {
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.network(URLError(.badServerResponse))
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.http(httpResponse.statusCode, String(data: Data(), encoding: .utf8) ?? "")
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }
}