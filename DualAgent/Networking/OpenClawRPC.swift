//
//  OpenClawRPC.swift
//  DualAgent
//
//  Long-lived gateway WebSocket RPC client. Implements the documented
//  OpenClaw gateway protocol (`docs/gateway/protocol.md` in the openclaw
//  repo) by reusing the connect handshake proven in `OpenClawPairing`
//  and exposing request/response + event subscription streams over the
//  SAME socket after `hello-ok`.
//
//  Verified protocol details (read from openclaw/docs/gateway/protocol.md):
//    - Frame shapes: `{type:"req", id, method, params}` /
//                    `{type:"res", id, ok, payload|error}` /
//                    `{type:"event", event, payload, seq?, stateVersion?}`
//    - Pre-connect challenge: `{type:"event", event:"connect.challenge", payload:{nonce,ts}}`
//    - Roles: "operator" / "node"; scopes drive method access
//    - Side-effecting calls (`chat.send`, `cron.add`, etc.) require
//      idempotency keys in their params.
//

import Foundation

/// Verified-wire gateway RPC client.
final class OpenClawRPC: @unchecked Sendable {

    enum RPCError: LocalizedError {
        case unsupportedTransport(URL)
        case challengeTimeout
        case encodingFailed
        case transport(Error)
        case serverRejected(String, code: String?)
        case socketClosed
        case requestTimeout(String, TimeInterval)
        case notConnected

        var errorDescription: String? {
            switch self {
            case .unsupportedTransport(let url):
                return "Refusing to send a credential over \(url.scheme ?? "?"). Use wss://, LAN, or localhost."
            case .challengeTimeout: return "The gateway did not send a connect.challenge in time."
            case .encodingFailed: return "Could not encode an RPC frame."
            case .transport(let e): return e.localizedDescription
            case .serverRejected(let m, let c): return "Gateway rejected the request (\(c ?? "?")): \(m)"
            case .socketClosed: return "The gateway closed the WebSocket before the RPC completed."
            case .requestTimeout(let m, let t): return "RPC \(m) timed out after \(Int(t))s."
            case .notConnected: return "Gateway connection is not open."
            }
        }
    }

    // MARK: - Public state

    /// Server info from `hello-ok.server` once a handshake completes.
    struct ServerInfo: Decodable { let version: String; let connId: String }

    /// Static info from `hello-ok`.
    struct HandshakeResult: Sendable {
        let server: ServerInfo
        let role: String
        let scopes: [String]
        let deviceToken: String?
        /// Authorized method names from `hello-ok.features.methods` (best-effort discovery).
        let featuresMethods: [String]
        let featuresEvents: [String]
    }

    /// Server-pushed event frame.
    struct ServerEvent: Sendable {
        let event: String
        let payload: [String: Any]
        let seq: Int?
    }

    // MARK: - Internals

    private let url: URL
    private let token: String
    private let stableID: OpenClawPairing.StableID
    private let client: PairingClientInfo
    private let role: String
    private let scopes: [String]

    private var task: URLSessionWebSocketTask?
    private let lock = NSLock()

    private var isOpen: Bool = false
    /// Method-call inflight table keyed by request id; stores a completion
    /// that resumes a `Result<Data, Error>` (success = JSON-encoded payload).
    private var inflight: [String: (Result<Data, Error>) -> Void] = [:]
    /// Active event subscribers.
    private var eventContinuations: [UUID: AsyncStream<ServerEvent>.Continuation] = [:]
    private var receiver: Task<Void, Never>?

    private(set) var handshake: HandshakeResult?

    init(
        url: URL,
        token: String,
        stableID: OpenClawPairing.StableID,
        client: PairingClientInfo,
        role: String = "operator",
        scopes: [String] = OpenClawPairing.defaultOperatorScopes
    ) {
        self.url = url
        self.token = token
        self.stableID = stableID
        self.client = client
        self.role = role
        self.scopes = scopes
    }

    // MARK: - Connection

