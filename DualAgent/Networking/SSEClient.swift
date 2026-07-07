import Foundation
import LDSwiftEventSource

/// Wraps the LDSwiftEventSource library to expose a Swift Concurrency-friendly SSE interface.
///
/// Usage:
/// ```
/// let client = SSEClient()
/// Task {
///     for await event in client.events(for: url) {
///         // event: SSEClient.Event
///     }
/// }
/// client.stop()
/// ```
final class SSEClient {

    /// A single raw event received from an SSE stream.
    struct Event: Equatable, Sendable {
        let id: String?
        let event: String?
        let data: String?
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

    private var eventHandler: EventHandler?
    private var accessToken: String?

    /// Configure a bearer token to be sent on all SSE requests.
    func setAccessToken(_ token: String?) {
        self.accessToken = token
    }

    /// Connect to an SSE endpoint and yield `Event`s via an `AsyncStream`.
    ///
    /// - Parameter url: The SSE endpoint URL.
    /// - Returns: An `AsyncStream` of `Event`.
    func events(for url: URL) -> AsyncStream<Result<Event, Error>> {
        AsyncStream { continuation in
            let config = EventSource.Config()
            config.url = url.absoluteString

            // Attach bearer token if set.
            if let token = accessToken {
                config.headers = ["Authorization": "Bearer \(token)"]
            }

            config.lastEventId = nil
            // Tell the server we want text/event-stream (default for EventSource).
            config.accept = "text/event-stream"

            let handler = EventHandler(
                config: config,
                continuation: continuation,
                url: url
            )
            self.eventHandler = handler

            continuation.onTermination = { @Sendable _ in
                handler.stop()
            }
        }
    }

    /// Stop the active SSE connection (if any).
    func stop() {
        eventHandler?.stop()
        eventHandler = nil
    }
}

// MARK: - EventHandler桥接LDSwiftEventSource

private final class EventHandler: @unchecked Sendable {
    private let source: EventSource
    private let continuation: AsyncStream<Result<SSEClient.Event, Error>>.Continuation

    init(
        config: EventSource.Config,
        continuation: AsyncStream<Result<SSEClient.Event, Error>>.Continuation,
        url: URL
    ) {
        self.continuation = continuation

        let emitter = SSEEventHandler { [weak self] id, event, data, retry in
            let ev = SSEClient.Event(id: id, event: event, data: data, retry: retry)
            self?.continuation.yield(.success(ev))
        }

        self.source = EventSource(handler: emitter, config: config)
        self.source.start()
    }

    func stop() {
        source.stop()
    }
}

/// C-compatible callback adapter so LDSwiftEventSource can call into our Swift closure.
private final class SSEEventHandler: @unchecked Sendable {
    let onEvent: (String?, String?, String?, Int?) -> Void

    init(onEvent: @escaping (String?, String?, String?, Int?) -> Void) {
        self.onEvent = onEvent
    }

    func onEventReceived(id: String?, event: String?, data: String?, lastEventId: String?, retry: Int?) {
        onEvent(id, event, data, retry)
    }
}

// MARK: - EventSourceDelegate桥接

/// Stub delegate to satisfy EventSource's delegate requirement (we use the handler callback instead).
private final class SSEEventHandlerBridge: EventSourceDelegate {
    func onStateChanged(state: EventSourceState) {}
    func onmessage(event: EventMessage) {}
    func onError(error: Error) {}
    func onComment(comment: String) {}
}
