import Foundation

/// Backend implementation for OpenClaw Gateway.
///
/// Uses the OpenClaw gateway REST API for auth, sessions, models, skills, files,
/// and WebSocket RPC for real-time chat streaming.
final class OpenClawBackend: Backend {

    // MARK: - Singleton

    static let shared = OpenClawBackend(baseURL: URL(string: "https://localhost")!)

    // MARK: - Private State

    private let _baseURL: URL

    private var authToken: String?
    private var _isAuthenticated: Bool = false

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

    func login(usernameOrEmail: String, passwordOrAPIKey: String) async throws -> Bool {
        // `passwordOrAPIKey` is the gateway token (from `openclaw config get gateway.auth.token`).
        // It must be authenticated against the gateway's WebSocket handshake — there is
        // no /login HTTP endpoint; auth is in-band on the connect frame.
        let credential = passwordOrAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else { return false }

        // Resolve WS URL from `_baseURL` (HTTP/S URL). Default port 18789.
        let wsURL = Self.websocketURL(fromHTTPURL: _baseURL)
        let stableID = OpenClawPairing.StableID(
            host: wsURL.host ?? "localhost",
            port: wsURL.port ?? 18789,
            tls: (wsURL.scheme ?? "").lowercased() == "wss"
        )

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let client = PairingClientInfo.defaultFor(appVersion: appVersion)

        let stream = OpenClawPairing.start(
            token: credential,
            websocketURL: wsURL,
            stableID: stableID,
            client: client
        )

        var didPair = false
        for try await event in stream {
            switch event {
            case .paired(let result):
                // For shared-token mode, hello-ok may not include a new deviceToken —
                // the original gateway token is the credential we keep using.
                let tokenToPersist = result.deviceToken.isEmpty ? credential : result.deviceToken
                OpenClawPairingKeychain.saveDeviceToken(tokenToPersist, for: stableID)
                self.authToken = tokenToPersist
                self._isAuthenticated = true
                didPair = true
            case .failed(let error):
                throw error
            default:
                continue
            }
        }
        return didPair
    }

    /// Convert an http(s):// URL into a ws(s):// URL pointing at the same host.
    /// Default OpenClaw gateway port is 18789 (`gateway.port`).
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

    func logout() async throws {
        authToken = nil
        _isAuthenticated = false
    }

    // MARK: - QR Pairing entry point

    /// Drives the OpenClaw QR/setup-code pairing handshake and persists the
    /// resulting device token. Returns the final paired result.
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
                            // Persist durable device token, drop bootstrap token.
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

    // MARK: - Stub Backend protocol methods
    // Real implementations should be re-added one at a time after the
    // conformance passes. For now these are intentionally minimal so the
    // app builds and the auth + pairing flows are testable end-to-end.

    func fetchSessions() async throws -> [UnifiedSession] { [] }
    func createSession(workspace: String, model: String, profile: String?) async throws -> UnifiedSession {
        UnifiedSession(
            id: "", title: "",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            workspace: workspace, model: model, modelProvider: profile
        )
    }
    func deleteSession(sessionId: String) async throws {}
    func setSessionPinned(sessionId: String, pinned: Bool) async throws {}
    func setSessionArchived(sessionId: String, archived: Bool) async throws {}
    func startChat(sessionId: String, message: String, attachments: [ChatAttachment]?) async throws -> String { "" }
    func steerChat(sessionId: String, text: String) async throws -> Bool { false }
    func cancelChat(streamId: String) async throws {}
    func chatStream(streamId: String) -> AsyncThrowingStream<UnifiedChatEvent, any Error> {
        AsyncThrowingStream<UnifiedChatEvent, any Error> { _ in }
    }
    func uploadFile(sessionId: String, fileData: Data, filename: String, mimeType: String) async throws -> UploadResult {
        UploadResult(filename: filename, path: "/uploads/\(filename)", size: Int64(fileData.count), mimeType: mimeType)
    }
    func fetchModels() async throws -> [String] { [] }
    func fetchProviders() async throws -> [String] { [] }
    func fetchReasoning() async throws -> String? { nil }
    func saveReasoning(effort: String) async throws {}
    func fetchSkills() async throws -> [SkillSummary] { [] }
    func fetchSkillContent(name: String) async throws -> SkillContent { SkillContent(content: "") }
    func fetchMemory() async throws -> (String, String) { ("", "") }
    func fetchCrons() async throws -> [CronJobSummary] { [] }
    func fetchCronOutput(jobId: String, limit: Int) async throws -> String { "" }
    func listWorkspace(sessionId: String, path: String) async throws -> [WorkspaceEntry] { [] }
    func readFile(sessionId: String, path: String) async throws -> FileResult {
        FileResult(content: "", mimeType: "text/plain", size: 0)
    }
    func readFileRaw(sessionId: String, path: String) async throws -> RawFileResult {
        RawFileResult(data: Data(), mimeType: "application/octet-stream", size: 0)
    }
}