    /// Connect, perform the handshake, and return once `hello-ok` is received.
    /// Implements the v3 device identity signing protocol documented in
    /// `docs/gateway/protocol.md` §"Device identity and pairing".
    func connect() async throws -> HandshakeResult {
        let host = url.host ?? ""
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "wss" || OpenClawPairing.isLoopbackOrLAN(host: host) else {
            throw RPCError.unsupportedTransport(url)
        }

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        // Wait for connect.challenge (10s) and capture the nonce.
        let challengeNonce: String
        do {
            challengeNonce = try await withTimeout(seconds: 10) {
                while !Task.isCancelled {
                    let msg = try await task.receive()
                    if let env = try? Self.decodeRawJSON(msg),
                       env["type"] as? String == "event",
                       env["event"] as? String == "connect.challenge",
                       let payload = env["payload"] as? [String: Any],
                       let nonce = payload["nonce"] as? String {
                        return nonce
                    }
                }
                throw RPCError.challengeTimeout
            }
        } catch is TimeoutError {
            task.cancel(with: .goingAway, reason: nil)
            throw RPCError.challengeTimeout
        } catch let e as RPCError {
            task.cancel(with: .goingAway, reason: nil)
            throw e
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            throw RPCError.transport(error)
        }

        // Build device identity and sign the challenge payload.
        let device: ConnectDevice?
        let signedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        if let identity = DeviceIdentityManager.shared.loadOrCreateIdentity() {
            let v3Payload = DeviceIdentityManager.shared.buildV3Payload(
                deviceId: identity.deviceId,
                clientId: client.clientID,
                clientMode: client.mode,
                role: role,
                scopes: scopes,
                signedAtMs: signedAtMs,
                token: token,
                nonce: challengeNonce,
                platform: "ios",
                deviceFamily: client.deviceFamily
            )
            guard let signatureData = DeviceIdentityManager.shared.signPayload(v3Payload, with: identity.privateKeyRef) else {
                task.cancel(with: .goingAway, reason: nil)
                throw RPCError.encodingFailed
            }
            device = ConnectDevice(
                id: identity.deviceId,
                publicKey: DeviceIdentityManager.shared.publicKeyBase64URL(identity.publicKeyData),
                signature: signatureData.base64URLEncodedString(),
                signedAt: signedAtMs,
                nonce: challengeNonce
            )
        } else {
            device = nil
        }

        // Send connect frame.
        let frameID = UUID().uuidString
        let connect = ConnectFrame(
            id: frameID,
            method: "connect",
            params: ConnectParams(
                minProtocol: 4,
                maxProtocol: 4,
                client: ConnectClient(
                    id: client.clientID,
                    displayName: client.displayName,
                    version: client.clientVersion,
                    platform: "ios",
                    deviceFamily: client.deviceFamily,
                    mode: client.mode,
                    instanceId: client.instanceID
                ),
                caps: client.caps,
                commands: client.commands,
                permissions: client.permissions,
                auth: .init(token: token),
                role: role,
                scopes: scopes,
                locale: Locale.preferredLanguages.first ?? "en-US",
                userAgent: "openclaw-ios/\(client.clientVersion)",
                device: device
            )
        )

        guard let encoded = try? JSONEncoder().encode(connect),
              let text = String(data: encoded, encoding: .utf8)
        else {
            task.cancel(with: .goingAway, reason: nil)
            throw RPCError.encodingFailed
        }
        do {
            try await task.send(.string(text))
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            throw RPCError.transport(error)
        }

        // Read hello-ok (15s).
        let helloData: Data
        do {
            helloData = try await withTimeout(seconds: 15) {
                while !Task.isCancelled {
                    let msg = try await task.receive()
                    guard let env = try? Self.decodeRawJSON(msg),
                          (env["type"] as? String) == "res",
                          (env["id"] as? String) == frameID
                    else { continue }
                    let ok = (env["ok"] as? Bool) ?? false
                    if !ok {
                        let err = env["error"] as? [String: Any] ?? [:]
                        throw RPCError.serverRejected(
                            (err["message"] as? String) ?? "rejected",
                            code: err["code"] as? String
                        )
                    }
                    let payload = env["payload"] as? [String: Any] ?? [:]
                    return try JSONSerialization.data(withJSONObject: payload)
                }
                throw RPCError.socketClosed
            }
        } catch is TimeoutError {
            task.cancel(with: .goingAway, reason: nil)
            throw RPCError.serverRejected("hello-ok timeout", code: nil)
        } catch let e as RPCError {
            task.cancel(with: .goingAway, reason: nil)
            throw e
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            throw RPCError.transport(error)
        }

        let hello = try JSONDecoder().decode(HelloEnvelope.self, from: helloData)
        let info = HandshakeResult(
            server: hello.server,
            role: hello.auth?.role ?? role,
            scopes: hello.auth?.scopes ?? scopes,
            deviceToken: hello.auth?.deviceToken,
            featuresMethods: hello.features?.methods ?? [],
            featuresEvents: hello.features?.events ?? []
        )
        self.handshake = info

        lock.lock()
        isOpen = true
        lock.unlock()
        startReceiver(task: task)
        return info
    }

