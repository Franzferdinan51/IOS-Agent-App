import Foundation

/// Backend implementation for OpenClaw Gateway.
///
/// Uses the OpenClaw gateway REST API for auth, sessions, models, skills, files,
/// and WebSocket RPC for real-time chat streaming.
final class OpenClawBackend: Backend {

    // MARK: - Singleton

    static let shared = OpenClawBackend()

    // MARK: - Private State

    private let apiClient = APIClient.shared
    private let _baseURL: URL

    /// Auth token stored in memory after login.
    private var authToken: String?

    /// Cached auth status based on presence of token.
    private var _isAuthenticated: Bool = false

    // MARK: - Init

    /// Initialize with a gateway base URL.
    /// - Parameter baseURL: The base URL of the OpenClaw gateway (e.g., https://gateway.example.com).
    init(baseURL: URL) {
        self._baseURL = baseURL
    }

    /// Default initializer with a placeholder URL.
    init() {
        self._baseURL = URL(string: "https://openclaw.local")!
    }

    // MARK: - Backend Conformance

    var backendType: BackendType { .openclaw }

    var baseURL: URL { _baseURL }

    var isAuthenticated: Bool { _isAuthenticated }

    // MARK: - Auth

    func login(usernameOrEmail: String, passwordOrAPIKey: String) async throws -> Bool {
        // usernameOrEmail may be "token"/"apiKey" for token auth.
        // OpenClaw gateway supports token-based auth via /v1/auth/token.
        // Also supports bootstrap-token, device-token, password in ConnectParams.
        let credentials: [String: String] = [
            "username": usernameOrEmail,
            "password": passwordOrAPIKey,
        ]
        if let token = credentials["token"] ?? credentials["apiKey"] {
            authToken = token
            _isAuthenticated = true
            return true
        }
        if let password = credentials["password"] {
            // POST /v1/auth with password
            let url = baseURL.appendingPathComponent("v1/auth")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = ["password": password]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let response: OpenClawAuthResponse = try await apiClient.request(request, decoding: OpenClawAuthResponse.self)
            authToken = response.token ?? response.accessToken
            _isAuthenticated = authToken != nil
            return _isAuthenticated
        }
        throw BackendError.invalidCredentials("Provide 'token', 'apiKey', or 'password' in credentials")
    }

    func logout() async throws {
        authToken = nil
        _isAuthenticated = false
        // Optionally call DELETE /v1/auth/token to invalidate server-side.
        if _isAuthenticated {
            let url = baseURL.appendingPathComponent("v1/auth/token")
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            try await addAuthHeader(to: &request)
            _ = try? await apiClient.requestData(request)
        }
    }

    // MARK: - Sessions

    func fetchSessions() async throws -> [UnifiedSession] {
        let url = baseURL.appendingPathComponent("v1/sessions")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try await addAuthHeader(to: &request)

        let response: OpenClawSessionsResponse = try await apiClient.request(request, decoding: OpenClawSessionsResponse.self)
        return response.sessions.map { $0.toUnifiedSession() }
    }

