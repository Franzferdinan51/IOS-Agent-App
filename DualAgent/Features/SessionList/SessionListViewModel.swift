import Foundation

@MainActor
final class SessionListViewModel: ObservableObject {
    @Published var sessions: [UnifiedSession] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isShowingNewSessionSheet: Bool = false
    @Published var isAuthenticated: Bool = false

    let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
        self.isAuthenticated = authManager.isAuthenticated
        loadSessions()
    }

    func loadSessions() {
        guard authManager.isAuthenticated, !isLoading else { return }
        Task { @MainActor in
            isLoading = true
            errorMessage = nil
            do {
                let fetched = try await authManager.backend.fetchSessions()
                self.sessions = fetched
            } catch {
                self.errorMessage = "Failed to load sessions: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    func refresh() async {
        guard authManager.isAuthenticated else { return }
        do {
            let fetched = try await authManager.backend.fetchSessions()
            self.sessions = fetched
        } catch {
            self.errorMessage = "Refresh failed: \(error.localizedDescription)"
        }
    }

    func createSession(workspace: String, model: String, profile: String? = nil) async {
        guard authManager.isAuthenticated else { return }
        isLoading = true
        errorMessage = nil
        do {
            let newSession = try await authManager.backend.createSession(
                workspace: workspace,
                model: model,
                profile: profile
            )
            sessions.insert(newSession, at: 0)
            isShowingNewSessionSheet = false
        } catch {
            errorMessage = "Failed to create session: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func togglePin(for session: UnifiedSession) async {
        guard authManager.isAuthenticated else { return }
        do {
            try await authManager.backend.setSessionPinned(
                sessionId: session.id,
                pinned: !session.isPinned
            )
            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                var s = sessions[idx]
                s = UnifiedSession(
                    id: s.id,
                    title: s.title,
                    createdAt: s.createdAt,
                    updatedAt: Date(),
                    workspace: s.workspace,
                    model: s.model,
                    modelProvider: s.modelProvider,
                    pinned: !s.isPinned,
                    archived: s.isArchived
                )
                sessions[idx] = s
            }
        } catch {
            errorMessage = "Failed to toggle pin: \(error.localizedDescription)"
        }
    }

    func toggleArchive(for session: UnifiedSession) async {
        guard authManager.isAuthenticated else { return }
        do {
            try await authManager.backend.setSessionArchived(
                sessionId: session.id,
                archived: !session.isArchived
            )
            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                var s = sessions[idx]
                s = UnifiedSession(
                    id: s.id,
                    title: s.title,
                    createdAt: s.createdAt,
                    updatedAt: Date(),
                    workspace: s.workspace,
                    model: s.model,
                    modelProvider: s.modelProvider,
                    pinned: s.isPinned,
                    archived: !s.isArchived
                )
                sessions[idx] = s
            }
        } catch {
            errorMessage = "Failed to toggle archive: \(error.localizedDescription)"
        }
    }

    func deleteSession(_ session: UnifiedSession) async {
        guard authManager.isAuthenticated else { return }
        do {
            try await authManager.backend.deleteSession(sessionId: session.id)
            sessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
    }
}
