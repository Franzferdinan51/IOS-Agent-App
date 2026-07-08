import Foundation
import LDSwiftEventSource

/// Wraps the LDSwiftEventSource library (launchdarkly/swift-eventsource) to expose a
/// Swift Concurrency-friendly SSE interface.
///
/// Usage:
/// ```
/// let client = SSEClient()
/// Task {
///     for await result in client.events(for: url) {
///         switch result {
///         case .success(let event):
///             // event: SSEClient.Event
///         case .failure(let error):
///             // error: Error
///         }
///     }
/// }
/// client.stop()
/// ```
final class SSEClient {

    /// A single raw event received from an SSE stream.
    struct Event: Equatable, Sendable {
        /// The event id (Last-Event-Id from the SSE spec).
        let id: String?
        /// The event type (the `event` field in SSE).
        let event: String?
        /// The event data payload.
        let data: String?
        /// The retry interval hint.
        let retry: Int?

        static func == (lhs: Event, rhs: Event) -> Bool {
            lhs.id == rhs.id && lhs.event == rhs.event && lhs.data == rhs.data && lhs.retry == rhs.retry
        }
    }

    /// Errors thrown by the SSE client.
    enum SSEError: LocalizedError {
        case connectionFailed(Error)
        case invalidURL
        case cancelled

        var errorDescription: String? {
            switch self {
            case .connectionFailed(let error):
                return "SSE connection failed: \(error.localizedDescription)"
            case .invalidURL:
                return "Invalid SSE URL"
            case .cancelled:
                return "SSE stream was cancelled"
            }
        }
    }

    private var eventSource: EventSource?
    private var accessToken: String?

    /// Configure a bearer token to be sent on all SSE requests.
    func setAccessToken(_ token: String?) {
        self.accessToken = token
    }

    /// Connect to an SSE endpoint and yield `Event`s via an `AsyncStream`.
    ///
    /// - Parameter url: The SSE endpoint URL.
    /// - Returns: An `AsyncStream` of `Result<Event, Error>`.
    func events(for url: URL) -> AsyncStream<Result<Event, Error>> {
        AsyncStream { [weak self] continuation in
            guard let self = self else { return }

            let handler = SSEEventBridge { id, event, data, retry in
                let ev = SSEClient.Event(id: id, event: event, data: data, retry: retry)
                continuation.yield(.success(ev))
            }

            var config = EventSource.Config(handler: handler, url: url)

            // Attach bearer token if set.
            if let token = self.accessToken {
                config.headers["Authorization"] = "Bearer \(token)"
            }

            config.lastEventId = nil

            let source = EventSource(config: config)
            self.eventSource = source

            continuation.onTermination = { @Sendable _ in
                source.stop()
            }

            source.start()
        }
    }

    /// Stop the active SSE connection (if any).
    func stop() {
        eventSource?.stop()
        eventSource = nil
    }
}

// MARK: - SSEEventBridge (EventHandler protocol)

/// Implements the LDSwiftEventSource EventHandler protocol and bridges events to a Swift closure.
private final class SSEEventBridge: EventHandler {
    let onEvent: (String?, String?, String?, Int?) -> Void

    init(onEvent: @escaping (String?, String?, String?, Int?) -> Void) {
        self.onEvent = onEvent
    }

    func onOpened() {
        // Connection opened — nothing to surface to the stream.
    }

    func onClosed() {
        // Stream closed — let the continuation end naturally.
    }

    func onMessage(eventType: String, messageEvent: MessageEvent) {
        // SSE data field can contain multiple lines joined by \n.
        let data = messageEvent.data
        let retry: Int? = nil  // retry is not exposed by MessageEvent in this library version.
        onEvent(messageEvent.lastEventId, eventType, data, retry)
    }

    func onComment(comment: String) {
        // SSE comments (lines starting with ':') are ignored.
        _ = comment
    }

    func onError(error: Error) {
        // Errors are surfaced via the stream; nothing extra needed here.
    }
}