    func createSession(workspace: String, model: String, profile: String?) async throws -> UnifiedSession {
        let url = baseURL.appendingPathComponent("v1/sessions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        try await addAuthHeader(to: &request)

        var body: [String: Any] = [
            "workspace": workspace,
            "model": model
        ]
        if let profile = profile {
            body["label"] = profile
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let response: OpenClawCreateSessionResponse = try await apiClient.request(request, decoding: OpenClawCreateSessionResponse.self)
        return response.toUnifiedSession()
    }

    func deleteSession(sessionId: String) async throws {
        let url = baseURL.appendingPathComponent("v1/sessions/\(sessionId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        try await addAuthHeader(to: &request)
        _ = try await apiClient.requestData(request)
    }

    func setSessionPinned(sessionId: String, pinned: Bool) async throws {
        let url = baseURL.appendingPathComponent("v1/sessions/\(sessionId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        try await addAuthHeader(to: &request)
        let body: [String: Any] = ["pinned": pinned]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await apiClient.requestData(request)
    }

    func setSessionArchived(sessionId: String, archived: Bool) async throws {
        let url = baseURL.appendingPathComponent("v1/sessions/\(sessionId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        try await addAuthHeader(to: &request)
        let body: [String: Any] = ["archived": archived]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await apiClient.requestData(request)
    }

    // MARK: - Chat (WebSocket)

    /// Starts a chat by sending `chat.start` over a new WebSocket connection.
    /// Returns a stream-id constructed from the session key + runId.
    func startChat(sessionId: String, message: String, attachments: [ChatAttachment]?) async throws -> String {
        guard let token = authToken else {
            throw BackendError.notAuthenticated
        }

        // Build WebSocket URL — gateway WS path is derived from baseURL
        let wsURL = buildWebSocketURL(path: "/v1/chat/stream", queryItems: [
            URLQueryItem(name: "sessionKey", value: sessionId)
        ])

        let wsClient = WSClient(url: wsURL, session: .shared)
        wsClient.setAccessToken(token)

        // Open WebSocket and send chat.start RPC
        let streamId = "\(sessionId)-\(UUID().uuidString)"

        for await result in wsClient.messages() {
            switch result {
            case .success(let msg):
                if case .text(let text) = msg {
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let frameType = json["type"] as? String {
                        switch frameType {
                        case "res":
                            // Response to our chat.start — extract runId for the stream id
                            if let payload = json["payload"] as? [String: Any],
                               let runId = payload["runId"] as? String ?? payload["run_id"] as? String {
                                wsClient.disconnect()
                                return "\(sessionId)-\(runId)"
                            }
                        case "event":
                            wsClient.disconnect()
                            return streamId
                        default:
                            break
                        }
                    }
                }
            case .failure:
                wsClient.disconnect()
                break
            }
        }

        wsClient.disconnect()
        return streamId
    }

    /// Sends a steer command via WebSocket RPC `chat.steer`.
    func steerChat(sessionId: String, text: String) async throws -> Bool {
        guard let token = authToken else {
            throw BackendError.notAuthenticated
        }

        let wsURL = buildWebSocketURL(path: "/v1/chat/stream", queryItems: [
            URLQueryItem(name: "sessionKey", value: sessionId)
        ])
        let wsClient = WSClient(url: wsURL, session: .shared)
        wsClient.setAccessToken(token)

        let requestId = UUID().uuidString
        let steerFrame: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.steer",
            "params": ["sessionKey": sessionId, "text": text]
        ]

        var accepted = false
        if let data = try? JSONSerialization.data(withJSONObject: steerFrame),
           let text = String(data: data, encoding: .utf8) {
            try await wsClient.send(text)

            for await result in wsClient.messages() {
                if case .success(let msg) = msg {
                    if case .text(let txt) = msg,
                       let responseData = txt.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                       let frameType = json["type"] as? String,
                       frameType == "res",
                       let resId = json["id"] as? String,
                       resId == requestId {
                        accepted = (json["ok"] as? Bool) ?? false
                        break
                    }
                } else {
                    break
                }
            }
        }

        wsClient.disconnect()
        return accepted
    }

    /// Cancels an active chat stream via WebSocket RPC `chat.cancel`.
    func cancelChat(streamId: String) async throws {
        guard let token = authToken else {
            throw BackendError.notAuthenticated
        }

        // Parse session key from stream id (format: "sessionKey-runId")
        let components = streamId.split(separator: "-", maxSplits: 1)
        guard components.count >= 1 else { return }
        let sessionKey = String(components[0])
        let runId = components.count > 1 ? String(components[1]) : nil

        let wsURL = buildWebSocketURL(path: "/v1/chat/stream", queryItems: [
            URLQueryItem(name: "sessionKey", value: sessionKey)
        ])
        let wsClient = WSClient(url: wsURL, session: .shared)
        wsClient.setAccessToken(token)

        var params: [String: Any] = ["sessionKey": sessionKey]
        if let runId = runId {
            params["runId"] = runId
        }

        let cancelFrame: [String: Any] = [
            "type": "req",
            "id": UUID().uuidString,
            "method": "chat.cancel",
            "params": params
        ]

        if let data = try? JSONSerialization.data(withJSONObject: cancelFrame),
           let text = String(data: data, encoding: .utf8) {
            try? await wsClient.send(text)
        }

        wsClient.disconnect()
    }

    // MARK: - Upload

    func uploadFile(sessionId: String, fileData: Data, filename: String, mimeType: String) async throws -> UploadResult {
        let url = baseURL.appendingPathComponent("v1/upload")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        try await addAuthHeader(to: &request)

        // Build multipart/form-data manually
        let boundary = UUID().uuidString
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // sessionId field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"sessionKey\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(sessionId)\r\n".data(using: .utf8)!)

        // file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let response: OpenClawUploadResponse = try await apiClient.request(request, decoding: OpenClawUploadResponse.self)
        return UploadResult(
            filename: response.filename ?? filename,
            path: response.path ?? "/uploads/\(filename)",
            mimeType: mimeType,
            size: Int64(fileData.count)
        )
    }

    // MARK: - Models & Providers

    func fetchModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("v1/models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try await addAuthHeader(to: &request)

        let response: OpenClawModelsResponse = try await apiClient.request(request, decoding: OpenClawModelsResponse.self)
        return response.models.map { $0.id }
    }

    func fetchProviders() async throws -> [String] {
        let url = baseURL.appendingPathComponent("v1/models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try await addAuthHeader(to: &request)

        let response: OpenClawModelsResponse = try await apiClient.request(request, decoding: OpenClawModelsResponse.self)
        let providers = Set(response.models.map { $0.provider })
        return Array(providers).sorted()
    }

    // MARK: - Reasoning

    func fetchReasoning() async throws -> String? {
        // OpenClaw uses session.patch to store per-session reasoning level.
        // For a global default, query the agent config via `agents.list`.
        // Fallback: check session model config for reasoning flag.
        return nil
    }

    func saveReasoning(effort: String) async throws {
        // OpenClaw stores reasoning effort in session patch.
        // Not a global setting in OpenClaw — this would need a session key.
        // Throw to indicate it requires an active session context.
        throw BackendError.notSupported("saveReasoning requires an active session context in OpenClaw")
    }

    // MARK: - Skills

    func fetchSkills() async throws -> [SkillSummary] {
        let url = baseURL.appendingPathComponent("v1/skills/status")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try await addAuthHeader(to: &request)

        let response: OpenClawSkillsResponse = try await apiClient.request(request, decoding: OpenClawSkillsResponse.self)
        return response.skills.map { SkillSummary(name: $0.name, category: $0.category ?? "general", description: $0.description ?? "") }
    }

    func fetchSkillContent(name: String) async throws -> SkillContent {
        let url = baseURL.appendingPathComponent("v1/skills/detail")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "name", value: name)]
        request.url = components?.url
        try await addAuthHeader(to: &request)

        let response: OpenClawSkillContentResponse = try await apiClient.request(request, decoding: OpenClawSkillContentResponse.self)
        return SkillContent(
            markdown: response.content ?? "",
            linkedFiles: response.files ?? [:]
        )
    }

    // MARK: - Memory

    func fetchMemory() async throws -> (String, String) {
        // OpenClaw does not have a unified memory endpoint like Hermes.
        // Memory is stored per-session. Return empty for now.
        return ("", "")
    }

    // MARK: - Crons

    func fetchCrons() async throws -> [CronJobSummary] {
        let url = baseURL.appendingPathComponent("v1/crons")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try await addAuthHeader(to: &request)

        let response: OpenClawCronsResponse = try await apiClient.request(request, decoding: OpenClawCronsResponse.self)
        return response.crons.map { cron in
            CronJobSummary(
                id: cron.id,
                name: cron.name ?? cron.id,
                schedule: cron.schedule ?? "",
                nextRun: cron.nextRun.map { Date(timeIntervalSince1970: $0 / 1000) },
                lastRun: cron.lastRun.map { Date(timeIntervalSince1970: $0 / 1000) },
                isRunning: cron.state == "active" || cron.running == true,
                prompt: cron.payload?.prompt ?? "",
                skill: cron.payload?.skill
            )
        }
    }

    func fetchCronOutput(jobId: String, limit: Int) async throws -> String {
        let url = baseURL.appendingPathComponent("v1/crons/\(jobId)/output")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        request.url = components?.url
        try await addAuthHeader(to: &request)

        let response: OpenClawCronOutputResponse = try await apiClient.request(request, decoding: OpenClawCronOutputResponse.self)
        return response.output
    }

    // MARK: - Workspace

    func listWorkspace(sessionId: String, path: String) async throws -> [WorkspaceEntry] {
        let url = baseURL.appendingPathComponent("v1/sessions/files/list")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        try await addAuthHeader(to: &request)

        let body: [String: Any] = [
            "sessionKey": sessionId,
            "path": path
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let response: OpenClawFilesListResponse = try await apiClient.request(request, decoding: OpenClawFilesListResponse.self)
        return response.entries.map { entry in
            WorkspaceEntry(
                name: entry.name,
                path: entry.path,
                isDirectory: entry.kind == "directory",
                size: entry.size,
                modifiedAt: entry.updatedAtMs.map { Date(timeIntervalSince1970: $0 / 1000) }
            )
        }
    }

    func readFile(sessionId: String, path: String) async throws -> FileResult {
        let url = baseURL.appendingPathComponent("v1/sessions/files/get")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        try await addAuthHeader(to: &request)

        let body: [String: Any] = [
            "sessionKey": sessionId,
            "path": path
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let response: OpenClawFileContentResponse = try await apiClient.request(request, decoding: OpenClawFileContentResponse.self)
        return FileResult(
            content: response.content ?? "",
            mimeType: response.mimeType ?? "text/plain",
            size: response.size ?? 0
        )
    }

    func readFileRaw(sessionId: String, path: String) async throws -> RawFileResult {
        let url = baseURL.appendingPathComponent("v1/sessions/files/get")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        try await addAuthHeader(to: &request)

        let body: [String: Any] = [
            "sessionKey": sessionId,
            "path": path
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Ask for binary content
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "sessionKey", value: sessionId),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "raw", value: "true")
        ]
        request.url = components?.url

        let data = try await apiClient.requestData(request)
        let mimeType = mimeTypeForPath(path)
        return RawFileResult(data: data, mimeType: mimeType, size: data.count)
    }

    // MARK: - Private Helpers

    /// Adds Bearer auth header if token is available.
    private func addAuthHeader(to request: inout URLRequest) async throws {
        if let token = authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            throw BackendError.notAuthenticated
        }
    }

    /// Builds a WebSocket URL from the base URL.
    private func buildWebSocketURL(path: String, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        // Switch scheme to ws/wss
        if components.scheme == "https" {
            components.scheme = "wss"
        } else if components.scheme == "http" {
            components.scheme = "ws"
        }
        return components.url!
    }

    private func mimeTypeForPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "md": return "text/markdown"
        case "swift": return "text/swift"
        case "json": return "application/json"
        case "html": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Error Types

enum BackendError: LocalizedError {
    case invalidCredentials(String)
    case notAuthenticated
    case notSupported(String)
    case networkError(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCredentials(let msg): return "Invalid credentials: \(msg)"
        case .notAuthenticated: return "Not authenticated"
        case .notSupported(let msg): return "Not supported: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .invalidResponse: return "Invalid response from server"
        }
    }
}

// MARK: - OpenClaw Response Types

/// Auth response from POST /v1/auth
private struct OpenClawAuthResponse: Decodable {
    let token: String?
    let accessToken: String?

    enum CodingKeys: String, CodingKey {
        case token
        case accessToken = "access_token"
    }
}

/// Sessions list response from GET /v1/sessions
private struct OpenClawSessionsResponse: Decodable {
    let sessions: [OpenClawSession]
}

/// OpenClaw session row — maps to GatewaySessionRow fields
private struct OpenClawSession: Decodable {
    let key: String
    let sessionId: String?
    let title: String?
    let label: String?
    let model: String?
    let modelProvider: String?
    let createdAt: Int64?
    let updatedAt: Int64?
    let lastActiveAt: Int64?
    let agentId: String?
    let pinned: Bool?
    let archived: Bool?
    let activeMinutes: Int?
    let unread: Bool?
    let kind: String?
    let spawnedBy: String?
    let spawnedWorkspaceDir: String?
    let spawnedCwd: String?
    let forkedFromParent: Bool?
    let spawnDepth: Int?
    let subagentRole: String?
    let subagentControlScope: String?
    let usage: OpenClawUsage?

    enum CodingKeys: String, CodingKey {
        case key
        case sessionId = "sessionId"
        case title
        case label
        case model
        case modelProvider = "modelProvider"
        case createdAt = "createdAt"
        case updatedAt = "updatedAt"
        case lastActiveAt = "lastActiveAt"
        case agentId = "agentId"
        case pinned
        case archived
        case activeMinutes = "activeMinutes"
        case unread
        case kind
        case spawnedBy = "spawnedBy"
        case spawnedWorkspaceDir = "spawnedWorkspaceDir"
        case spawnedCwd = "spawnedCwd"
        case forkedFromParent = "forkedFromParent"
        case spawnDepth = "spawnDepth"
        case subagentRole = "subagentRole"
        case subagentControlScope = "subagentControlScope"
        case usage
    }

    struct OpenClawUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let estimatedCost: Double?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "inputTokens"
            case outputTokens = "outputTokens"
            case estimatedCost = "estimatedCost"
        }
    }

