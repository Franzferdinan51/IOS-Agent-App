import Foundation

/// OpenClaw gateway QR/setup-code pairing driver.
///
/// What this module does:
///   - Parses a QR payload (base64url-encoded JSON: `{url|host, bootstrapToken, …}`)
///   - Opens a `URLSessionWebSocketTask` to the gateway's `wss://` (or LAN) endpoint
///   - Waits for the `connect.challenge` event
///   - Replies with a `connect` request carrying `auth.bootstrapToken`
///   - Reads `hello-ok`, extracts the issued device token(s)
///   - Persists the durable device token (NOT the bootstrap token) for reconnect
///
/// Source of truth:
///   - openclaw/docs/gateway/protocol.md
///   - openclaw/apps/shared/OpenClawKit/Sources/OpenClawKit/DeepLinks.swift
///   - openclaw/packages/gateway-client/src/client.ts
///   - openclaw/packages/gateway-client/src/device-auth.ts
enum OpenClawPairing {

    // MARK: - Public Types

    /// Lifecycle event emitted while the pairing handshake is in flight.
    enum Event: Sendable {
        case connecting(URL)
        case challengeReceived
        case paired(PairedResult)
        case failed(Error)
    }

    /// Stable per-gateway identifier derived from host+port+TLS.
    struct StableID: Hashable, Sendable, CustomStringConvertible {
        let host: String
        let port: Int
        let tls: Bool

        var description: String { "\(host):\(port) [\(tls ? "wss" : "ws")]" }
        var storageKey: String { "openclaw_\(host)_\(port)_\(tls ? "wss" : "ws")" }
    }

    /// Successful pairing result.
    struct PairedResult: Sendable {
        /// Primary token (role=node on mobile). Use this for normal reconnects.
        let deviceToken: String
        /// Bounded operator token (if the QR bootstrap rewarded one).
        let operatorToken: String?
        let role: String
        let scopes: [String]
        let sessionID: String
        let gatewayVersion: String
        let stableID: StableID
    }

    /// Parsed QR payload, ready to drive the handshake.
    struct SetupLink: Sendable, Equatable {
        let websocketURL: URL
        let bootstrapToken: String
        let stableID: StableID

        static func == (lhs: SetupLink, rhs: SetupLink) -> Bool {
            lhs.websocketURL == rhs.websocketURL
                && lhs.bootstrapToken == rhs.bootstrapToken
                && lhs.stableID == rhs.stableID
        }
    }

    enum PairError: LocalizedError {
        case invalidPayload(String)
        case unsupportedTransport(URL)
        case transport(Error)
        case challengeTimeout
        case connectRejected(String)
        case setupCodeExpired
        case pairingRequired
        case encodingFailed
        case socketClosed

        var errorDescription: String? {
            switch self {
            case .invalidPayload(let s): return "QR setup code is not a recognized OpenClaw code (\(s))."
            case .unsupportedTransport(let url):
                return "Refusing to send a setup code over \(url.scheme ?? "?"). Use wss://, LAN, or localhost."
            case .transport(let e): return e.localizedDescription
            case .challengeTimeout: return "The gateway did not send a connect.challenge in time."
            case .connectRejected(let m): return "The gateway rejected the setup code: \(m)"
            case .setupCodeExpired: return "That setup code has already been used or has expired. Generate a fresh one on the gateway host."
            case .pairingRequired: return "Pairing is required. Approve this device from another already-paired OpenClaw client (e.g. `/pair approve`)."
            case .encodingFailed: return "Could not encode the connect frame."
            case .socketClosed: return "The gateway closed the connection before completing pairing."
            }
        }
    }

    // MARK: - Setup Code Parsing

    /// Parse a QR payload or raw setup input into a `SetupLink`.
    ///
    /// Accepts, in order:
    ///   1. base64url-encoded JSON `{url|host, bootstrapToken, …}`  ← the QR path
    ///   2. raw setup JSON
    ///   3. `openclaw://gateway?host=…&port=…&tls=…&bootstrapToken=…` deep link
    static func parseSetupInput(_ raw: String) throws -> SetupLink {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PairError.invalidPayload("empty")
        }

        // 3. openclaw:// deep link
        if let comps = URLComponents(string: trimmed),
           comps.scheme?.lowercased() == "openclaw" {
            return try parseDeepLink(comps)
        }

