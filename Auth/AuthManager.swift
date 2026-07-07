//
//  AuthManager.swift
//  DualAgent
//
//  Created by Hermes Agent on 2026-07-06.
//

import Foundation
import Combine

/// Manages authentication state and credentials for the DualAgent app.
@MainActor
final class AuthManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isLoggedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var userID: String? = nil
    
    // MARK: - Dependencies
    private let backend: any Backend
    private let keychainStore: KeychainStore
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(backend: any Backend, keychainStore: KeychainStore = KeychainStore()) {
        self.backend = backend
        self.keychainStore = keychainStore
        
        // Initialize auth state from keychain
        self.isLoggedIn = keychainStore.isLoggedIn
        self.userID = keychainStore.userID
        
        // Sync with backend auth state
        checkAuthStatus()
    }
    
    // MARK: - Public Methods
    
    /// Logs in the user with username/email and password.
    /// - Parameters:
    ///   - username: The user's username or email
    ///   - password: The user's password
    /// - Returns: A publisher that emits true if login was successful
    func login(username: String, password: String) -> AnyPublisher<Bool, Error> {
        isLoading = true
        errorMessage = nil
        
        return backend.login(credentials: ["username": username, "password": password])
            .handleEvents(receiveCompletion: { [weak self] _ in
                self?.isLoading = false
            }, receiveOutput: { [weak self] success in
                if success {
                    // Store tokens in keychain (in a real app, these would come from the login response)
                    // For now, we'll simulate receiving tokens
                    self?.keychainStore.accessToken = "mock_access_token_\(UUID().uuidString)"
                    self?.keychainStore.refreshToken = "mock_refresh_token_\(UUID().uuidString)"
                    self?.keychainStore.userID = username
                    
                    self?.isLoggedIn = true
                    self?.userID = username
                    self?.errorMessage = nil
                } else {
                    self?.errorMessage = "Invalid username or password"
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Logs out the current user and clears authentication data.
    func logout() {
        isLoading = true
        
        Task {
            do {
                try await backend.logout()
            } catch {
                // Even if logout fails on the server, we still clear local state
                print("Logout failed: \(error)")
            }
            
            await MainActor.run {
                keychainStore.clear()
                isLoggedIn = false
                userID = nil
                isLoading = false
                errorMessage = nil
            }
        }
    }
    
    /// Refreshes the authentication token using the refresh token.
    func refreshToken() -> AnyPublisher<Bool, Error> {
        guard let refreshToken = keychainStore.refreshToken else {
            return Fail(error: NSError(domain: "AuthManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "No refresh token available"]))
                .eraseToAnyPublisher()
        }
        
        isLoading = true
        errorMessage = nil
        
        // In a real implementation, this would call a token refresh endpoint
        // For now, we'll simulate a successful refresh
        return Just(true)
            .delay(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] success in
                if success {
                    // Generate new tokens (in reality, these would come from the server)
                    self?.keychainStore.accessToken = "mock_access_token_\(UUID().uuidString)"
                    // Keep the same refresh token (in a real app, this might rotate)
                }
                self?.isLoading = false
            })
            .mapError { $0 as Error }
            .eraseToAnyPublisher()
    }
    
    /// Checks the current authentication status with the backend.
    func checkAuthStatus() {
        isLoading = true
        
        Task {
            let isAuthenticated = backend.isAuthenticated
            
            await MainActor.run {
                self.isLoggedIn = isAuthenticated
                self.isLoading = false
                
                // If backend says not authenticated but we have tokens, try to refresh
                if !isAuthenticated && keychainStore.isLoggedIn {
                    // Attempt to refresh token
                    Task {
                        let refreshResult = try? await refreshToken()
                        await MainActor.run {
                            self.isLoggedIn = refreshResult ?? false
                            self.isLoading = false
                        }
                    }
                }
            }
        }
    }
    
    /// Gets the current access token for API requests.
    func getAccessToken() -> String? {
        return keychainStore.accessToken
    }
    
    /// Clears any error messages.
    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Preview Helper
#if DEBUG
import SwiftUI

class PreviewBackend: Backend {
    let backendType: BackendType = .hermes
   
    let baseURL: URL = URL(string: "https://example.com")!
    
    var isAuthenticated: Bool: Bool {
        return false
    }
    
    func login(credentials: [String: String]) async throws -> Bool {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000)
        // Simulate successful login
        return true
    }
    
    func logout() async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    func fetchSessions() async throws -> [UnifiedSession] {
        try await Task.sleep(nanoseconds: 500_000_000)
        return []
    }
    
    func createSession(workspace: String, model: String, profile: String?) async throws -> UnifiedSession {
        try await Task.sleep(nanoseconds: 500_000_000)
        return UnifiedSession(id: UUID().uuidString, title: "Test Session", createdAt: Date(), updatedAt: Date(), lastMessageAt: nil, isPinned: false, isArchived: false, projectId: nil, workspace: workspace, model: model, inputTokens: 0, outputTokens: 0, estimatedCost: 0.0)
    }
    
    func deleteSession(sessionId: String) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    func setSessionPinned(sessionId: String, pinned: Bool) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    func setSessionArchived(sessionId: String, archived: Bool) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    func startChat(sessionId: String, message: String, attachments: [ChatAttachment]?) async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        return UUID().uuidString
    }
    
    func steerChat(sessionId: String, text: String) async throws -> Bool {
        try await Task.sleep(nanoseconds: 500_000_000)
        return true
    }
    
    func cancelChat(streamId: String) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    func uploadFile(sessionId: String, fileData: Data, filename: String, mimeType: String) async throws -> UploadResult {
        try await Task.sleep(nanoseconds: 500_000_000)
        return UploadResult(filename: filename, path: "/uploads/\(filename)", mimeType: mimeType, size: fileData.count, isImage: mimeType.hasPrefix("image/"))
    }
    
    func fetchModels() async throws -> [String] {
        try await Task.sleep(nanoseconds: 500_000_000)
        return ["Hermes-3", "OpenClaw"]
    }
    
    func fetchProviders() async throws -> [String] {
        try await Task.sleep(nanoseconds: 500_000_000)
        return ["hermes", "openclaw"]
    }
    
    func fetchReasoning() async throws -> String? {
        try await Task.sleep(nanoseconds: 500_000_000)
        return "medium"
    }
    
    func saveReasoning(effort: String) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    func fetchSkills() async throws -> [SkillSummary] {
        try await Task.sleep(nanoseconds: 500_000_000)
        return []
    }
    
    func fetchSkillContent(name: String) async throws -> SkillContent {
        try await Task.sleep(nanoseconds: 500_000_000)
        return SkillContent(markdown: "# Test Skill", linkedFiles: [:])
    }
    
    func fetchMemory() async throws -> (String, String) {
        try await Task.sleep(nanoseconds: 500_000_000)
        return ("", "")
    }
    
    func fetchCrons() async throws -> [CronJobSummary] {
        try await Task.sleep(nanoseconds: 500_000_000)
        return []
    }
    
    func fetchCronOutput(jobId: String, limit: Int) async throws -> String {
        try await Task.sleep(nanoseconds: 500_000_000)
        return ""
    }
    
    func listWorkspace(sessionId: String, path: String) async throws -> [WorkspaceEntry] {
        try await Task.sleep(nanoseconds: 500_000_000)
        return []
    }
    
    func readFile(sessionId: String, path: String) async throws -> FileResult {
        try await Task.sleep(nanoseconds: 500_000_000)
        return FileResult(content: "", mimeType: "text/plain", size: 0)
    }
    
    func readFileRaw(sessionId: String, path: String) async throws -> RawFileResult {
        try await Task.sleep(nanoseconds: 500_000_000)
        return RawFileResult(data: Data(), mimeType: "text/plain", size: 0)
    }
}

struct AuthManager_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("Auth Manager Preview")
        }
        .environmentObject(AuthManager(backend: PreviewBackend()))
    }
}
#endif