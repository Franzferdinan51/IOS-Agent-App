//
//  SSEClient.swift
//  DualAgent
//
//  Created by Hermes Agent on 2026-07-06.
//

import Foundation
import EventSource

/// A wrapper around LDSwiftEventSource to provide AsyncSequence functionality for SSE events.
@MainActor
final class SSEClient: @unchecked Sendable {
    private var eventSource: EventSource?
    private var continuation: AsyncStream<SSEEvent>.Continuation?
    private let stream: AsyncStream<SSEEvent>
    
    /// Creates a new SSEClient that connects to the given URL.
    /// - Parameter url: The URL to connect to for SSE events.
    init(url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 300 // 5 minutes timeout for long-running streams
        
        stream = AsyncStream { [weak self] continuation in
            self?.continuation = continuation
            
            // Create the event source
            let eventSource = EventSource(request: request)
            
            // Handle incoming events
            eventSource.on { [weak self] (command: EventSource.Command) in
                switch command {
                case .open:
                    print("SSE connection opened")
                case .meta(let meta):
                    print("SSE meta: \(meta)")
                case .openError(let error):
                    print("SSE open error: \(error)")
                    continuation.finish()
                case .message(let message):
                    // Parse the SSE message
                    let event = SSEEvent(
                        id: message.id,
                        event: message.event,
                        data: message.data
                    )
                    continuation.yield(event)
                case .closed:
                    print("SSE connection closed")
                    continuation.finish()
                }
            }
            
            // Start the connection
            eventSource.start()
            
            // Store reference to prevent deallocation
            self?.eventSource = eventSource
            
            // Cleanup when the stream is cancelled
            continuation.onTermination = { [weak eventSource] @Sendable _ in
                eventSource?.close()
                self?.eventSource = nil
                self?.continuation = nil
            }
        }
    }
    
    /// The async stream of SSE events.
    nonisolated var events: AsyncStream<SSEEvent> {
        stream
    }
    
    /// Closes the SSE connection.
    nonisolated func close() {
        eventSource?.close()
        eventSource = nil
        continuation?.finish()
        continuation = nil
    }
    
    deinit {
        close()
    }
}

/// Represents a single Server-Sent Event.
struct SSEEvent: Sendable {
    /// The event ID.
    let id: String?
    /// The event type (e.g., "token", "tool_call", etc.).
    let event: String?
    /// The event data payload.
    let data: String
}