        // 2. raw JSON
        if trimmed.hasPrefix("{") {
            return try parseJSON(trimmed)
        }

        // 1. base64url JSON
        if let decoded = base64URLDecode(trimmed) {
            return try parseJSON(decoded)
        }

        throw PairError.invalidPayload("not base64url JSON, raw JSON, or an openclaw:// link")
    }

    private static func parseDeepLink(_ comps: URLComponents) throws -> SetupLink {
        let q = comps.queryItems ?? []
        let host = q.first(where: { $0.name == "host" })?.value ?? ""
        let port = Int(q.first(where: { $0.name == "port" })?.value ?? "443") ?? 443
        let tls = (q.first(where: { $0.name == "tls" })?.value ?? "true") != "false"
        let token = q.first(where: { $0.name == "bootstrapToken" || $0.name == "token" })?.value ?? ""
        guard !host.isEmpty, !token.isEmpty else {
            throw PairError.invalidPayload("openclaw:// link missing host or bootstrapToken")
        }
        return try makeLink(host: host, port: port, tls: tls, bootstrapToken: token)
    }

    private static func parseJSON(_ json: String) throws -> SetupLink {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw PairError.invalidPayload("JSON parse failed")
        }

        // bootstrap token comes from one of these keys
        let token = (obj["bootstrapToken"] as? String)
            ?? (obj["token"] as? String)
            ?? ""
        guard !token.isEmpty else {
            throw PairError.invalidPayload("no bootstrapToken field")
        }

        if let urlString = obj["url"] as? String,
           let url = URL(string: urlString),
           ["ws", "wss"].contains(url.scheme?.lowercased() ?? ""),
           let host = url.host {
            return try makeLink(host: host, port: url.port ?? 443, tls: url.scheme == "wss", bootstrapToken: token)
        }
        if let urls = obj["urls"] as? [String], let first = urls.first,
           let url = URL(string: first),
           ["ws", "wss"].contains(url.scheme?.lowercased() ?? ""),
           let host = url.host {
            return try makeLink(host: host, port: url.port ?? 443, tls: url.scheme == "wss", bootstrapToken: token)
        }
        if let host = obj["host"] as? String, !host.isEmpty {
            let port = (obj["port"] as? Int) ?? 443
            let tls = (obj["tls"] as? Bool) ?? true
            return try makeLink(host: host, port: port, tls: tls, bootstrapToken: token)
        }

        throw PairError.invalidPayload("no url or host/port/tls fields")
    }

    private static func makeLink(host: String, port: Int, tls: Bool, bootstrapToken: String) throws -> SetupLink {
        let scheme = tls ? "wss" : "ws"
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = host
        comps.port = port
        comps.path = "/"
        guard let url = comps.url else {
            throw PairError.invalidPayload("could not build gateway URL")
        }
        return SetupLink(
            websocketURL: url,
            bootstrapToken: bootstrapToken,
            stableID: StableID(host: host, port: port, tls: tls)
        )
    }

    private static func base64URLDecode(_ s: String) -> String? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        let pad = t.count % 4
        if pad > 0 { t.append(String(repeating: "=", count: 4 - pad)) }
        guard let data = Data(base64Encoded: t) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Pairing Drive

    /// Drive the pairing handshake end-to-end. Returns an `AsyncThrowingStream`
    /// that emits lifecycle events and terminates with `.paired` or `.failed`.
    static func start(link: SetupLink, client: PairingClientInfo) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream<Event, Error> { (continuation: AsyncThrowingStream<Event, Error>.Continuation) in
            let yieldFn: @Sendable (Event) -> Void = continuation.yield
            let task = Task {
                await Self.drivePairing(
                    link: link,
                    client: client,
                    auth: .bootstrapToken(link.bootstrapToken),
                    role: "node",
                    scopes: [],
                    yield: yieldFn
                )
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Drive a manual token-auth connect (no QR). Returns an `AsyncThrowingStream`
    /// with the same `.paired` / `.failed` events but the `PairedResult.deviceToken`
    /// is the same token the caller supplied (no new one is issued in token mode).
    ///
    /// Use this for the "I pasted a gateway token" path — matches the real
    /// OpenClaw iOS app's `client.id = "openclaw-ios"`, `client.mode = "ui"`,
    /// `role = "operator"`, `scopes = defaultOperatorConnectScopes`.
    static func start(
        token: String,
        websocketURL: URL,
        stableID: StableID,
        client: PairingClientInfo
    ) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream<Event, Error> { (continuation: AsyncThrowingStream<Event, Error>.Continuation) in
            let yieldFn: @Sendable (Event) -> Void = continuation.yield
            let task = Task {
                let link = SetupLink(
                    websocketURL: websocketURL,
                    bootstrapToken: token, // reused as a transport gate check below
                    stableID: stableID
                )
                await Self.drivePairing(
                    link: link,
                    client: client,
                    auth: .sharedToken(token),
                    role: "operator",
                    scopes: defaultOperatorScopes,
                    yield: yieldFn
                )
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Default operator scopes for a token-auth connection. Mirrors
    /// `defaultOperatorConnectScopes` in
    /// `apps/shared/OpenClawKit/Sources/OpenClawKit/GatewayChannel.swift:227-233`.
    static let defaultOperatorScopes: [String] = [
        "operator.admin",
        "operator.read",
        "operator.write",
        "operator.approvals",
        "operator.pairing",
    ]

    /// Pure internal driver — kept separate so it's testable without streams.
    fileprivate static func drivePairing(
        link: SetupLink,
        client: PairingClientInfo,
        auth: AuthMode,
        role: String,
        scopes: [String],
        yield: @escaping @Sendable (Event) -> Void
    ) async {
        // 1. Transport gate: only wss://, loopback, or LAN. No cleartext over WAN.
        let host = link.websocketURL.host ?? ""
        let scheme = link.websocketURL.scheme?.lowercased() ?? ""
        let transportOK = scheme == "wss" || isLoopbackOrLAN(host: host)
        guard transportOK else {
            yield(.failed(PairError.unsupportedTransport(link.websocketURL)))
            return
        }

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: link.websocketURL)
        yield(.connecting(link.websocketURL))
        task.resume()

        // 2. Wait for connect.challenge (timeout 10s).
        let challenge: ConnectChallenge
        do {
            challenge = try await withTimeout(seconds: 10) {
                let msg = try await task.receive()
                return try Self.decode(ConnectChallenge.self, from: msg)
            }
        } catch is TimeoutError {
            yield(.failed(PairError.challengeTimeout))
            task.cancel(with: .goingAway, reason: nil)
            return
        } catch {
            yield(.failed(PairError.transport(error)))
            task.cancel(with: .goingAway, reason: nil)
            return
        }
        yield(.challengeReceived)

        // 3. Build and send the connect frame.
        let frameID = UUID().uuidString
        let signedAt = Int(Date().timeIntervalSince1970 * 1000)

        let connect = ConnectRequest(
            id: frameID,
            method: "connect",
            params: ConnectParams(
                minProtocol: 4,
                maxProtocol: 4,
                client: ClientInfoFrame(
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
                auth: auth.encoded(),
                role: role,
                scopes: scopes,
                // locale + userAgent are required by openclaw/docs/gateway/protocol.md §"Handshake"
                // for non-trusted clients (client.id ≠ "gateway-client", client.mode ≠ "backend").
                locale: Locale.preferredLanguages.first ?? "en-US",
                userAgent: "openclaw-ios/\(client.clientVersion)"
            )
        )

        guard let encoded = try? JSONEncoder().encode(connect),
              let text = String(data: encoded, encoding: .utf8)
        else {
            yield(.failed(PairError.encodingFailed))
            task.cancel(with: .goingAway, reason: nil)
            return
        }
        do {
            try await task.send(.string(text))
        } catch {
            yield(.failed(PairError.transport(error)))
            task.cancel(with: .goingAway, reason: nil)
            return
        }

        // 4. Read hello-ok (15s timeout).
        let helloOK: HelloOKResponse
        do {
            helloOK = try await withTimeout(seconds: 15) {
                while !Task.isCancelled {
                    let msg = try await task.receive()
                    guard let env = try? Self.decodeRawJSON(msg),
                          env["type"] as? String == "res",
                          env["id"] as? String == frameID
                    else { continue }
                    let ok = env["ok"] as? Bool ?? false
                    if !ok {
                        let error = env["error"] as? [String: Any]
                        let code = error?["code"] as? String
                        let message = error?["message"] as? String ?? "rejected"
                        if code == "AUTH_BOOTSTRAP_TOKEN_INVALID" {
                            throw PairError.setupCodeExpired
                        }
                        if code == "PAIRING_REQUIRED" {
                            throw PairError.pairingRequired
                        }
                        throw PairError.connectRejected(message)
                    }
                    guard let payload = env["payload"] as? [String: Any] else {
                        throw PairError.connectRejected("missing payload")
                    }
                    let payloadData = try JSONSerialization.data(withJSONObject: payload)
                    let payloadObj = try JSONDecoder().decode(HelloOKPayload.self, from: payloadData)
                    return HelloOKResponse(ok: true, payload: payloadObj, error: nil)
                }
                throw PairError.socketClosed
            }
        } catch is TimeoutError {
            yield(.failed(PairError.connectRejected("hello-ok timeout")))
            task.cancel(with: .goingAway, reason: nil)
            return
        } catch let e as PairError {
            yield(.failed(e))
            task.cancel(with: .goingAway, reason: nil)
            return
        } catch {
            yield(.failed(PairError.transport(error)))
            task.cancel(with: .goingAway, reason: nil)
            return
        }

        if !helloOK.ok {
            let code = helloOK.error?["code"] as? String
            let message = helloOK.error?["message"] as? String ?? "rejected"
            if code == "AUTH_BOOTSTRAP_TOKEN_INVALID" {
                yield(.failed(PairError.setupCodeExpired))
            } else if code == "PAIRING_REQUIRED" {
                yield(.failed(PairError.pairingRequired))
            } else {
                yield(.failed(PairError.connectRejected(message)))
            }
            task.cancel(with: .goingAway, reason: nil)
            return
        }

        let auth = helloOK.payload.auth
        let primary = auth?.deviceToken ?? ""
        let operatorToken = auth?.deviceTokens?.first?.deviceToken
        let resolvedRole = auth?.role ?? role
        let scopes = auth?.scopes ?? []

        // In bootstrap/device-token mode, hello-ok MUST include a deviceToken.
        // In shared-token / password mode, hello-ok typically only echoes role+scopes
        // — the caller (OpenClawBackend.login) supplies the original token separately.
        let result = PairedResult(
            deviceToken: primary, // empty when shared-token mode; OpenClawBackend.login supplies its own
            operatorToken: operatorToken,
            role: resolvedRole,
            scopes: scopes,
            sessionID: helloOK.payload.server.connId,
            gatewayVersion: helloOK.payload.server.version,
            stableID: link.stableID
        )
        // silence the unused warning if signedAt ever feeds signature later
        _ = signedAt
        yield(.paired(result))
        // Leave `task` alive; the caller decides when to close.
    }

    // MARK: - Codable Wire Types

    private struct ConnectChallenge: Decodable {
        let type: String
        let event: String
        let payload: Payload
        struct Payload: Decodable { let nonce: String; let ts: Int64? }
    }

    private struct HelloOKResponse {
        let ok: Bool
        let payload: HelloOKPayload
        let error: [String: Any]?
    }

    private struct HelloOKPayload: Decodable {
        let server: Server
        let auth: Auth?
        struct Server: Decodable { let version: String; let connId: String }
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
    }

    private struct ConnectRequest: Encodable {
        let type: String = "req"
        let id: String
        let method: String
        let params: ConnectParams
    }

    private struct ConnectParams: Encodable {
        let minProtocol: Int
        let maxProtocol: Int
        let client: ClientInfoFrame
        let caps: [String]
        let commands: [String]
        let permissions: [String: Bool]
        let auth: ConnectAuthFrame
        let role: String
        let scopes: [String]
        let locale: String
        let userAgent: String
    }

    private struct ClientInfoFrame: Encodable {
        let id: String
        let displayName: String
        let version: String
        let platform: String
        let deviceFamily: String?
        let mode: String
        let instanceId: String
    }

    fileprivate struct ConnectAuthFrame: Encodable {
        // Encode exactly one of these, mirroring the server-side union type
        // (`auth.token | auth.password | auth.bootstrapToken | auth.deviceToken`).
        // Per docs/gateway/protocol.md, the server picks based on which key is present.
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

        // Use a manual encode so Swift's default JSON encoder doesn't write all four
        // keys with explicit nulls — the server expects only the one that's present.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let v = token { try container.encode(v, forKey: .token) }
            if let v = password { try container.encode(v, forKey: .password) }
            if let v = bootstrapToken { try container.encode(v, forKey: .bootstrapToken) }
            if let v = deviceToken { try container.encode(v, forKey: .deviceToken) }
        }

        enum CodingKeys: String, CodingKey {
            case token, password, bootstrapToken, deviceToken
        }
    }

    /// Which auth credential to ride on the connect frame.
    fileprivate enum AuthMode: Sendable {
        case sharedToken(String)
        case bootstrapToken(String)
        case deviceToken(String)
        case password(String)

        fileprivate func encoded() -> ConnectAuthFrame {
            switch self {
            case .sharedToken(let v): return ConnectAuthFrame(token: v)
            case .bootstrapToken(let v): return ConnectAuthFrame(bootstrapToken: v)
            case .deviceToken(let v): return ConnectAuthFrame(deviceToken: v)
            case .password(let v): return ConnectAuthFrame(password: v)
            }
        }
    }

    // MARK: - Helpers

    private static func decode<T: Decodable>(_ type: T.Type, from msg: URLSessionWebSocketTask.Message) throws -> T {
        let data: Data
        switch msg {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default:
            throw PairError.transport(NSError(domain: "OpenClawPairing", code: -1))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func decodeRawJSON(_ msg: URLSessionWebSocketTask.Message) throws -> [String: Any] {
        let data: Data
        switch msg {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default:
            throw PairError.transport(NSError(domain: "OpenClawPairing", code: -1))
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PairError.transport(NSError(domain: "OpenClawPairing", code: -2))
        }
        return obj
    }

    /// Match loopback + RFC1918 + link-local + mDNS.
    static func isLoopbackOrLAN(host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h == "127.0.0.1" || h == "::1" || h.hasSuffix(".local") || h.hasSuffix(".lan") {
            return true
        }
        let parts = h.split(separator: ".")
        if parts.count == 4, let o0 = Int(parts[0]), let o1 = Int(parts[1]) {
            if o0 == 10 { return true }
            if o0 == 172 && (16...31).contains(o1) { return true }
            if o0 == 192 && o1 == 168 { return true }
            if o0 == 169 && o1 == 254 { return true }
            if o0 == 127 { return true }
        }
        return false
    }

    private struct TimeoutError: Error {}
    private static func withTimeout<T>(seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
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

// MARK: - Public Client Info

struct PairingClientInfo: Sendable {
    let clientID: String              // matches `GATEWAY_CLIENT_IDS.IOS_APP` = "openclaw-ios"
    let displayName: String           // user's device name
    let clientVersion: String         // app version
    let deviceFamily: String?         // "iPhone"
    let instanceID: String            // UUID generated once, persisted
    let caps: [String]                // node-mode capabilities (empty for operator/token)
    let commands: [String]            // node-mode commands (empty for operator/token)
    let permissions: [String: Bool]
    let mode: String                  // matches `GATEWAY_CLIENT_MODES` — "ui" or "node"

    static func defaultFor(appVersion: String) -> PairingClientInfo {
        let deviceName: String = {
            #if canImport(UIKit)
            return UIDevice.current.name
            #else
            return "iPhone"
            #endif
        }()
        return PairingClientInfo(
            clientID: "openclaw-ios",   // matches `GATEWAY_CLIENT_IDS.IOS_APP` from
                                         // openclaw/packages/gateway-protocol/src/client-info.ts:23
            displayName: deviceName,
            clientVersion: appVersion,
            deviceFamily: "iPhone",
            instanceID: OpenClawPairingKeychain.loadOrCreateInstanceID(),
            caps: [],                    // operator-mode has no caps; node caps go through the same field
            commands: [],
            permissions: [:],
            mode: "ui"                   // matches `GATEWAY_CLIENT_MODES.UI` from
                                         // openclaw/packages/gateway-protocol/src/client-info.ts:44
        )
    }
}

#if canImport(UIKit)
import UIKit
#endif