    func toUnifiedSession() -> UnifiedSession {
        UnifiedSession(
            id: sessionId ?? key,
            title: title ?? label ?? "Untitled",
            createdAt: createdAt.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? Date(),
            updatedAt: updatedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? Date(),
            lastMessageAt: lastActiveAt.map { Date(timeIntervalSince1970: Double($0) / 1000) },
            isPinned: pinned ?? false,
            isArchived: archived ?? false,
            projectId: nil,
            workspace: spawnedWorkspaceDir ?? spawnedCwd ?? "",
            model: model ?? "",
            inputTokens: usage?.inputTokens ?? 0,
            outputTokens: usage?.outputTokens ?? 0,
            estimatedCost: usage?.estimatedCost ?? 0
        )
    }
}

/// Create session response from POST /v1/sessions
private struct OpenClawCreateSessionResponse: Decodable {
    let ok: Bool?
    let key: String
    let sessionId: String?
    let entry: OpenClawSessionEntry?

    enum CodingKeys: String, CodingKey {
        case ok
        case key
        case sessionId = "sessionId"
        case entry
    }

    struct OpenClawSessionEntry: Decodable {
        let sessionId: String?
        let updatedAt: Int64?

        enum CodingKeys: String, CodingKey {
            case sessionId = "sessionId"
            case updatedAt = "updatedAt"
        }
    }

