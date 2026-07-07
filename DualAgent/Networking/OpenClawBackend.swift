import Foundation
import Observation

/// The OpenClaw backend implementation (stub for now).
@MainActor
final class OpenClawBackend: Backend {
    // MARK: - Properties
    
    /// The base URL of the OpenClaw gateway (e.g., https://opencv.example.com).
    let baseURL: URL
    
    /// The API client for making requests.
    private let apiClient: APIClient
    
    /// The authentication token (JWT or API key) stored in the Keychain.
    private let keychain = Keychain(service: "com.duckets.DualAgent.openclaw")
    
    /// The current authentication state.
    @Published private(set) var isAuthenticated: Bool = false
    
    // MARK: - Initialization
    
    init(baseURL: URL) {
        self.baseURL = baseURL
        self.apiClient = APIClient(baseURL: baseURL)
        
        // Attempt to load existing token from Keychain.
        if let tokenData = try? keychain.getData("authToken"),
           let token = String(data: tokenData, encoding: .utf8) {
            // For simplicity, we just note that we have a token.
            // In a real app, we would set the token in the APIClient's headers.
            self.isAuthenticated = true
        }
    }
    
    // MARK: - Backend Conformance
    
    var authToken: String? {
        if let tokenData = try? keychain.getData("authToken"),
           let token = String(data: tokenData, encoding: .utf8) {
            return token
        }
        return nil
    }
    
    func login(usernameOrEmail: String, passwordOrAPIKey: String) async throws -> Bool {
        // For OpenClaw, we might use username/email and password or API key.
        // We'll assume the passwordOrAPIKey is either a password or an API key.
        // We'll try to authenticate with the gateway's auth endpoint.
        // Note: The exact endpoint depends on the OpenClaw version and configuration.
        // We'll use a placeholder endpoint: /node/auth/login
        let loginRequest = LoginRequest(username: usernameOrEmail, password: passwordOrAPIKey)
        let response: LoginResponse = try await apiClient.request(
            to: "/node/auth/login",
            method: "POST",
            body: loginRequest
        )
        
        // If successful, we store the token.
        if let token = response.token {
            try keychain.set(token.data(using: .utf8)!, key: "authToken")
            self.isAuthenticated = true
            return true
        } else {
            return false
        }
    }
    
    func logout() {
        try? keychain.remove("authToken")
        self.isAuthenticated = false
    }
    
    func testConnection() async throws -> Bool {
        // Try to ping the gateway.
        let _: PingResponse = try await apiClient.request(to: "/node/ping", method: "GET")
        return true
    }
    
    // MARK: - API Methods (Stubs)
    
    // We'll stub out the methods for now. In a real implementation, we would call the OpenClaw gateway API.
    
    func getSessions() async throws -> [UnifiedSession> {
        // Placeholder: return an empty array.
        return []
    }
    
    func createSession(workspace: String? = nil, model: String? = nil, modelProvider: String? = nil, profile: String? = nil) async throws -> UnifiedSession> {
        // Placeholder: return a dummy session.
        return UnifiedSession(id: UUID().uuidString, title: "New Session", createdAt: Date(), updatedAt: Date())
    }
    
    func sendMessage(sessionID: String, message: String, attachments: [Attachment] = []) async throws -> String> {
        // Placeholder: return a dummy stream ID.
        return "stream-123"
    }
    
    func startListeningToStream(streamID: String, onEvent: @escaping (UnifiedChatEvent) -> Void) async {
        // Placeholder: do nothing.
    }
    
    func stopListeningToStream() {
        // Placeholder: do nothing.
    }
    
    // We'll stub out the rest of the methods as needed.
    func uploadFile(sessionID: String, fileData: Data, filename: String, mimeType: String) async throws -> FileMetadata> {
        fatalError("Not implemented")
    }
    
    func getWorkspaceContents(sessionID: String, path: String) async throws -> [WorkspaceEntry> {
        return []
    }
    
    func readFile(sessionID: String, path: String, raw: Bool) async throws -> FileData {
        return FileData(data: Data(), mimeType: "text/plain", suggestedFilename: "test.txt")
    }
    
    func getSkills() async throws -> [Skill> {
        return []
    }
    
    func getSkillContent(name: String) async throws -> SkillContent> {
        return SkillContent(name: name, markdown: "", files: [:])
    }
    
    func getMemory() async throws -> MemoryData> {
        return MemoryData(notes: [], userProfile: [:])
    }
    
    func getJobs() async throws -> [Job> {
        return []
    }
    
    func getModels() async throws -> [ModelInfo> {
        return []
    }
    
    func getProviders() async throws -> [ProviderInfo> {
        return []
    }
    
    func getProfiles() async throws -> [ProfileInfo> {
        return []
    }
    
    func getReasoningOptions() async throws -> [ReasoningOption> {
        return []
    }
    
    func getSettings() async throws -> ServerSettings {
        return ServerSettings(version: "0.0.0", botName: "Test", extra: [:])
    }
    
    // We need to implement the mutating session methods (pin, archive, delete) for completeness.
    func pinSession(sessionID: String, pinned: Bool) async throws { }
    func archiveSession(sessionID: String, archived: Bool) async throws { }
    func deleteSession(sessionID: String) async throws { }
}

// MARK: - Request and Response Models for OpenClaw API (Placeholders)

struct LoginRequest: Encodable {
    let username: String
    let password: String
}

struct LoginResponse: Decodable {
    let token: String?
}

struct PingResponse: Decodable {
    let status: String
}

// We'll reuse the same UnifiedChatEvent and other models from UnifiedModels.swift.
// Note: We are duplicating some definitions here for the sake of having a self-contained file.
// In a real project, we would share these models.

// However, to avoid duplication, we should import the UnifiedModels.
// But since we are in a separate file, we can't import from the same target without making them public.
// Let's assume we have moved the shared models to a separate framework or made them public.
// For now, we'll leave the duplicates and note that we should refactor.

// We'll define the same models again here for the stub to compile.
// In practice, we would have a shared module.

// We'll skip the duplicate definitions for brevity and assume they are imported.
// But since we cannot import, we'll have to define them again or use a different approach.
// Given the constraints, we'll leave the stub as is and note that the real implementation would use shared models.

// We'll just note that the OpenClawBackend is a stub and needs to be implemented with the actual OpenClaw API.