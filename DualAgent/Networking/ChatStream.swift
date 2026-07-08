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
                            continuation.finish(throwing: error)
                        }
                    }
                    continuation.yield(.streamEnd)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
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
                            continuation.finish(throwing: error)
                        }
                    }
                    continuation.yield(.streamEnd)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
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
    /// Supports the Hermes named-event format used by HermesMobile
    /// (`hermex/HermesMobile/Networking/SSEClient.swift:181-253`):
    /// `token`, `reasoning`, `tool`, `tool_complete`, `title`, `done`,
    /// `initial`, `approval`, `clarify`, `pending_steer_leftover`, `stream_end`,
    /// `cancel`, `error`, `apperror`. Falls back to default-event handling for
    /// `{"content":"…"}` and raw text tokens.
    private static func parse(sseEvent event: SSEClient.Event) -> ChatEvent? {
        // Comment line (starts with `:`) — ignore.
        if event.data == nil && event.event == nil && event.id == nil {
            return nil
        }

        // Named event: route by event type.
        if let eventType = event.event, !eventType.isEmpty {
            guard let data = event.data else { return nil }
            return decodeNamedEvent(eventType: eventType, data: data)
        }

        // Default "message" event: raw data field.
        guard let data = event.data else { return nil }

        // Empty data on default event may signal stream end in some SSE protocols.
        if data.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }

        return decodeDefaultMessage(data: data)
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
    /// Tries the simple `{"content": "..."}` dict format first, then falls back to a raw
    /// string token.
    private static func decodeChatEvent(from data: Data) -> ChatEvent? {
        // Primary: simple `{"content": "token string"}` format.
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

    /// Decode a Hermes named SSE event. The wire shape is `event: <type>\ndata: <json>`.
    /// Field shapes per `hermex/HermesMobile/Networking/SSEClient.swift:181-253`.
    private static func decodeNamedEvent(eventType: String, data: String) -> ChatEvent? {
        guard let jsonData = data.data(using: .utf8) else { return nil }
        let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]

        switch eventType {
        case "token":
            // {text: "..."} or {content: "..."}
            if let text = (dict?["text"] as? String) ?? (dict?["content"] as? String) {
                return .token(text)
            }
            return .token("")

        case "reasoning":
            if let text = (dict?["text"] as? String) ?? (dict?["content"] as? String) {
                return .reasoning(text)
            }
            return nil

        case "tool":
            // ToolStreamEvent: {event_type, name, args, preview, …}
            if let name = dict?["name"] as? String {
                let args = (dict?["args"] as? [String: String]) ?? [:]
                return .toolCall(ToolCall(id: UUID().uuidString, name: name, arguments: args))
            }
            return nil

        case "tool_complete":
            // ToolStreamEvent completion: emit a toolResult.
            if let name = (dict?["name"] as? String) ?? (dict?["tool_name"] as? String) {
                let output = (dict?["output"] as? String) ?? (dict?["result"] as? String) ?? ""
                return .toolResult(ToolResult(
                    toolCallId: (dict?["id"] as? String) ?? UUID().uuidString,
                    output: output,
                    isError: (dict?["is_error"] as? Bool) ?? (dict?["isError"] as? Bool) ?? false
                ))
            }
            return nil

        case "title":
            // Session title update — surface as a token so the UI can react.
            if let text = dict?["text"] as? String { return .token(text) }
            return nil

        case "done":
            // Terminal: signal the end of stream.
            return .streamEnd

        case "stream_end":
            return .streamEnd

        case "cancel":
            return .streamEnd

        case "error", "apperror":
            // {error, message, type, hint, details, …} — read whichever the server sent.
            let message = (dict?["error"] as? String)
                ?? (dict?["message"] as? String)
                ?? "The stream returned an error."
            return .error(message)

        case "initial", "approval", "clarify", "pending_steer_leftover":
            // Server housekeeping frames — surface as empty tokens so the stream
            // keeps flowing but no UI element changes. Future: render approvals.
            return .token("")

        default:
            // Unknown event types: log nothing, drop. The reference HermesMobile
            // calls this `.ignored` — DualAgent's `UnifiedChatEvent` has no
            // equivalent, so we just skip.
            return nil
        }
    }

    /// Decode a default-event SSE message (no `event:` field). Tries the simple
    /// `{"content":"…"}` JSON format first, then treats the raw data as a token.
    private static func decodeDefaultMessage(data: String) -> ChatEvent? {
        if let jsonData = data.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            if let content = dict["content"] as? String { return .token(content) }
            if let text = dict["text"] as? String { return .token(text) }
        }
        return .token(data)
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
