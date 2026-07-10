import Foundation

private enum SessionListError: LocalizedError {
    case missingWorkspace
    case missingModel

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "Hermes did not provide a default workspace. Enter one under Advanced."
        case .missingModel:
            return "Choose a model before creating a thread."
        }
    }
}

@MainActor
final class SessionListViewModel: ObservableObject {
    @Published var sessions: [UnifiedSession] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isShowingNewSessionSheet: Bool = false
    @Published var isAuthenticated: Bool = false

    let authManager: AuthManager

    var backend: Backend { authManager.backend }

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

    func createSession(workspace: String, model: String, profile: String? = nil) async -> UnifiedSession? {
        guard authManager.isAuthenticated else {
            errorMessage = "Connect to Hermes before creating a thread."
            return nil
        }

        let trimmedWorkspace = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProfile = profile?.trimmingCharacters(in: .whitespacesAndNewlines)

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let serverWorkspace = try await authManager.backend.fetchDefaultWorkspace()?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedWorkspace: String
            if !trimmedWorkspace.isEmpty {
                resolvedWorkspace = trimmedWorkspace
            } else if let serverWorkspace, !serverWorkspace.isEmpty {
                resolvedWorkspace = serverWorkspace
            } else {
                throw SessionListError.missingWorkspace
            }

            guard !trimmedModel.isEmpty else { throw SessionListError.missingModel }

            let newSession = try await authManager.backend.createSession(
                workspace: resolvedWorkspace,
                model: trimmedModel,
                profile: trimmedProfile?.isEmpty == true ? nil : trimmedProfile
            )
            sessions.insert(newSession, at: 0)
            isShowingNewSessionSheet = false
            return newSession
        } catch {
            errorMessage = "Failed to create session: \(error.localizedDescription)"
            return nil
        }
    }

    func fetchDefaultWorkspace() async -> String? {
        guard authManager.isAuthenticated else { return nil }
        do {
            return try await authManager.backend.fetchDefaultWorkspace()
        } catch {
            return nil
        }
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
                    isPinned: !s.isPinned,
                    isArchived: s.isArchived,
                    workspace: s.workspace,
                    model: s.model,
                    modelProvider: s.modelProvider
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
                    isPinned: s.isPinned,
                    isArchived: !s.isArchived,
                    workspace: s.workspace,
                    model: s.model,
                    modelProvider: s.modelProvider
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
