import Foundation

/// Backend implementation for Hermes‑webui.
final class HermesBackend: @preconcurrency Backend {
    /// Shared instance (singleton).
    static let shared = HermesBackend()

    private let apiClient = APIClient.shared
    private let _baseURL: URL
    /// Session token (from `HERMES_DASHBOARD_SESSION_TOKEN` env, or set by
    /// `login(credential:)` when the server is in dashboard-gated mode). When
    /// non-nil, every request carries it as `X-Hermes-Session-Token`.
    private var sessionToken: String?

    private static let hermesURLSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        // Chat runs are returned as finite SSE bodies and can legitimately take
        // well over 20 seconds before Hermes closes the response. A short
        // resource timeout aborts an otherwise healthy assistant run.
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = .shared
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()

    private static func normalizedHermesRequest(_ request: URLRequest, timeout: TimeInterval = 15) -> URLRequest {
        var request = request
        request.timeoutInterval = timeout
        if #available(iOS 14.5, *) {
            request.assumesHTTP3Capable = false
        }
        return request
    }

    /// Initialize with a base URL.
    /// - Parameter baseURL: The base URL of the Hermes‑webui server (e.g., https://hermes.example.com).
    init(baseURL: URL) {
        self._baseURL = baseURL
    }

    /// Default initializer with a placeholder URL.
    init() {
        self._baseURL = URL(string: "https://hermes.local")!
    }

    /// Adds the session token header to the request if one is set.
    private func attachAuth(to request: inout URLRequest) {
        if let token = sessionToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
        }
    }

    // MARK: - Backend Conformance

    var baseURL: URL { _baseURL }

    var backendType: BackendType { .hermes }

    var isAuthenticated: Bool {
        // In a real implementation, we would check if we have a valid cookie or token.
        // For simplicity, we return true if we have any cookies for this domain.
        return !(HTTPCookieStorage.shared.cookies(for: baseURL)?.isEmpty ?? true)
    }
    
    func login(credential: String) async throws -> Bool {
        // Hermes-webui signs in by POSTing a password to /api/auth/login.
        // That endpoint requires `basic_auth.password` (or `basic_auth.password_hash`)
        // to be configured server-side — if it's empty, any password is rejected.
        //
        // Local/desktop mode, however, uses a *session token* the desktop shell
        // mints and injects into the SPA via `HERMES_DASHBOARD_SESSION_TOKEN`.
        // From an outside client (like this app) that token has to be presented
        // as `X-Hermes-Session-Token` on every request, and `/api/auth/login`
        // itself returns 401 because there is no real password set on the
        // server. We detect that case and authenticate via the header instead
        // — the user pastes the same token they'd see in their Hermes env.
        //
        // First, try the password path (the official public contract).
        let url = baseURL.appendingPathComponent("/api/auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // Important: Do NOT set Origin or Referer headers (see HERMES spec).
        let body = ["password": credential]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await Self.hermesURLSession.data(for: Self.normalizedHermesRequest(request))
            guard let http = response as? HTTPURLResponse else {
                throw APIError.network(URLError(.badServerResponse))
            }
            if (200..<300).contains(http.statusCode) {
                _ = try? JSONDecoder().decode(LoginResponse.self, from: data)
                self.sessionToken = nil  // cookie auth, no header needed
                APIClient.shared.customHeaderName = nil
                APIClient.shared.customHeaderValue = nil
                return true
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            if http.statusCode == 404 {
                throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        } catch APIError.http(let status, _) where status == 401 || status == 403 {
            // Password rejected. Probe whether the server is in session-token
            // gated mode by calling /api/auth/status (always public) with the
            // credential as `X-Hermes-Session-Token`. If that returns 200 we
            // treat the credential as a valid session token and persist it.
            // on the shared APIClient so all subsequent requests carry it.
            let probeURL = baseURL.appendingPathComponent("/api/auth/status")
            var probe = URLRequest(url: probeURL)
            probe.httpMethod = "GET"
            probe.setValue(credential, forHTTPHeaderField: "X-Hermes-Session-Token")
            do {
                let (_, resp) = try await Self.hermesURLSession.data(for: Self.normalizedHermesRequest(probe))
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    self.sessionToken = credential
                    APIClient.shared.customHeaderName = "X-Hermes-Session-Token"
                    APIClient.shared.customHeaderValue = credential
                    return true
                }
            } catch {
                // Network unreachable or other error — fall through to false.
            }
            return false
        } catch APIError.http(let status, _) where status == 404 {
            // No auth endpoint = anonymous / auth disabled. Stay "connected".
            return true
        } catch {
            throw error
        }
    }

    /// Hermes-WebUI does not expose a public `/api/version` or `/api/health`
    /// endpoint. Return a best-effort descriptor so the Onboarding form has
    /// something readable; the deeper status probe lives in
    /// `ConnectionState`/`pingSession()` and updates the live pill.
    func fetchServerStatus() async -> String? {
        // The user-facing Hermes-WebUI version isn't a server response;
        // it ships in `_current_webui_version()` of api/config.py and is
        // surfaced through the WebUI's HTML <meta> but not as an API.
        return "Hermes-WebUI at \(baseURL.host ?? "")"
    }

    func logout() async throws {
        let url = baseURL.appendingPathComponent("/api/auth/logout")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // No body needed.
        _ = try await apiClient.request(request, decoding: EmptyResponse.self)
        // Clear cookies for this domain.
        if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    func fetchSessions() async throws -> [UnifiedSession] {
        let url = baseURL.appendingPathComponent("/api/sessions")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response: SessionsResponse = try await apiClient.request(request, decoding: SessionsResponse.self)
        return response.sessions.map { $0.toUnifiedSession() }
    }
    
    func createSession(workspace: String, model: String, profile: String?) async throws -> UnifiedSession {
        let url = baseURL.appendingPathComponent("/api/session/new")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["workspace": workspace, "model": model]
        if let profile = profile {
            body["profile"] = profile
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let response: SessionResponse = try await apiClient.request(request, decoding: SessionResponse.self)
        return response.session.toUnifiedSession()
    }
    
    func deleteSession(sessionId: String) async throws {
        let url = baseURL.appendingPathComponent("/api/session/delete")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["session_id": sessionId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await apiClient.request(request)
    }
    
    func setSessionPinned(sessionId: String, pinned: Bool) async throws {
        let url = baseURL.appendingPathComponent(pinned ? "/api/session/pin" : "/api/session/unpin")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["session_id": sessionId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await apiClient.request(request)
    }
    
    func setSessionArchived(sessionId: String, archived: Bool) async throws {
        let url = baseURL.appendingPathComponent(archived ? "/api/session/archive" : "/api/session/unarchive")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["session_id": sessionId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await apiClient.request(request)
    }
    
    func startChat(sessionId: String, message: String, attachments: [ChatAttachment]?) async throws -> String {
        let url = baseURL.appendingPathComponent("/api/chat/start")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["session_id": sessionId, "message": message]
        if let attachments = attachments, !attachments.isEmpty {
            // For simplicity, we assume attachments are handled via multipart.
            // In a real implementation, we would use URLSession's uploadTask with multipart form data.
            // For now, we'll just pass the filenames (or we could implement multipart separately).
            // This is a placeholder.
            let attachmentDicts = attachments.map { [
                "filename": $0.filename,
                "mime": $0.mimeType,
                "data": base64Encode($0.data) // Not ideal, but for demo.
            ] }
            body["attachments"] = attachmentDicts
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let response: ChatStartResponse = try await apiClient.request(request, decoding: ChatStartResponse.self)
        return response.stream_id
    }
    
    func steerChat(sessionId: String, text: String) async throws -> Bool {
        let url = baseURL.appendingPathComponent("/api/chat/steer")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["session_id": sessionId, "text": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let response: SteerResponse = try await apiClient.request(request, decoding: SteerResponse.self)
        return response.accepted
    }
    
    func cancelChat(streamId: String) async throws {
        let url = baseURL.appendingPathComponent("/api/chat/cancel")
        var request = URLRequest(url: url)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "stream_id", value: streamId)]
        request.url = components?.url
        request.httpMethod = "GET"
        _ = try await apiClient.request(request)
    }

    func chatStream(streamId: String) -> AsyncThrowingStream<UnifiedChatEvent, any Error> {
        // Hermes exposes chat output as a finite SSE response for a run stream.
        // URLSession.AsyncBytes can coalesce this response without yielding lines
        // on iOS simulator, so read the completed body and parse SSE frames
        // deterministically once Hermes closes the stream.
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/chat/stream"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "stream_id", value: streamId)]
        let url = components?.url ?? baseURL

        return AsyncThrowingStream<UnifiedChatEvent, any Error>(bufferingPolicy: .unbounded) { continuation in
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 120
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("no-cache, no-transform", forHTTPHeaderField: "Cache-Control")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            if let token = self.sessionToken, !token.isEmpty {
                request.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
            }

            let producer = Task {
                do {
                    let (body, response) = try await Self.hermesURLSession.data(for: Self.normalizedHermesRequest(request, timeout: 120))
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw ChatStreamError("HTTP \(http.statusCode)")
                    }
                    guard let text = String(data: body, encoding: .utf8) else {
                        throw ChatStreamError("Unable to decode stream body")
                    }
                    print("DUALAGENT_STREAM body_bytes=\(body.count)")

                    var yieldedTerminal = false
                    for (eventType, data) in self.parseHermesSSEFrames(text) {
                        if Task.isCancelled { break }
                        guard let chatEvent = self.decodeHermesStreamEvent(eventType: eventType, data: data) else {
                            print("DUALAGENT_STREAM ignored event=\(eventType ?? "message") data=\(data.prefix(160))")
                            continue
                        }
                        print("DUALAGENT_STREAM event=\(eventType ?? "message") chatEvent=\(chatEvent)")
                        continuation.yield(chatEvent)
                        if eventType == "final_assistant" {
                            continuation.yield(.streamEnd)
                            yieldedTerminal = true
                        } else if case .streamEnd = chatEvent {
                            yieldedTerminal = true
                        } else if case .cancelled = chatEvent {
                            yieldedTerminal = true
                        }
                    }
                    if !yieldedTerminal {
                        continuation.yield(.streamEnd)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                producer.cancel()
            }
        }
    }

    private func parseHermesSSEFrames(_ body: String) -> [(eventType: String?, data: String)] {
        var frames: [(eventType: String?, data: String)] = []
        var eventType: String?
        var dataLines: [String] = []

        func flush() {
            guard !dataLines.isEmpty else {
                eventType = nil
                return
            }
            frames.append((eventType, dataLines.joined(separator: "\n")))
            eventType = nil
            dataLines.removeAll()
        }

        for rawLine in body.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix(":") {
                continue
            } else if line.hasPrefix("event:") {
                eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        flush()
        return frames
    }

    private func decodeHermesStreamEvent(eventType rawEventType: String?, data: String) -> UnifiedChatEvent? {
        let eventType = rawEventType ?? "message"
        let json = decodeJSONObject(data)

        if let legacy = json, let event = UnifiedChatEvent.from(json: legacy) {
            return event
        }

        switch eventType {
        case "token":
            return .token(stringValue(json?["text"]) ?? stringValue(json?["data"]) ?? data)
        case "interim_assistant", "final_assistant", "assistant":
            let text = stringValue(json?["text"]) ?? stringValue(json?["content"]) ?? stringValue(json?["message"])
            guard let text, !text.isEmpty else { return nil }
            return .token(text)
        case "reasoning":
            return .reasoning(stringValue(json?["text"]) ?? stringValue(json?["data"]) ?? data)
        case "tool":
            guard let json else { return nil }
            let name = stringValue(json["name"]) ?? "tool"
            let id = stringValue(json["tid"]) ?? stringValue(json["id"]) ?? stringValue(json["tool_call_id"]) ?? UUID().uuidString
            let rawArgs = json["args"] ?? json["arguments"] ?? [:]
            let args: [String: String]
            if let dict = rawArgs as? [String: Any] {
                args = dict.mapValues { String(describing: $0) }
            } else if let text = rawArgs as? String {
                args = ["raw": text]
            } else {
                args = [:]
            }
            return .toolCall(ToolCall(id: id, name: name, arguments: args))
        case "tool_complete":
            guard let json else { return nil }
            let id = stringValue(json["tid"]) ?? stringValue(json["id"]) ?? stringValue(json["tool_call_id"]) ?? UUID().uuidString
            let output = stringValue(json["output"]) ?? stringValue(json["result"]) ?? stringValue(json["preview"]) ?? ""
            let isError = (json["is_error"] as? Bool) ?? false
            return .toolResult(ToolResult(toolCallId: id, output: output, isError: isError))
        case "done", "stream_end":
            return .streamEnd
        case "cancel":
            return .cancelled
        case "error", "apperror":
            return .error(stringValue(json?["error"]) ?? stringValue(json?["message"]) ?? data)
        default:
            return nil
        }
    }

    private func decodeJSONObject(_ data: String) -> [String: Any]? {
        guard let jsonData = data.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case .some(let value):
            return String(describing: value)
        case nil:
            return nil
        }
    }

    func uploadFile(sessionId: String, fileData: Data, filename: String, mimeType: String) async throws -> UploadResult {
        // Implement multipart upload.
        // For simplicity, we'll use a placeholder.
        // In a real app, you would create a multipart/form-data request.
        // This is a stub.
        return UploadResult(filename: filename, path: "/uploads/\(filename)", size: Int64(fileData.count), mimeType: mimeType)
    }
    
    func fetchModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("/api/models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response: ModelsResponse = try await apiClient.request(request, decoding: ModelsResponse.self)
        return response.models
    }

    func fetchServerModelCatalog() async throws -> ServerModelCatalog {
        let catalogURL = baseURL.appendingPathComponent("/api/models")
        var request = URLRequest(url: catalogURL)
        request.httpMethod = "GET"
        let raw: ModelsResponse = try await apiClient.request(request, decoding: ModelsResponse.self)

        // Group raw model strings under a single "Available Models" group.
        // Each model ID is used as its own display name.
        let options = raw.models.map { ServerModelOption(id: $0, displayName: $0, providerID: nil) }
        let group = ServerModelCatalogGroup(
            id: "available",
            name: "Available Models",
            providerID: nil,
            models: options
        )
        return ServerModelCatalog(groups: [group], defaultModel: raw.defaultModel)
    }

    func fetchProviders() async throws -> [String] {
        let url = baseURL.appendingPathComponent("/api/providers")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response: ProvidersResponse = try await apiClient.request(request, decoding: ProvidersResponse.self)
        return response.providers
    }

    func fetchDefaultWorkspace() async throws -> String? {
        let url = Endpoints.activeProfile(baseURL: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response: ActiveProfileResponse = try await apiClient.request(request, decoding: ActiveProfileResponse.self)
        let trimmed = response.default_workspace?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
    func fetchReasoning() async throws -> String? {
        let url = baseURL.appendingPathComponent("/api/reasoning")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response: ReasoningResponse = try await apiClient.request(request, decoding: ReasoningResponse.self)
        return response.effort
    }
    
    func saveReasoning(effort: String) async throws {
        let url = baseURL.appendingPathComponent("/api/reasoning")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["effort": effort]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await apiClient.request(request, decoding: EmptyResponse.self)
    }
    
    func fetchSkills() async throws -> [SkillSummary] {
        let url = baseURL.appendingPathComponent("/api/skills")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response: SkillsResponse = try await apiClient.request(request, decoding: SkillsResponse.self)
        return response.skills.map { $0.toSkillSummary() }
    }
    
    func fetchSkillContent(name: String) async throws -> SkillContent {
        let url = baseURL.appendingPathComponent("/api/skills/content")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "name", value: name)]
        request.url = components?.url
        let response: SkillContentResponse = try await apiClient.request(request, decoding: SkillContentResponse.self)
        let linkedFiles = response.linked_files?
            .values
            .flatMap { $0 }
            .sorted()
        return SkillContent(content: response.content, linkedFiles: linkedFiles)
    }
    
    func fetchMemory() async throws -> (String, String) {
        let url = baseURL.appendingPathComponent("/api/memory")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response: MemoryResponse = try await apiClient.request(request, decoding: MemoryResponse.self)
        return (response.memory, response.user)
    }
    
    func fetchCrons() async throws -> [CronJobSummary] {
        let url = baseURL.appendingPathComponent("/api/crons")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response: CronsResponse = try await apiClient.request(request, decoding: CronsResponse.self)
        return response.jobs.map { $0.toCronJobSummary() }
    }
    
    func fetchCronOutput(jobId: String, limit: Int) async throws -> String {
        let url = baseURL.appendingPathComponent("/api/crons/output")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "job_id", value: jobId),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        request.url = components?.url
        let response: CronOutputResponse = try await apiClient.request(request, decoding: CronOutputResponse.self)
        return response.output
    }

    func runCronNow(jobId: String) async throws -> String? {
        // Hermes-WebUI does not currently expose a manual cron trigger
        // endpoint. Surface this honestly rather than failing the UI: the
        // cron detail sheet renders the button as disabled with a tooltip
        // pointing here. OpenClaw's RPC supports `cron.run` and implements
        // it on the OpenClaw backend.
        return nil
    }
    
    func listWorkspace(sessionId: String, path: String) async throws -> [WorkspaceEntry] {
        let url = baseURL.appendingPathComponent("/api/list")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "path", value: path)
        ]
        request.url = components?.url
        let response: ListResponse = try await apiClient.request(request, decoding: ListResponse.self)
        return response.entries.map { $0.toWorkspaceEntry() }
    }
    
    func readFile(sessionId: String, path: String) async throws -> FileResult {
        let url = baseURL.appendingPathComponent("/api/file")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "path", value: path)
        ]
        request.url = components?.url
        let response: FileResponse = try await apiClient.request(request, decoding: FileResponse.self)
        return FileResult(content: response.content, mimeType: response.mime_type, size: Int64(response.size))
    }
    
    func readFileRaw(sessionId: String, path: String) async throws -> RawFileResult {
        let url = baseURL.appendingPathComponent("/api/file/raw")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "path", value: path)
        ]
        request.url = components?.url
        let data = try await apiClient.requestData(request)
        // We don't have metadata here; we could make another request to /api/file for metadata.
        // For simplicity, we'll guess mime type from extension.
        let mimeType = mimeTypeForPath(path)
        return RawFileResult(data: data, mimeType: mimeType, size: Int64(data.count))
    }
    
    // MARK: - Helper Types (Decodable responses from Hermes‑webui)

    private struct LoginResponse: Decodable {
        // Hermes API: response is `{ok?, message?, error?}`. All fields are
        // optional; success is signalled by `ok == true` and absence of
        // `error`. Mirrors `hermex/HermesMobile/Models/ServerInfo.swift:LoginResponse`.
        let ok: Bool?
        let message: String?
        let error: String?
    }

    private struct EmptyResponse: Decodable {}

    private struct SessionsResponse: Decodable {
        let sessions: [Session]
    }

    private struct Session: Decodable {
        // Server returns `session_id` (snake_case); the rest of the backend
        // protocol is snake_case too. Without this explicit CodingKeys map
        // Swift looks for an `id` key, which is missing in the JSON, and
        // bails with "The data couldn't be read because it is missing."
        private enum CodingKeys: String, CodingKey {
            case id = "session_id"
            case title
            case created_at
            case updated_at
            case last_message_at
            case pinned
            case archived
            case project_id
            case workspace
            case model
            case input_tokens
            case output_tokens
            case estimated_cost
            case source_tag
            case session_source
            case source_label
            case raw_source
            case is_cli_session
            case read_only
        }

        let id: String
        let title: String
        let created_at: Double
        let updated_at: Double
        let last_message_at: Double?
        let pinned: Bool
        let archived: Bool
        let project_id: String?
        let workspace: String
        let model: String
        // These three are only set on webui-originated sessions; telegram /
        // subagent / cron sessions omit them. Server returns the value as
        // null or as a missing key — both are treated as `nil` so the
        // decoder doesn't bail on the whole list when a single row is
        // shaped differently.
        let input_tokens: Int?
        let output_tokens: Int?
        let estimated_cost: Double?
        let source_tag: String?
        let session_source: String?
        let source_label: String?
        let raw_source: String?
        let is_cli_session: Bool?
        let read_only: Bool?

        func toUnifiedSession() -> UnifiedSession {
            UnifiedSession(
                id: id,
                title: title,
                createdAt: Date(timeIntervalSince1970: created_at),
                updatedAt: Date(timeIntervalSince1970: updated_at),
                lastMessageAt: last_message_at.map { Date(timeIntervalSince1970: $0) },
                isPinned: pinned,
                isArchived: archived,
                projectId: project_id,
                workspace: workspace,
                model: model,
                modelProvider: nil,
                inputTokens: input_tokens ?? 0,
                outputTokens: output_tokens ?? 0,
                estimatedCost: estimated_cost ?? 0.0,
                sourceTag: source_tag,
                sessionSource: session_source,
                sourceLabel: source_label,
                rawSource: raw_source,
                isCliSession: is_cli_session ?? false,
                isReadOnly: read_only ?? false
            )
        }
    }

    private struct SessionResponse: Decodable {
        let session: Session
    }

    private struct ChatStartResponse: Decodable {
        let stream_id: String
    }

    private struct SteerResponse: Decodable {
        let accepted: Bool
    }

    private struct ModelsResponse: Decodable {
        let models: [String]
        let defaultModel: String?

        enum CodingKeys: String, CodingKey {
            case models
            case defaultModel = "default_model"
        }
    }

    private struct ProvidersResponse: Decodable {
        let providers: [String]
    }

    private struct ActiveProfileResponse: Decodable {
        let default_workspace: String?
    }

    private struct ReasoningResponse: Decodable {
        let effort: String
    }

    private struct SkillsResponse: Decodable {
        let skills: [Skill]
    }

    private struct Skill: Decodable {
        let name: String
        let category: String?
        let description: String
        let disabled: Bool?

        func toSkillSummary() -> SkillSummary {
            SkillSummary(
                id: name,
                name: name,
                category: category ?? "",
                description: description,
                tags: disabled == true ? ["disabled"] : []
            )
        }
    }

    private struct SkillContentResponse: Decodable {
        let content: String
        let linked_files: [String: [String]]?
    }

    private struct MemoryResponse: Decodable {
        let memory: String
        let user: String
        let soul: String?
        let project_context: String?
    }

    private struct CronsResponse: Decodable {
        let jobs: [CronJob]
    }

    private struct CronJob: Decodable {
        let id: String
        let name: String
        let schedule: String
        let next_run_at: Double?
        let last_run_at: Double?
        let running: Bool?
        let prompt: String?
        let skill: String?

        func toCronJobSummary() -> CronJobSummary {
            CronJobSummary(
                id: id,
                name: name,
                schedule: schedule,
                nextRun: next_run_at.map { Date(timeIntervalSince1970: $0) },
                lastRun: last_run_at.map { Date(timeIntervalSince1970: $0) },
                isRunning: running ?? false,
                prompt: prompt ?? "",
                skill: skill
            )
        }
    }

    private struct CronOutputResponse: Decodable {
        let output: String
    }

    private struct ListResponse: Decodable {
        let entries: [ListEntry]
    }

    private struct ListEntry: Decodable {
        let name: String
        let path: String
        let is_dir: Bool
        let size: Int?
        let modified: Double?

        func toWorkspaceEntry() -> WorkspaceEntry {
            WorkspaceEntry(
                name: name,
                path: path,
                isDirectory: is_dir,
                size: size.map { Int64($0) },
                modifiedAt: modified.map { Date(timeIntervalSince1970: $0) }
            )
        }
    }

    private struct FileResponse: Decodable {
        let content: String
        let mime_type: String
        let size: Int
    }

    // MARK: - Private Helpers

    private func base64Encode(_ data: Data) -> String {
        data.base64EncodedString()
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
        default: return "application/octet-stream"
        }
    }
}