    /// Close the socket cleanly.
    func disconnect() {
        lock.lock()
        let wasOpen = isOpen
        isOpen = false
        let subs = eventContinuations.values
        eventContinuations.removeAll()
        let pending = inflight
        inflight.removeAll()
        lock.unlock()

        for cont in subs { cont.finish() }
        for (_, comp) in pending { comp(.failure(RPCError.socketClosed)) }
        receiver?.cancel()
        if wasOpen { task?.cancel(with: .goingAway, reason: nil) }
        task = nil
    }

    // MARK: - Request / response

    /// Issue a single RPC. Returns the raw `payload` decoded into `T`.
    func request<T: Decodable>(
        _ method: String,
        params: [String: Any] = [:],
        timeout: TimeInterval = 30,
        as type: T.Type
    ) async throws -> T {
        let data = try await requestRawData(method, params: params, timeout: timeout)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Issue a single RPC, returning the raw `payload` as JSON Data.
    func requestRawData(
        _ method: String,
        params: [String: Any] = [:],
        timeout: TimeInterval = 30
    ) async throws -> Data {
        lock.lock()
        guard isOpen, let active = task else {
            lock.unlock()
            throw RPCError.notConnected
        }
        lock.unlock()

        let id = UUID().uuidString
        let frame: [String: Any] = [
            "type": "req",
            "id": id,
            "method": method,
            "params": params,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let text = String(data: data, encoding: .utf8)
        else { throw RPCError.encodingFailed }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let completion: (Result<Data, Error>) -> Void = { result in
                switch result {
                case .success(let d): cont.resume(returning: d)
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            self.lock.lock()
            self.inflight[id] = completion
            self.lock.unlock()

            // Send attempt
            Task {
                do {
                    try await active.send(.string(text))
                } catch {
                    self.lock.lock()
                    if let pending = self.inflight.removeValue(forKey: id) {
                        pending(.failure(error))
                    }
                    self.lock.unlock()
                }
            }
            // Timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.lock.lock()
                if let pending = self.inflight.removeValue(forKey: id) {
                    pending(.failure(RPCError.requestTimeout(method, timeout)))
                }
                self.lock.unlock()
            }
        }
    }

    /// Issue a single RPC, returning the raw `payload` dictionary.
    func requestRaw(
        _ method: String,
        params: [String: Any] = [:],
        timeout: TimeInterval = 30
    ) async throws -> [String: Any] {
        let data = try await requestRawData(method, params: params, timeout: timeout)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    // MARK: - Events

    /// Subscribe to a stream of all incoming server events (excluding res).
    func events() -> AsyncStream<ServerEvent> {
        AsyncStream { (continuation: AsyncStream<ServerEvent>.Continuation) in
            let id = UUID()
            self.lock.lock()
            guard self.isOpen else {
                self.lock.unlock()
                continuation.finish()
                return
            }
            self.eventContinuations[id] = continuation
            self.lock.unlock()
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.lock.lock()
                self?.eventContinuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    // MARK: - Receiver

    private func startReceiver(task: URLSessionWebSocketTask) {
        receiver = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                do {
                    let msg = try await task.receive()
                    self.dispatch(msg)
                } catch {
                    self.handleSocketClosed()
                    break
                }
            }
        }
    }

    private func dispatch(_ msg: URLSessionWebSocketTask.Message) {
        guard let obj = try? Self.decodeRawJSON(msg) else { return }
        let type = (obj["type"] as? String) ?? ""
        switch type {
        case "res":
            let id = (obj["id"] as? String) ?? ""
            lock.lock()
            let pending = inflight.removeValue(forKey: id)
            lock.unlock()
            if let pending {
                let ok = (obj["ok"] as? Bool) ?? false
                if ok {
                    let payload = (obj["payload"] as? [String: Any]) ?? [:]
                    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    pending(.success(data))
                } else {
                    let err = (obj["error"] as? [String: Any]) ?? [:]
                    let code = err["code"] as? String
                    let message = (err["message"] as? String) ?? "rejected"
                    pending(.failure(RPCError.serverRejected(message, code: code)))
                }
            }
        case "event":
            let eventName = (obj["event"] as? String) ?? ""
            let payload = (obj["payload"] as? [String: Any]) ?? [:]
            let seq = obj["seq"] as? Int
            let serverEvent = ServerEvent(event: eventName, payload: payload, seq: seq)
            lock.lock()
            let subs = Array(eventContinuations.values)
            lock.unlock()
            for cont in subs { cont.yield(serverEvent) }
        default:
            break
        }
    }

    private func handleSocketClosed() {
        lock.lock()
        isOpen = false
        for cont in eventContinuations.values { cont.finish() }
        eventContinuations.removeAll()
        let pending = inflight
        inflight.removeAll()
        lock.unlock()
        for (_, comp) in pending { comp(.failure(RPCError.socketClosed)) }
    }

    // MARK: - Wire types

    private struct ConnectChallenge: Decodable {
        let type: String
        let event: String
        let payload: Payload
        struct Payload: Decodable { let nonce: String; let ts: Int64? }
    }

    fileprivate struct HelloEnvelope: Decodable {
        let server: ServerInfo
        let auth: Auth?
        let features: Features?
        struct Auth: Decodable {
            let role: String?
            let scopes: [String]?
            let deviceToken: String?
            let deviceTokens: [BoundedToken]?
            struct BoundedToken: Decodable {
                let deviceToken: String
                let role: String
                let scopes: [String]
            }
        }
        struct Features: Decodable {
            let methods: [String]?
            let events: [String]?
        }
    }

    private struct ConnectFrame: Encodable {
        let type: String = "req"
        let id: String
        let method: String
        let params: ConnectParams
    }

    private struct ConnectParams: Encodable {
        let minProtocol: Int
        let maxProtocol: Int
        let client: ConnectClient
        let caps: [String]
        let commands: [String]
        let permissions: [String: Bool]
        let auth: ConnectAuth
        let role: String
        let scopes: [String]
        let locale: String
        let userAgent: String
        let device: ConnectDevice?
    }

    /// Device identity frame for the v3 signing protocol.
    /// Sent in `connect.params.device` when a device identity is available.
    private struct ConnectDevice: Encodable {
        let id: String          // device fingerprint (hex from SHA256 public key)
        let publicKey: String   // base64url raw P256 public key
        let signature: String    // base64url ECDSA signature over v3 payload
        let signedAt: Int64     // Unix milliseconds when signature was created
        let nonce: String       // the connect.challenge nonce that was signed
    }

    private struct ConnectClient: Encodable {
        let id: String
        let displayName: String
        let version: String
        let platform: String
        let deviceFamily: String?
        let mode: String
        let instanceId: String
    }

    private struct ConnectAuth: Encodable {
        let token: String?
        let password: String?
        let bootstrapToken: String?
        let deviceToken: String?
        init(token: String? = nil, password: String? = nil, bootstrapToken: String? = nil, deviceToken: String? = nil) {
            self.token = token
            self.password = password
            self.bootstrapToken = bootstrapToken
            self.deviceToken = deviceToken
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if let v = token { try c.encode(v, forKey: .token) }
            if let v = password { try c.encode(v, forKey: .password) }
            if let v = bootstrapToken { try c.encode(v, forKey: .bootstrapToken) }
            if let v = deviceToken { try c.encode(v, forKey: .deviceToken) }
        }
        enum CodingKeys: String, CodingKey {
            case token, password, bootstrapToken, deviceToken
        }
    }

    // MARK: - Helpers

    private static func decode<T: Decodable>(_ type: T.Type, from msg: URLSessionWebSocketTask.Message) throws -> T {
        let data: Data
        switch msg {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default:
            throw RPCError.transport(NSError(domain: "OpenClawRPC", code: -1))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func decodeRawJSON(_ msg: URLSessionWebSocketTask.Message) throws -> [String: Any] {
        let data: Data
        switch msg {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default:
            throw RPCError.transport(NSError(domain: "OpenClawRPC", code: -1))
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RPCError.transport(NSError(domain: "OpenClawRPC", code: -2))
        }
        return obj
    }

    private struct TimeoutError: Error {}
    private func withTimeout<T>(seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            for try await result in group {
                if let r = result { return r }
                group.cancelAll()
                throw TimeoutError()
            }
            throw TimeoutError()
        }
    }
}
