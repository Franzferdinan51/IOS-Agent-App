import Foundation

/// Bridges raw SSE or WebSocket events into the unified `ChatEvent` stream.
///
/// Use `ChatStream.bridge(sse:)` for Server-Sent Events and `ChatStream.bridge(ws:)` for
/// WebSocket connections. Both return an `AsyncThrowingStream<ChatEvent, Error>` that callers
/// can iterate with `for try await`.
enum ChatStream {

    // MARK: - SSE Bridge

    /// Wraps an `AsyncSequence` of raw SSE events and parses them into `ChatEvent`s.
    ///
    /// Each `data:` field in an SSE message is decoded as a JSON fragment.
    /// Plain text `data:` lines are treated as incremental token content.
    ///
    /// - Parameters:
    ///   - events: The raw SSE event stream.
    ///   - streamId: The stream identifier (used only for debugging context).
    /// - Returns: An `AsyncSequence` of `ChatEvent`.
    static func bridge<S: AsyncSequence>(sse events: S, streamId: String) -> AsyncThrowingStream<ChatEvent, Error>
    where S.Element == Result<SSEClient.Event, Error>
    {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await result in events {
                        switch result {
                        case .success(let event):
                            if let chatEvent = parse(sseEvent: event) {
                                continuation.yield(chatEvent)
                            }
                        case .failure(let error):
                            continuation.yield(.error(error))
                        }
                    }
                    continuation.yield(.streamEnd)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                // Cleanup is handled by the caller who owns the SSEClient instance.
            }
        }
    }

    // MARK: - WebSocket Bridge

    /// Wraps an `AsyncSequence` of WebSocket messages and parses them into `ChatEvent`s.
    ///
    /// Expected message format: JSON-encoded `ChatEvent` objects, one per text or data frame.
    /// Plain text frames are treated as incremental token content.
    ///
    /// - Parameters:
    ///   - messages: The raw WebSocket message stream.
    ///   - streamId: The stream identifier (used only for debugging context).
    /// - Returns: An `AsyncSequence` of `ChatEvent`.
    static func bridge<S: AsyncSequence>(ws messages: S, streamId: String) -> AsyncThrowingStream<ChatEvent, Error>
    where S.Element == Result<WSClient.Message, Error>
    {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await result in messages {
                        switch result {
                        case .success(let msg):
                            if let chatEvent = parse(wsMessage: msg) {
                                continuation.yield(chatEvent)
                            }
                        case .failure(let error):
                            continuation.yield(.error(error))
                        }
                    }
                    continuation.yield(.streamEnd)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                // Cleanup is handled by the caller who owns the WSClient instance.
            }
        }
    }

    // MARK: - Parsing

    /// Parse a raw SSE `Event` into a `ChatEvent`, or `nil` if the event should be skipped.
    ///
    /// Supports two formats:
    /// - Named event type (e.g. `event: chat`): full JSON body in `data` field.
    /// - Default `message` event: raw text or JSON fragment in `data` field.
    private static func parse(sseEvent event: SSEClient.Event) -> ChatEvent? {
        // Comment line (starts with `:`) — ignore.
        if event.data == nil && event.event == nil && event.id == nil {
            return nil
        }

        // Named event: decode the structured JSON body.
        if let eventType = event.event, !eventType.isEmpty {
            if let data = event.data, let jsonData = data.data(using: .utf8) {
                return decodeChatEvent(from: jsonData)
            }
            return nil
        }

        // Default "message" event: raw data field.
        guard let data = event.data else { return nil }

        // Empty data on default event may signal stream end in some SSE protocols.
        if data.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }

        // Try JSON decode first (structured event format).
        if let jsonData = data.data(using: .utf8),
           let event = try? JSONDecoder().decode(ChatEvent.self, from: jsonData) {
            return event
        }

        // Fall back: treat raw string as a plain token.
        return .token(data)
    }

    /// Parse a raw WebSocket `Message` into a `ChatEvent`, or `nil` if the message is
    /// a protocol-level frame (ping/pong) that should not surface as a chat event.
    private static func parse(wsMessage msg: WSClient.Message) -> ChatEvent? {
        switch msg {
        case .text(let text):
            guard let data = text.data(using: .utf8) else { return nil }
            return decodeChatEvent(from: data)

        case .data(let data):
            return decodeChatEvent(from: data)

        case .disconnected:
            return .streamEnd

        case .ping, .pong:
            // Protocol-level ping/pong frames — not user-facing chat events.
            return nil
        }
    }

    /// Attempt to decode a `ChatEvent` from raw JSON data.
    ///
    /// Tries the structured `ChatEvent` Codable format first, then falls back to a simple
    /// `{"content": "..."}` dict for raw token strings.
    private static func decodeChatEvent(from data: Data) -> ChatEvent? {
        // Primary: structured ChatEvent JSON.
        if let event = try? JSONDecoder().decode(ChatEvent.self, from: data) {
            return event
        }

        // Secondary: simple `{"content": "token string"}` fallback.
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let content = dict["content"] as? String {
            return .token(content)
        }

        // Last resort: treat raw UTF-8 bytes as a plain token.
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return .token(text)
        }

        return nil
    }
}

// MARK: - Convenience Builders

/// Extension to make it easy to build a ChatEvent stream from an SSE endpoint.
extension SSEClient {
    /// Creates a `ChatEvent` stream from a given SSE URL.
    ///
    /// Example:
    /// ```swift
    /// let client = SSEClient()
    /// client.setAccessToken(token)
    /// let chatEvents = client.chatEvents(from: url, streamId: "abc")
    /// for try await event in chatEvents { ... }
    /// client.stop()
    /// ```
    ///
    /// - Parameters:
    ///   - url: The SSE endpoint URL.
    ///   - streamId: The stream identifier (used for logging/debugging).
    /// - Returns: An `AsyncThrowingStream` of `ChatEvent`.
    func chatEvents(from url: URL, streamId: String) -> AsyncThrowingStream<ChatEvent, Error> {
        ChatStream.bridge(sse: self.events(for: url), streamId: streamId)
    }
}

/// Extension to make it easy to build a ChatEvent stream from a WebSocket URL.
extension WSClient {
    /// Creates a `ChatEvent` stream from this client's WebSocket connection.
    ///
    /// Example:
    /// ```swift
    /// let client = WSClient(url: wsUrl)
    /// client.setAccessToken(token)
    /// let chatEvents = client.chatEvents(streamId: "abc")
    /// for try await event in chatEvents { ... }
    /// client.disconnect()
    /// ```
    ///
    /// - Parameter streamId: The stream identifier (used for logging/debugging).
    /// - Returns: An `AsyncThrowingStream` of `ChatEvent`.
    func chatEvents(streamId: String) -> AsyncThrowingStream<ChatEvent, Error> {
        ChatStream.bridge(ws: self.messages(), streamId: streamId)
    }
}
