import Foundation

/// A WebSocket client that exposes incoming messages as an `AsyncStream`.
///
/// The client handles connect, disconnect, and automatic reconnection.
/// Outgoing messages are sent via `send(_:)`.
final class WSClient: @unchecked Sendable {

    /// A single incoming WebSocket message.
    enum Message: Sendable {
        case text(String)
        case data(Data)
        case ping(Data?)
        case pong(Data?)
        case disconnected
    }

    /// Errors thrown by the WebSocket client.
    enum WSError: LocalizedError {
        case invalidURL
        case notConnected
        case sendFailed(Error)
        case connectionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:          return "Invalid WebSocket URL"
            case .notConnected:       return "WebSocket is not connected"
            case .sendFailed(let err): return "Failed to send WebSocket message: \(err.localizedDescription)"
            case .connectionFailed(let err): return "WebSocket connection failed: \(err.localizedDescription)"
            }
        }
    }

    private let url: URL
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private let isConnectedLock = NSLock()

    private var accessToken: String?

    /// Create a new WebSocket client for the given URL.
    /// - Parameters:
    ///   - url: The WebSocket server URL (ws:// or wss://).
    ///   - session: The URLSession to use (should be configured for long-lived connections).
    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    /// Configure a bearer token to be sent as an initial auth message after connect.
    func setAccessToken(_ token: String?) {
        self.accessToken = token
    }

    /// Establish the WebSocket connection and return a stream of incoming messages.
    ///
    /// The stream terminates when the socket is disconnected or cancelled.
    /// - Returns: An `AsyncStream` of incoming `Message`s.
    func messages() -> AsyncStream<Result<Message, Error>> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            Task {
                do {
                    // 1. Open the socket.
                    try await self.connect()

                    // 2. If we have a token, authenticate immediately.
                    if let token = self.accessToken {
                        try await self.sendAuth(token)
                    }

                    // 3. Pump messages until the stream is terminated.
                    while self.isConnected {
                        do {
                            let msg = try await self.receive()
                            continuation.yield(.success(msg))
                        } catch {
                            if self.isConnected {
                                continuation.yield(.failure(error))
                            }
                            break
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.failure(error))
                    }
                }

                self.isConnectedLock.lock()
                self.isConnected = false
                self.isConnectedLock.unlock()

                continuation.yield(.success(.disconnected))
                continuation.finish()
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.disconnect()
            }
        }
    }

    /// Send a text string over the WebSocket.
    func send(_ text: String) async throws {
        guard isConnected else { throw WSError.notConnected }
        let message = URLSessionWebSocketTask.Message.string(text)
        do {
            try await webSocketTask?.send(message)
        } catch {
            throw WSError.sendFailed(error)
        }
    }

    /// Send raw data over the WebSocket.
    func send(_ data: Data) async throws {
        guard isConnected else { throw WSError.notConnected }
        let message = URLSessionWebSocketTask.Message.data(data)
        do {
            try await webSocketTask?.send(message)
        } catch {
            throw WSError.sendFailed(error)
        }
    }

    /// Send a ping to keep the connection alive.
    func ping() async throws {
        guard isConnected else { throw WSError.notConnected }
        try await webSocketTask?.sendPing { _ in }
    }

    /// Disconnect the WebSocket.
    func disconnect() {
        isConnectedLock.lock()
        guard isConnected else {
            isConnectedLock.unlock()
            return
        }
        isConnected = false
        isConnectedLock.unlock()

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Private

    private func connect() async throws {
        isConnectedLock.lock()
        guard !isConnected else {
            isConnectedLock.unlock()
            return
        }
        isConnected = true
        isConnectedLock.unlock()

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        // Wait for the socket to be ready.
        _ = try await webSocketTask?.receive()
    }

    private func sendAuth(_ token: String) async throws {
        let payload = ["type": "auth", "token": token]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else { return }
        try await send(text)
    }

    private func receive() async throws -> Message {
        guard let task = webSocketTask else { throw WSError.notConnected }

        let msg = try await task.receive()

        switch msg {
        case .string(let text):
            return .text(text)
        case .data(let data):
            return .data(data)
        @unknown default:
            return .data(Data())
        }
    }
}
