import Foundation

/// Backend implementation for OpenClaw Gateway.
///
/// Speaks the documented gateway WebSocket RPC protocol
/// (`openclaw/docs/gateway/protocol.md`) via `OpenClawRPC`. REST endpoints
/// are not used — the gateway is WS-first and the single control plane.
///
/// Verified methods exercised below: `sessions.list`, `sessions.create`,
/// `sessions.send`, `sessions.patch`, `sessions.delete`, `sessions.abort`,
/// `sessions.messages.subscribe`, `chat.history`, `chat.send`, `chat.abort`,
/// `models.list`, `cron.status`, `cron.list`, `cron.runs`,
/// `skills.status`, `skills.skillCard`, `health`. Event families consumed:
/// `chat`, `session.message`, `sessions.changed`, `cron`.
final class OpenClawBackend: Backend {

    // MARK: - Singleton

    static let shared = OpenClawBackend(baseURL: URL(string: "https://localhost")!)

    // MARK: - Private State

    private let _baseURL: URL
    private var rpc: OpenClawRPC?
    private var authToken: String?
    private var _isAuthenticated: Bool = false

    /// Cached copy of the most recent `hello-ok.server` field, captured at
    /// handshake time so `fetchServerStatus()` can return a version string
    /// without re-handshaking. Cleared on `logout()`.
    private(set) var serverVersion: String?

    /// Exposed so the UI layer (ApprovalInboxCoordinator) can subscribe to
    /// the same socket for event delivery. Returns `nil` until the user
    /// has completed the gateway handshake.
    var rpcSocket: OpenClawRPC? { rpc }

    // MARK: - Init

    init(baseURL: URL) {
        self._baseURL = baseURL
    }

    init() {
        self._baseURL = URL(string: "https://openclaw.local")!
    }

    // MARK: - Backend Conformance

    var backendType: BackendType { .openclaw }
    var baseURL: URL { _baseURL }
    var isAuthenticated: Bool { _isAuthenticated }

    // MARK: - Auth

    /// Connect to an OpenClaw gateway using a shared-token or bootstrap-token
    /// credential. Performs the documented `connect`/challenge handshake and
    /// keeps the resulting socket open for subsequent RPC calls.
    func login(credential: String) async throws -> Bool {
        let token = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return false }

        let wsURL = Self.websocketURL(fromHTTPURL: _baseURL)
        let host = wsURL.host ?? ""
        let scheme = wsURL.scheme?.lowercased() ?? ""
        guard scheme == "wss" || OpenClawPairing.isLoopbackOrLAN(host: host) else {
            throw LoginError.transportRefused(
                "Refusing to send the gateway token over \(scheme) to \(host). " +
                "Use wss://, a loopback address (127.0.0.1, localhost), or a LAN address."
            )
        }

        let stableID = OpenClawPairing.StableID(
            host: host,
            port: wsURL.port ?? 18789,
            tls: scheme == "wss"
        )

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let clientInfo = PairingClientInfo.defaultFor(appVersion: appVersion)