    func toUnifiedSession() -> UnifiedSession {
        UnifiedSession(
            id: sessionId ?? entry?.sessionId ?? key,
            title: "New Session",
            createdAt: Date(),
            updatedAt: entry?.updatedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? Date(),
            lastMessageAt: nil,
            isPinned: false,
            isArchived: false,
            projectId: nil,
            workspace: "",
            model: "",
            inputTokens: 0,
            outputTokens: 0,
            estimatedCost: 0
        )
    }
}

/// Upload response from POST /v1/upload
private struct OpenClawUploadResponse: Decodable {
    let filename: String?
    let path: String?
    let url: String?
    let size: Int64?

    enum CodingKeys: String, CodingKey {
        case filename
        case path
        case url
        case size
    }
}

/// Models list response from GET /v1/models
private struct OpenClawModelsResponse: Decodable {
    let models: [OpenClawModel]
}

private struct OpenClawModel: Decodable {
    let id: String
    let name: String
    let provider: String
    let alias: String?
    let available: Bool?
    let contextWindow: Int64?
    let reasoning: Bool?
}

/// Skills status response from GET /v1/skills/status
private struct OpenClawSkillsResponse: Decodable {
    let skills: [OpenClawSkill]
}

private struct OpenClawSkill: Decodable {
    let name: String
    let category: String?
    let description: String?
    let enabled: Bool?
}

