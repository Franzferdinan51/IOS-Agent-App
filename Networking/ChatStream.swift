//
//  ChatStream.swift
//  DualAgent
//
//  Created by Hermes Agent on 2026-07-06.
//

import Foundation

/// Represents a chat event from the server-side streaming API.
enum ChatEvent: Sendable {
    case token(String)
    case toolCall(String, [String: Any]) // toolName, arguments
    case toolResult(String, Any) // toolName, result
    case reasoning(String)
    case streamEnd
    case error(String)
    case cancel
    
    init(from sseEvent: SSEEvent) throws {
        guard let eventType = sseEvent.event else {
            throw NSError(domain: "ChatEvent", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing event type"])
        }
        
        switch eventType {
        case "token":
            self = .token(sseEvent.data)
        case "tool_call":
            // Parse the tool call data (expected to be JSON)
            if let data = sseEvent.data.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               let dict = json as? [String: Any],
               let toolName = dict["tool"] as? String,
               let arguments = dict["arguments"] as? [String: Any] {
                self = .toolCall(toolName, arguments)
            } else {
                throw NSError(domain: "ChatEvent", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid tool_call data"])
            }
        case "tool_result":
            // Parse the tool result data
            if let data = sseEvent.data.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               let dict = json as? [String: Any],
               let toolName = dict["tool"] as? String,
               let result = dict["result"] {
                self = .toolResult(toolName, result)
            } else {
                throw NSError(domain: "ChatEvent", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid tool_result data"])
            }
        case "reasoning":
            self = .reasoning(sseEvent.data)
        case "stream_end":
            self = .streamEnd
        case "error":
            self = .error(sseEvent.data)
        case "cancel":
            self = .cancel
        default:
            throw NSError(domain: "ChatEvent", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unknown event type: \(eventType)"])
        }
    }
}

/// Provides an AsyncSequence of ChatEvent for chat streaming.
final class ChatStream: @unchecked Sendable {
    private let sseClient: SSEClient
    private var iterator: AsyncStream<SSEEvent>.Iterator?
    
    /// Creates a ChatStream that connects to the given SSE URL.
    /// - Parameter url: The SSE endpoint URL.
    init(url: URL) {
        self.sseClient = SSEClient(url: url)
        self.iterator = sseClient.events.makeIterator()
    }
    
    /// Provides an async iterator for chat events.
    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: iterator!)
    }
    
    /// An async iterator for ChatEvent.
    struct AsyncIterator: AsyncIteratorProtocol {
        private var iterator: AsyncStream<SSEEvent>.Iterator
        
        init(iterator: AsyncStream<SSEEvent>.Iterator) {
            self.iterator = iterator
        }
        
        mutating func next() async throws -> ChatEvent? {
            guard let sseEvent = try await iterator.next() else {
                return nil
            }
            
            do {
                return try ChatEvent(from: sseEvent)
            } catch {
                // If we can't parse the event, return it as an error event
                return .error("Failed to parse SSE event: \(error.localizedDescription)")
            }
        }
    }
    
    /// Closes the underlying SSE connection.
    func close() {
        sseClient.close()
    }
}