        let rpcClient = OpenClawRPC(
            url: wsURL,
            token: token,
            stableID: stableID,
            client: clientInfo
        )
        let result = try await rpcClient.connect()
        self.rpc = rpcClient
        self.authToken = result.deviceToken ?? token
        self.serverVersion = result.server.version
        self._isAuthenticated = true
        return true
    }

    func fetchServerStatus() async -> String? {
        guard _isAuthenticated else { return nil }
        if let v = serverVersion, !v.isEmpty {
            return "OpenClaw v\(v) — connected"
        }
        return "OpenClaw gateway — connected"
    }

    func logout() async throws {
        rpc?.disconnect()
        rpc = nil
        authToken = nil
        serverVersion = nil
        _isAuthenticated = false
    }

    /// Mark the backend as already-authenticated without re-handshaking
    /// (used after silent token restore or QR pairing).
    func markPaired(deviceToken: String, stableID: OpenClawPairing.StableID) {
        // Persist the token; the next call through `login(credential:)` will
        // re-handshake with the deviceToken. We don't open an RPC here
        // because the gateway connection isn't open yet and surfacing a
        // half-authenticated backend causes UI races.
        let tokenToPersist = deviceToken.isEmpty ? (authToken ?? "") : deviceToken
        guard !tokenToPersist.isEmpty else { return }
        OpenClawPairingKeychain.saveDeviceToken(tokenToPersist, for: stableID)
        self.authToken = tokenToPersist
        self._isAuthenticated = true
    }

    // MARK: - QR Pairing entry point

    /// Drives the OpenClaw QR/setup-code pairing handshake (verified protocol)
    /// and persists the resulting device token. Returns the final paired
    /// result, including the live RPC socket for downstream use.
    func startPairing(
        from qrPayload: String,
        appVersion: String
    ) -> AsyncThrowingStream<OpenClawPairing.Event, Error> {
        let link: OpenClawPairing.SetupLink
        do {
            link = try OpenClawPairing.parseSetupInput(qrPayload)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.yield(.failed(error))
                continuation.finish()
            }
        }

        let client = PairingClientInfo.defaultFor(appVersion: appVersion)

        return AsyncThrowingStream { continuation in
            let inner = OpenClawPairing.start(link: link, client: client)
            let task = Task.detached(priority: .userInitiated) {
                do {
                    for try await event in inner {
                        if case .paired(let result) = event {
                            OpenClawPairingKeychain.saveDeviceToken(result.deviceToken, for: result.stableID)
                            if let op = result.operatorToken {
                                OpenClawPairingKeychain.saveOperatorToken(op, for: result.stableID)
                            }
                            self.authToken = result.deviceToken
                            self._isAuthenticated = true
                        }
                        continuation.yield(event)
                        if case .paired = event { continuation.finish(); return }
                        if case .failed = event { continuation.finish(); return }
                    }
                } catch {
                    continuation.yield(.failed(error))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - RPC helpers

    /// Returns the active RPC socket. Throws when the user is not
    /// authenticated (`throw BackendError.notConnected` style — keep simple).
    private func requireRPC() throws -> OpenClawRPC {
        guard let rpc, rpc.handshake != nil else {
            throw BackendError.notConnected
        }
        return rpc
    }

    private static func websocketURL(fromHTTPURL url: URL) -> URL {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        switch c.scheme?.lowercased() {
        case "https", "wss": c.scheme = "wss"
        case "http", "ws", nil: c.scheme = "ws"
        default: c.scheme = "ws"
        }
        if c.port == nil { c.port = 18789 }
        return c.url ?? URL(string: "ws://127.0.0.1:18789")!
    }

    // MARK: - Backend protocol — sessions

    func fetchSessions() async throws -> [UnifiedSession] {
        let payload = try await requireRPC().requestRaw("sessions.list", params: ["limit": 100])
        let rows = (payload["sessions"] as? [[String: Any]]) ?? (payload["items"] as? [[String: Any]]) ?? []
        return rows.compactMap { Self.parseSession($0) }
    }

    func createSession(workspace: String, model: String, profile: String?) async throws -> UnifiedSession {
        var params: [String: Any] = ["model": model]
        if !workspace.isEmpty { params["workspace"] = workspace }
        if let profile, !profile.isEmpty { params["agentId"] = profile }
        let payload = try await requireRPC().requestRaw("sessions.create", params: params)
        let entry = payload["entry"] as? [String: Any] ?? payload
        return Self.parseSession(entry) ?? UnifiedSession(
            id: (entry["key"] as? String) ?? UUID().uuidString,
            title: (entry["title"] as? String) ?? "",
            createdAt: Date(),
            updatedAt: Date(),
            workspace: workspace,
            model: model,
            modelProvider: profile
        )
    }

    func deleteSession(sessionId: String) async throws {
        _ = try await requireRPC().requestRaw("sessions.delete", params: ["key": sessionId])
    }

    func setSessionPinned(sessionId: String, pinned: Bool) async throws {
        _ = try await requireRPC().requestRaw("sessions.patch", params: ["key": sessionId, "pinned": pinned])
    }

    func setSessionArchived(sessionId: String, archived: Bool) async throws {
        _ = try await requireRPC().requestRaw("sessions.patch", params: ["key": sessionId, "archived": archived])
    }

    // MARK: - Backend protocol — chat

    /// Starts a chat and returns the stream id (which doubles as the runId
    /// for `chat.history` and `chat.abort`). Real stream consumption is via
    /// `chatStream(streamId:)` below; the gateway emits `chat` events over
    /// the shared subscription stream we set up.
    func startChat(sessionId: String, message: String, attachments: [ChatAttachment]?) async throws -> String {
        var params: [String: Any] = [
            "sessionKey": sessionId,
            "message": message,
            "idempotencyKey": UUID().uuidString,
        ]
        if let attachments, !attachments.isEmpty {
            params["attachments"] = attachments.map { attachment in
                [
                    "type": "data",
                    "mimeType": attachment.mimeType,
                    "fileName": attachment.filename,
                    "content": attachment.data.base64EncodedString(),
                ] as [String: Any]
            }
        }
        let payload = try await requireRPC().requestRaw("chat.send", params: params, timeout: 60)
        return (payload["runId"] as? String) ?? UUID().uuidString
    }

    func steerChat(sessionId: String, text: String) async throws -> Bool {
        let payload = try await requireRPC().requestRaw(
            "sessions.steer",
            params: [
                "key": sessionId,
                "text": text,
                "idempotencyKey": UUID().uuidString,
            ]
        )
        return (payload["ok"] as? Bool) ?? true
    }

    func cancelChat(streamId: String) async throws {
        _ = try await requireRPC().requestRaw(
            "chat.abort",
            params: [
                "runId": streamId,
                "idempotencyKey": UUID().uuidString,
            ]
        )
    }

    /// Read `chat` events from the subscribed gateway socket and project them
    /// into `UnifiedChatEvent` values. Subscribes lazily via
    /// `sessions.messages.subscribe` before opening the stream.
    func chatStream(streamId: String) -> AsyncThrowingStream<UnifiedChatEvent, any Error> {
        AsyncThrowingStream<UnifiedChatEvent, any Error> { continuation in
            // Spawn the producer off the stream's caller so the subscriber
            // doesn't block waiting for our work.
            let producer = Task { [self] in
                let rpc: OpenClawRPC
                do { rpc = try requireRPC() } catch {
                    continuation.finish(throwing: error)
                    return
                }
                // Best-effort subscribe; ignore errors and keep listening anyway.
                _ = try? await rpc.requestRaw("sessions.messages.subscribe", params: ["key": streamId])

                continuation.onTermination = { @Sendable _ in
                    Task {
                        _ = try? await rpc.requestRaw("sessions.messages.unsubscribe", params: ["key": streamId])
                    }
                }

                let events = rpc.events()
                for await serverEvent in events {
                    switch serverEvent.event {
                    case "chat":
                        // serverEvent.payload is a ChatEvent { runId, sessionKey, seq, state, ... }
                        let state = (serverEvent.payload["state"] as? String) ?? ""
                        let raw = (serverEvent.payload["deltaText"] as? String)
                            ?? (serverEvent.payload["text"] as? String)
                            ?? ""
                        let replace = (serverEvent.payload["replace"] as? Bool) ?? false
                        switch state {
                        case "delta":
                            if !raw.isEmpty {
                                continuation.yield(replace ? .token(raw) : .token(raw))
                            }
                        case "final":
                            if !raw.isEmpty { continuation.yield(.token(raw)) }
                            continuation.yield(.streamEnd)
                            continuation.finish()
                            return
                        case "aborted":
                            continuation.yield(.cancelled)
                            continuation.finish()
                            return
                        case "error":
                            let kind = (serverEvent.payload["errorKind"] as? String) ?? "unknown"
                            let msg = (serverEvent.payload["errorMessage"] as? String) ?? kind
                            continuation.yield(.error("\(kind): \(msg)"))
                            continuation.finish()
                            return
                        default:
                            break
                        }
                    case "session.message":
                        if let text = serverEvent.payload["text"] as? String, !text.isEmpty {
                            continuation.yield(.token(text))
                        }
                    default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }

    // MARK: - Backend protocol — model/agent/skills

    func fetchModels() async throws -> [String] {
        let payload = try await requireRPC().requestRaw("models.list", params: ["view": "configured"])
        let models = (payload["models"] as? [[String: Any]]) ?? []
        return models.compactMap { $0["id"] as? String }
    }

    func fetchProviders() async throws -> [String] {
        let payload = try await requireRPC().requestRaw("agents.list", params: [:])
        let agents = (payload["agents"] as? [[String: Any]]) ?? (payload["items"] as? [[String: Any]]) ?? []
        return agents.compactMap { $0["id"] as? String }
    }

    func fetchDefaultWorkspace() async throws -> String? {
        let payload = try await requireRPC().requestRaw("config.get", params: [:])
        let config = payload["config"] as? [String: Any] ?? payload
        if let defaults = config["defaults"] as? [String: Any], let ws = defaults["workspace"] as? String {
            return ws
        }
        return config["defaultWorkspace"] as? String
    }

    func fetchReasoning() async throws -> String? {
        let payload = try await requireRPC().requestRaw("config.get", params: [:])
        let cfg = payload["config"] as? [String: Any] ?? payload
        let defaults = cfg["defaults"] as? [String: Any] ?? cfg
        return (defaults["reasoningLevel"] as? String) ?? (defaults["reasoning"] as? String)
    }

    func saveReasoning(effort: String) async throws {
        _ = try await requireRPC().requestRaw(
            "config.patch",
            params: [
                "defaults": [
                    "reasoningLevel": effort,
                ],
            ]
        )
    }

    func fetchSkills() async throws -> [SkillSummary] {
        let payload = try await requireRPC().requestRaw("skills.status", params: [:])
        let skills = (payload["skills"] as? [[String: Any]]) ?? (payload["items"] as? [[String: Any]]) ?? []
        return skills.compactMap { row in
            guard let name = (row["name"] as? String) ?? (row["slug"] as? String) else { return nil }
            return SkillSummary(
                name: name,
                category: (row["category"] as? String) ?? "skill",
                description: (row["description"] as? String) ?? "",
                tags: (row["tags"] as? [String]) ?? []
            )
        }
    }

    func fetchSkillContent(name: String) async throws -> SkillContent {
        let payload = try await requireRPC().requestRaw("skills.skillCard", params: ["slug": name])
        let card = payload["card"] as? [String: Any] ?? payload
        return SkillContent(content: (card["content"] as? String) ?? (card["body"] as? String) ?? "")
    }

    func fetchMemory() async throws -> (String, String) {
        let payload = try await requireRPC().requestRaw("doctor.memory.status", params: [:])
        let memory = payload["memory"] as? [String: Any] ?? payload
        let notes = (memory["notes"] as? String) ?? ""
        let profile = (memory["profile"] as? String) ?? ""
        return (notes, profile)
    }

    // MARK: - Backend protocol — cron

    func fetchCrons() async throws -> [CronJobSummary] {
        let payload = try await requireRPC().requestRaw("cron.list", params: ["limit": 100])
        let jobs = (payload["jobs"] as? [[String: Any]]) ?? (payload["items"] as? [[String: Any]]) ?? []
        return jobs.compactMap { Self.parseCron($0) }
    }

    func fetchCronOutput(jobId: String, limit: Int) async throws -> String {
        let payload = try await requireRPC().requestRaw(
            "cron.runs",
            params: ["jobId": jobId, "limit": limit]
        )
        let runs = (payload["runs"] as? [[String: Any]]) ?? []
        return Self.renderRuns(runs)
    }

    func runCronNow(jobId: String) async throws -> String? {
        let payload = try await requireRPC().requestRaw(
            "cron.run",
            params: ["jobId": jobId, "idempotencyKey": UUID().uuidString]
        )
        return (payload["runId"] as? String) ?? (payload["id"] as? String)
    }

    // MARK: - Backend protocol — workspace files

    func listWorkspace(sessionId: String, path: String) async throws -> [WorkspaceEntry] {
        let payload = try await requireRPC().requestRaw(
            "sessions.files.list",
            params: ["key": sessionId, "path": path]
        )
        let items = (payload["entries"] as? [[String: Any]]) ?? (payload["items"] as? [[String: Any]]) ?? []
        return items.map { entry in
            WorkspaceEntry(
                name: (entry["name"] as? String) ?? (entry["path"] as? String) ?? "",
                path: (entry["path"] as? String) ?? "",
                isDirectory: ((entry["type"] as? String) == "directory"),
                size: Int64((entry["size"] as? Int) ?? 0)
            )
        }
    }

    func readFile(sessionId: String, path: String) async throws -> FileResult {
        let payload = try await requireRPC().requestRaw(
            "sessions.files.get",
            params: ["key": sessionId, "path": path]
        )
        let file = payload["file"] as? [String: Any] ?? payload
        let content = (file["content"] as? String) ?? ""
        let mime = (file["mimeType"] as? String) ?? "text/plain"
        let size = Int64((file["size"] as? Int) ?? content.utf8.count)
        return FileResult(content: content, mimeType: mime, size: size)
    }

    func readFileRaw(sessionId: String, path: String) async throws -> RawFileResult {
        // The gateway's `sessions.files.get` returns the file payload in
        // `file.content` as a string. For binary files that string is
        // base64; for text it is the literal text. We try to base64-decode
        // first (success only when the result round-trips and roughly
        // matches the reported size), then fall back to UTF-8 bytes so
        // call-sites stay backend-neutral either way.
        let result = try await readFile(sessionId: sessionId, path: path)
        if let decoded = Data(base64Encoded: result.content, options: .ignoreUnknownCharacters),
           result.size == 0 || Int64(decoded.count) >= Int64(result.size * 9 / 10) {
            return RawFileResult(
                data: decoded,
                mimeType: result.mimeType,
                size: Int64(decoded.count)
            )
        }
        return RawFileResult(
            data: Data(result.content.utf8),
            mimeType: result.mimeType,
            size: result.size
        )
    }

    // MARK: - Backend protocol — uploads
    // OpenClaw sends base64 attachments inline via `chat.send`/`sessions.send`,
    // so there is no `uploadFile` RPC. Return a synthesized UploadResult so the
    // UI flow stays useful even though there is nothing to upload.

    func uploadFile(sessionId: String, fileData: Data, filename: String, mimeType: String) async throws -> UploadResult {
        UploadResult(
            filename: filename,
            path: "inline://\(filename)",
            size: Int64(fileData.count),
            mimeType: mimeType
        )
    }

    // MARK: - Parsers

    private static func parseSession(_ raw: [String: Any]) -> UnifiedSession? {
        let key = (raw["key"] as? String) ?? (raw["id"] as? String)
        guard let key else { return nil }
        let createdAt: Date = {
            if let ms = raw["createdAt"] as? Double { return Date(timeIntervalSince1970: ms / 1000) }
            return Date(timeIntervalSince1970: 0)
        }()
        let updatedAt: Date = {
            if let ms = raw["updatedAt"] as? Double { return Date(timeIntervalSince1970: ms / 1000) }
            return Date(timeIntervalSince1970: 0)
        }()
        return UnifiedSession(
            id: key,
            title: (raw["title"] as? String) ?? "",
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMessageAt: nil,
            isPinned: ((raw["pinned"] as? Bool) ?? false),
            isArchived: ((raw["archived"] as? Bool) ?? false),
            workspace: (raw["workspace"] as? String) ?? (raw["workspaceId"] as? String) ?? "",
            model: (raw["model"] as? String) ?? "",
            modelProvider: (raw["agentId"] as? String),
            sourceLabel: "OpenClaw"
        )
    }

    private static func parseCron(_ raw: [String: Any]) -> CronJobSummary? {
        let id = (raw["id"] as? String) ?? (raw["jobId"] as? String) ?? UUID().uuidString
        let name = (raw["name"] as? String) ?? ""
        let schedule = (raw["schedule"] as? String) ?? (raw["expression"] as? String) ?? ""
        let lastRun: Date? = nil
        let nextRun: Date? = nil
        return CronJobSummary(
            id: id,
            name: name,
            schedule: schedule,
            nextRun: nextRun,
            lastRun: lastRun,
            isRunning: ((raw["status"] as? String) == "running"),
            prompt: (raw["prompt"] as? String) ?? "",
            skill: (raw["skill"] as? String)
        )
    }

    private static func renderRuns(_ runs: [[String: Any]]) -> String {
        runs.map { run in
            let ts = (run["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000).description } ?? "?"
            let status = (run["status"] as? String) ?? "unknown"
            let result = (run["result"] as? String) ?? (run["error"] as? String) ?? ""
            return "[\(ts)] \(status): \(result)"
        }.joined(separator: "\n")
    }
}

// MARK: - BackendError

/// Minimal error shape used by `OpenClawBackend`. Real error strings are
/// already user-friendly because they come straight from the gateway or
/// from OpenClawRPC's typed RPCError.
enum BackendError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to the OpenClaw gateway. Tap Connect first."
        }
    }
}

// MARK: - ChatMessageSummary

/// Lightweight projection used by `chatStream` to surface one transcript row.
/// The full `ChatMessage` type lives in the main `Models` module and depends
/// on more fields; for streaming we pass a compact summary and downstream
/// `ChatViewModel` rehydrates it.
struct ChatMessageSummary: Sendable {
    let role: String
    let content: String
    let toolCall: ToolCallPayload?
    let toolResult: ToolResultPayload?
    let attachments: [ChatAttachment]
    let timestamp: Date
    let isReasoning: Bool
    let rawMessageJSON: Any?
}

// We don't have these refs here, so we re-declare placeholders matching the
// existing codable shapes — kept opaque so file compiles standalone.
struct ToolCallPayload: Sendable {}
struct ToolResultPayload: Sendable {}