/// Skill detail response from GET /v1/skills/detail?name=...
private struct OpenClawSkillContentResponse: Decodable {
    let name: String?
    let content: String?
    let files: [String: String]?
}

/// Crons list response from GET /v1/crons
private struct OpenClawCronsResponse: Decodable {
    let jobs: [OpenClawCron]?
    let crons: [OpenClawCron]?
}

private struct OpenClawCron: Decodable {
    let id: String
    let name: String?
    let schedule: String?
    let nextRun: Int64?
    let lastRun: Int64?
    let running: Bool?
    let state: String?
    let payload: OpenClawCronPayload?

    struct OpenClawCronPayload: Decodable {
        let prompt: String?
        let skill: String?
    }
}

/// Cron output response from GET /v1/crons/{id}/output
private struct OpenClawCronOutputResponse: Decodable {
    let output: String
}

/// Files list response from POST /v1/sessions/files/list
private struct OpenClawFilesListResponse: Decodable {
    let entries: [OpenClawFileEntry]
}

private struct OpenClawFileEntry: Decodable {
    let name: String
    let path: String
    let kind: String  // "file" or "directory"
    let size: Int64?
    let updatedAtMs: Int64?

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case kind
        case size
        case updatedAtMs = "updatedAtMs"
    }
}

/// File content response from POST /v1/sessions/files/get
private struct OpenClawFileContentResponse: Decodable {
    let content: String?
    let mimeType: String?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case content
        case mimeType = "mimeType"
        case size
    }
}
