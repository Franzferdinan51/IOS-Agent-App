import Foundation
import Observation
import Combine

@Observable
final class SessionListViewModel {
    // MARK: - Dependencies
    private let authManager: AuthManager
    
    // MARK: - Published Properties
    private(set) var sessions: [UnifiedSession] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var isAuthenticated: Bool = false
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    init(authManager: AuthManager) {
        self.authManager = authManager
        self.isAuthenticated = authManager.isAuthenticated
        
        // Subscribe to auth manager changes
        authManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isAuthenticated = self?.authManager.isAuthenticated ?? false
                if self?.authManager.isAuthenticated == true {
                    Task { await self?.loadSessions() }
                } else {
                    self?.sessions = []
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    func loadSessions() {
        guard authManager.isAuthenticated else {
            sessions = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let fetchedSessions = try await authManager.backend.getSessions()
                await MainActor.run {
                    self.sessions = fetchedSessions
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    func refresh() {
        Task { await loadSessions() }
    }
    
    func createSession(workspace: String? = nil, model: String? = nil, modelProvider: String? = nil, profile: String? = nil) async throws -> UnifiedSession {
        return try await authManager.backend.createSession(
            workspace: workspace,
            model: model,
            modelProvider: modelProvider,
            profile: profile
        )
    }
    
    func deleteSession(_ session: UnifiedSession) async throws {
        // TODO: Implement delete session in backend
        // For now, we'll just remove from local array and rely on backend to sync
        await MainActor.run {
            sessions.removeAll { $0.id == session.id }
        }
    }
    
    func togglePin(_ session: UnifiedSession) {
        // TODO: Implement pinning in backend
        // For now, we'll just toggle locally
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            // Since UnifiedSession doesn't have a pinned property, we'll need to extend it
            // For now, we'll just note that we need to implement this in the backend
            print("Toggle pin for session: \(session.title)")
        }
    }
    
    func toggleArchive(_ session: UnifiedSession) {
        // TODO: Implement archiving in backend
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            print("Toggle archive for session: \(session.title)")
        }
    }
}