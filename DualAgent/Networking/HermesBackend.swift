import Foundation

/// Backend implementation for Hermes‑webui.
final class HermesBackend: @preconcurrency Backend {
    /// Shared instance (singleton).
    static let shared = HermesBackend()

    private let apiClient = APIClient.shared
    private let _baseURL: URL

    /// Initialize with a base URL.
    /// - Parameter baseURL: The base URL of the Hermes‑webui server (e.g., https://hermes.example.com).
    init(baseURL: URL) {
        self._baseURL = baseURL
    }

    /// Default initializer with a placeholder URL.
    init() {
        self._baseURL = URL(string: "https://hermes.local")!
    }

    // MARK: - Backend Conformance

    var baseURL: URL { _baseURL }

    var backendType: BackendType { .hermes }

    var isAuthenticated: Bool {
        // In a real implementation, we would check if we have a valid cookie or token.
        // For simplicity, we return true if we have any cookies for this domain.
        return !(HTTPCookieStorage.shared.cookies(for: baseURL)?.isEmpty ?? true)
    }
    
    func login(usernameOrEmail: String, passwordOrAPIKey: String) async throws -> Bool {
        let url = baseURL.appendingPathComponent("/api/auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // Important: Do NOT set Origin or Referer headers (see HERMES spec).
        let body = ["password": passwordOrAPIKey]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let response: LoginResponse = try await apiClient.request(request, decoding: LoginResponse.self)
        // The login endpoint sets a cookie in the HTTPCookieStorage via URLSession's default storage.
        // We can check if we got a session cookie.
        let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        let hasSessionCookie = cookies.contains { $0.name == "session" }
        return hasSessionCookie
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
        // Hermes streams chat via Server-Sent Events on /api/chat/stream
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/chat/stream"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "stream_id", value: streamId)]
        let url = components?.url ?? baseURL
        return AsyncThrowingStream<UnifiedChatEvent, any Error> { continuation in
            let sse = SSEClient()
            Task {
                for await result in sse.events(for: url) {
                    switch result {
                    case .success(let event):
                        if let dataStr = event.data,
                           let jsonData = dataStr.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                           let chatEvent = UnifiedChatEvent.from(json: json) {
                            continuation.yield(chatEvent)
                        }
                    case .failure(let error):
                        continuation.finish(throwing: ChatStreamError(error.localizedDescription))
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in sse.stop() }
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
    
    func fetchProviders() async throws -> [String] {
        let url = baseURL.appendingPathComponent("/api/providers")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response: ProvidersResponse = try await apiClient.request(request, decoding: ProvidersResponse.self)
        return response.providers
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
        return SkillContent(content: response.content, linkedFiles: Array(response.files.keys))
    }
    
    func fetchMemory() async throws -> (String, String) {
        let url = baseURL.appendingPathComponent("/api/memory")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response: MemoryResponse = try await apiClient.request(request, decoding: MemoryResponse.self)
        return (response.notes, response.user_profile)
    }
    
    func fetchCrons() async throws -> [CronJobSummary] {
        let url = baseURL.appendingPathComponent("/api/crons")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response: CronsResponse = try await apiClient.request(request, decoding: CronsResponse.self)
        return response.crons.map { $0.toCronJobSummary() }
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
        let success: Bool
    }

    private struct EmptyResponse: Decodable {}

    private struct SessionsResponse: Decodable {
        let sessions: [Session]
    }

    private struct Session: Decodable {
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
        let input_tokens: Int
        let output_tokens: Int
        let estimated_cost: Double

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
                inputTokens: input_tokens,
                outputTokens: output_tokens,
                estimatedCost: estimated_cost
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
    }

    private struct ProvidersResponse: Decodable {
        let providers: [String]
    }

    private struct ReasoningResponse: Decodable {
        let effort: String
    }

    private struct SkillsResponse: Decodable {
        let skills: [Skill]
    }

    private struct Skill: Decodable {
        let id: String
        let name: String
        let category: String
        let description: String

        func toSkillSummary() -> SkillSummary {
            SkillSummary(id: id, name: name, category: category, description: description)
        }
    }

    private struct SkillContentResponse: Decodable {
        let content: String
        let files: [String: String]
    }

    private struct MemoryResponse: Decodable {
        let notes: String
        let user_profile: String
    }

    private struct CronsResponse: Decodable {
        let crons: [CronJob]
    }

    private struct CronJob: Decodable {
        let id: String
        let name: String
        let schedule: String
        let next_run: Double?
        let last_run: Double?
        let running: Bool
        let prompt: String
        let skill: String?

        func toCronJobSummary() -> CronJobSummary {
            CronJobSummary(
                id: id,
                name: name,
                schedule: schedule,
                nextRun: next_run.map { Date(timeIntervalSince1970: $0) },
                lastRun: last_run.map { Date(timeIntervalSince1970: $0) },
                isRunning: running,
                prompt: prompt,
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