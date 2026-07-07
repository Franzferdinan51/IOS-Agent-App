//
//  APIError.swift
//  DualAgent
//
//  Created by Hermes Agent on 2026-07-06.
//

import Foundation

/// API errors that can occur during network requests.
enum APIError: LocalizedError {
    case network(Error)
    case http(Int, String)
    case decoding(Error)
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .http(let statusCode, let body):
            return "HTTP \(statusCode): \(body)"
        case .decoding(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication required"
        }
    }
}