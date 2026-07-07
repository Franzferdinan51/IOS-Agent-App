import Foundation

/// Backend implementation for OpenClaw Gateway.
/// This is a stub implementation; actual endpoints need to be mapped from the OpenClaw gateway API.
final class OpenClawBackend: Backend {
    /// Shared instance (singleton).
    static let shared = OpenClawBackend()
    
    private let apiClient = APIClient.shared
    private let baseURL: URL
    
    /// Initialize with a base URL.
    /// - Parameter baseURL: The base URL of the OpenClaw gateway (e.g., https://gateway.example.com).
    init(baseURL: URL) {
        self.baseURL = baseURL
    }
    
    // MARK: - Backend Conformance
    
    var baseURL: URL { return self.baseURL }
    
    var isAuthenticated: Bool {
        // Check for token in Keychain.
        // For now, return false.
        return false
    }
    
    func login(credentials: [String: String]) async throws -> Bool {
        // Expect credentials to contain either "password" or "apiKey".
        // For OpenClaw, authentication might be via a token or API key.
        // This is a placeholder.
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func logout() async throws {
        // Clear any stored credentials.
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func fetchSessions() async throws -> [UnifiedSession> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func createSession(workspace: String, model: String, profile: String?) async throws -> UnifiedSession> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func deleteSession(sessionId: String) async throws {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func setSessionPinned(sessionId: String, pinned: Bool) async throws {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func setSessionArchived(sessionId: String, archived: Bool) async throws {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func startChat(sessionId: String, message: String, attachments: [ChatAttachment]?) async throws -> String> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func steerChat(sessionId: String, text: String) async throws -> Bool> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func cancelChat(streamId: String) async throws {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func uploadFile(sessionId: String, fileData: Data, filename: String, mimeType: String) async throws -> UploadResult> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func fetchModels() async throws -> [String]> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func fetchProviders() async throws -> [String]> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func fetchReasoning() async throws -> String?> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func saveReasoning(effort: String) async throws {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func fetchSkills() async throws -> [SkillSummary]> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func fetchSkillContent(name: String) async throws -> SkillContent> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func fetchMemory() async throws -> (String, String)> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func fetchCrons() async throws -> [CronJobSummary]> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func fetchCronOutput(jobId: String, limit: Int) async throws -> String> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func listWorkspace(sessionId: String, path: String) async throws -> [WorkspaceEntry]> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func readFile(sessionId: String, path: String) throws -> FileResult> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
    
    func readFileRaw(sessionId: String, path: String) throws -> RawFileResult> {
        throw NSError(domain: "OpenClawBackend", code: 501, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
    }
}

/// An error indicating that a method is not implemented.
enum NotImplementedError: Error {
    case notImplemented(String)
}