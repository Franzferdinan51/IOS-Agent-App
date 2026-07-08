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
    private var additionalHeaders: [String: String] = [:]

    /// Configure a bearer token to be sent on all SSE requests.
    func setAccessToken(_ token: String?) {
        self.accessToken = token
    }

    /// Configure non-bearer headers, e.g. Hermes' dashboard session token.
    func setAdditionalHeaders(_ headers: [String: String]) {
        additionalHeaders = headers
    }

    /// Connect to an SSE endpoint and yield `Event`s via an `AsyncStream`.
    ///
    /// - Parameter url: The SSE endpoint URL.
    /// - Returns: An `AsyncStream` of `Result<Event, Error>`.
    func events(for url: URL) -> AsyncStream<Result<Event, Error>> {
        AsyncStream { [weak self] continuation in
            guard let self = self else { return }

            let handler = SSEEventBridge(
                onEvent: { id, event, data, retry in
                    let ev = SSEClient.Event(id: id, event: event, data: data, retry: retry)
                    continuation.yield(.success(ev))
                },
                onError: { error in
                    continuation.yield(.failure(SSEError.connectionFailed(error)))
                    continuation.finish()
                },
                onClosed: {
                    continuation.finish()
                }
            )

            var config = EventSource.Config(handler: handler, url: url)

            config.headers["Accept"] = "text/event-stream"
            config.headers["Cache-Control"] = "no-cache, no-transform"
            config.headers["Accept-Encoding"] = "identity"
            for (name, value) in self.additionalHeaders where !value.isEmpty {
                config.headers[name] = value
            }

            // Attach bearer token if set.
            if let token = self.accessToken {
                config.headers["Authorization"] = "Bearer \(token)"
            }

            let configuration = URLSessionConfiguration.default
            configuration.httpCookieStorage = .shared
            configuration.httpCookieAcceptPolicy = .always
            configuration.httpShouldSetCookies = true
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.urlSessionConfiguration = configuration

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
    let onErrorEvent: (Error) -> Void
    let onClosedEvent: () -> Void

    init(
        onEvent: @escaping (String?, String?, String?, Int?) -> Void,
        onError: @escaping (Error) -> Void,
        onClosed: @escaping () -> Void
    ) {
        self.onEvent = onEvent
        self.onErrorEvent = onError
        self.onClosedEvent = onClosed
    }

    func onOpened() {
        // Connection opened — nothing to surface to the stream.
    }

    func onClosed() {
        onClosedEvent()
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
        onErrorEvent(error)
    }
}
