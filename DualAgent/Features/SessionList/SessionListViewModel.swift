import Foundation
import Observation
import Combine

@Observable
final class SessionListViewModel {
    // MARK: - Published Properties
    var sessions: [UnifiedSession] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var isShowingNewSessionSheet: Bool = false
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Internal Properties
    let authManager: AuthManager
    
    // MARK: - Initialization
    init(authManager: AuthManager) {
        self.authManager = authManager
        loadSessions()
        setupAuthListener()
    }
    
    // MARK: - Public Methods
        func loadSessions() {
            guard authManager.isAuthenticated && !isLoading else { return }
        
            Task { @MainActor in
                isLoading = true
                errorMessage = nil
            
                do {
                    let backend = authManager.backend
                    let fetchedSessions = try await backend.getSessions()
                    self.sessions = fetchedSessions
                } catch {
                    self.errorMessage = "Failed to load sessions: \(error.localizedDescription)"
                }
            
                isLoading = false
            }
        }
    
        func refresh() {
            loadSessions()
        }
    
        func createSession(workspace: String, model: String, provider: String?, profile: String?) {
            Task { @MainActor in
                isLoading = true
                errorMessage = nil
            
                do {
                    let backend = authManager.backend
                    let newSession = try await backend.createSession(
                        workspace: workspace,
                        model: model,
                        provider: provider,
                        profile: profile
                    )
                
                    // Add the new session to the beginning of the list
                    sessions.insert(newSession, at: 0)
                    isShowingNewSessionSheet = false
                } catch {
                    errorMessage = "Failed to create session: \(error.localizedDescription)"
                }
            
                isLoading = false
            }
        }
    
        func togglePin(for session: UnifiedSession) {
            Task { @MainActor in
                isLoading = true
                errorMessage = nil
            
                do {
                    let backend = authManager.backend
                    let updatedSession = try await backend.updateSession(
                        sessionID: session.id,
                        isPinned: !session.isPinned
                    )
                
                    if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                        sessions[index] = updatedSession
                    }
                } catch {
                    errorMessage = "Failed to toggle pin: \(error.localizedDescription)"
                }
            
                isLoading = false
            }
        }
    
        func toggleArchive(for session: UnifiedSession) {
            Task { @MainActor in
                isLoading = true
                errorMessage = nil
            
                do {
                    let backend = authManager.backend
                    let updatedSession = try await backend.updateSession(
                        sessionID: session.id,
                        isArchived: !session.isArchived
                    )
                
                    if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                        sessions[index] = updatedSession
                    }
                } catch {
                    errorMessage = "Failed to toggle archive: \(error.localizedDescription)"
                }
            
                isLoading = false
            }
        }
    
        func deleteSession(_ session: UnifiedSession) {
            Task { @MainActor in
                isLoading = true
                errorMessage = nil
            
                do {
                    let backend = authManager.backend
                    try await backend.deleteSession(sessionID: session.id)
                
                    sessions.removeAll { $0.id == session.id }
                } catch {
                    errorMessage = "Failed to delete session: \(error.localizedDescription)"
                }
            
                isLoading = false
            }
        }
        func toggleArchive(for session: UnifiedSession) {
            Task { @MainActor in
                isLoading = true
                errorMessage = nil
            
                do {
                    let backend = authManager.backend
                    let updatedSession = try await backend.updateSession(
                        sessionID: session.id,
                        isArchived: !session.isArchived
                    )
                
                    if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                        sessions[index] = updatedSession
                    }
                } catch {
                    errorMessage = "Failed to toggle archive: \(error.localizedDescription)"
                }
            
                isLoading = false
            }
        }
    
        func deleteSession(_ session: UnifiedSession) {
            Task { @MainActor in
                isLoading = true
                errorMessage = nil
            
                do {
                    let backend = authManager.backend
                    try await backend.deleteSession(sessionID: session.id)
                
                    sessions.removeAll { $0.id == session.id }
                } catch {
                    errorMessage = "Failed to delete session: \(error.localizedDescription)"
                }
            
                isLoading = false
            }
        }
    
    // MARK: - Private Methods
    private func setupAuthListener() {
        // Listen for authentication changes
        NotificationCenter.default.publisher(for: .authenticationDidChange)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.authManager.isAuthenticated {
                    self.loadSessions()
                } else {
                    self.sessions.removeAll()
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let authenticationDidChange = Notification.Name("authenticationDidChange")
}