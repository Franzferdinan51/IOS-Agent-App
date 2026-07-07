import SwiftUI

struct SessionListView: View {
    @StateObject private var viewModel: SessionListViewModel
    @State private var selectedSession: UnifiedSession?
    
    init(authManager: AuthManager) {
        _viewModel = StateObject(wrappedValue: SessionListViewModel(authManager: authManager))
    }
    // MARK: - Session List View
        var body: some View {
            NavigationStack {
                Group {
                    if viewModel.isLoading {
                        ProgressView()
                    } else if let errorMessage = viewModel.errorMessage {
                        VStack {
                            Text(errorMessage)
                                .foregroundColor(.red)
                            Button("Retry") {
                                viewModel.loadSessions()
                            }
                        }
                    } else if viewModel.sessions.isEmpty {
                        ContentUnavailableView(
                            "No Sessions",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Start a new session to begin chatting.")
                        )
                    } else {
                        List {
                            ForEach(viewModel.sessions) { session in
                                NavigationLink {
                                    ChatView(viewModel: ChatViewModel(authManager: viewModel.authManager, session: session))
                                } label: {
                                    SessionRowView(session: session)
                                }
                            }
                            .onDelete(perform: deleteSession)
                        }
                        .listStyle(.plain)
                        .refreshable {
                            viewModel.refresh()
                        }
                    }
                }
                .navigationTitle("Sessions")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            // Show profile or settings
                        }) {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            viewModel.isShowingNewSessionSheet = true
                        }) {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
                .sheet(isPresented: $viewModel.isShowingNewSessionSheet) {
                    NewSessionView(viewModel: viewModel)
                }
            }
        }
}

// MARK: - Session Row View
private struct SessionRowView: View {
    let session: UnifiedSession
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let lastMessageAt = session.lastMessageAt {
                        Text(lastMessageAt, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Badges for pinned and archived
                    if session.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                    if session.isArchived {
                        Image(systemName: "archivebox.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                // Delete action will be handled in the List's onDelete
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                // Archive toggle will be handled in the List's onDelete or we need to expose it
            } label: {
                Label(session.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
            .tint(.blue)
            
            Button {
                // Pin toggle
            } label: {
                Label(session.isPinned ? "Unpin" : "Pin", systemImage: "pin")
            }
            .tint(.yellow)
        }
    }
}

// MARK: - New Session View
private struct NewSessionView: View {
    @ObservedObject var viewModel: SessionListViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var workspace: String = ""
    @State private var model: String = ""
    @State private var provider: String = ""
    @State private var profile: String = ""
    
    // We'll need to fetch available workspaces, models, etc. from the backend.
    // For simplicity, we'll leave them as text fields for now.
    // In a real app, we would use pickers backed by data from the backend.
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Workspace") {
                    TextField("Workspace (optional)", text: $workspace)
                }
                
                Section("Model") {
                    TextField("Model ID", text: $model)
                }
                
                Section("Provider (optional)") {
                    TextField("Provider ID", text: $provider)
                }
                
                Section("Profile (optional)") {
                    TextField("Profile ID", text: $profile)
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        viewModel.createSession(
                            workspace: workspace.isEmpty ? nil : workspace,
                            model: model.isEmpty ? nil : model,
                            provider: provider.isEmpty ? nil : provider,
                            profile: profile.isEmpty ? nil : profile
                        )
                        dismiss()
                    }
                    .disabled(model.isEmpty) // Model is required
                }
            }
        }
    }
    
    // MARK: - Private Methods
    private func deleteSession(at offsets: IndexSet) {
        offsets.map { viewModel.sessions[$0] }.forEach { session in
            viewModel.deleteSession(session)
        }
    }
}

// MARK: - Preview
struct SessionListView_Previews: PreviewProvider {
    static var previews: some View {
        // For preview, we need to provide a mock AuthManager
        let authManager = AuthManager(backend: PreviewBackend())
        SessionListView(authManager: authManager)
    }
}

// MARK: - Preview Backend (Mock)
class PreviewBackend: Backend {
    var baseURL: URL = URL(string: "https://example.com")!
    var authToken: String? = nil
    
    func login(usernameOrEmail: String, passwordOrAPIKey: String) async throws -> Bool {
        return true
    }
    
    func logout() {}
    
    func testConnection() async throws -> Bool {
        return true
    }
    
    func fetchSessions() async throws -> [UnifiedSession] {
        // Return some mock sessions
        return [
            UnifiedSession(id: "1", title: "Chat with Assistant", createdAt: Date().addingTimeInterval(-3600), updatedAt: Date(), lastMessageAt: Date(), workspace: "default", model: "Hermes-3", modelProvider: nil),
            UnifiedSession(id: "2", title: "Code Review", createdAt: Date().addingTimeInterval(-7200), updatedAt: Date(), lastMessageAt: Date().addingTimeInterval(-1800), workspace: "default", model: "Hermes-3", modelProvider: nil),
        ]
    }
    
    func createSession(workspace: String?, model: String?, provider: String?, profile: String?) async throws -> UnifiedSession {
        // Return a mock session
        return UnifiedSession(id: UUID().uuidString, title: "New Session", createdAt: Date(), updatedAt: Date(), lastMessageAt: Date(), workspace: workspace ?? "default", model: model ?? "Hermes-3", modelProvider: provider)
    }
    
    func fetchSession(sessionID: String, messageLimit: Int) async throws -> UnifiedSession {
        // Return a mock session
        return UnifiedSession(id: sessionID, title: "Sample Session", createdAt: Date(), updatedAt: Date(), lastMessageAt: Date(), workspace: "default", model: "Hermes-3", modelProvider: nil)
    }
    
    func startChat(sessionID: String, message: String, attachments: [Attachment]? = []) async throws -> (streamID: String, initialResponse: String?) {
        return ("stream1", "Hello, how can I help you?")
    }
    
    func chatStream(streamID: String) -> AsyncThrowingStream<UnifiedChatEvent, Error> {
        // This is a simplified implementation for preview
        AsyncThrowingStream { continuation in
            // We don't actually stream in the preview, so we just finish immediately.
            continuation.finish()
        }
    }
    
    func cancelChat(streamID: String) async throws {}
    
    func uploadFile(sessionID: String, fileData: Data, filename: String, mimeType: String) async throws -> FileMetadata {
        // Mock implementation
        return FileMetadata(filename: filename, path: "", mimeType: mimeType, size: fileData.count, isImage: false)
    }
    
    func getWorkspaceContents(sessionID: String, path: String) async throws -> [WorkspaceEntry] {
        return []
    }
    
    func readFile(sessionID: String, path: String, raw: Bool) async throws -> FileData {
        // Mock implementation
        return FileData(data: Data(), mimeType: "text/plain", suggestedFilename: "test.txt")
    }
    
    func getSkills() async throws -> [Skill] {
        return []
    }
    
    func getSkillContent(name: String) async throws -> SkillContent {
        return SkillContent(name: name, markdown: "", files: [:])
    }
    
    func getMemory() async throws -> MemoryData {
        return MemoryData(notes: [], userProfile: [:])
    }
    
    func getModels() async throws -> [ModelInfo] {
        return []
    }
    
    func getProviders() async throws -> [ProviderInfo] {
        return []
    }
    
    func getProfiles() async throws -> [ProfileInfo] {
        return []
    }
    
    func getReasoningOptions() async throws -> [ReasoningOption] {
        return []
    }
    
    func getSettings() async throws -> ServerSettings {
        return ServerSettings(version: "1.0", botName: "Assistant", extra: [:])
    }
    
    func getJobs() async throws -> [Job] {
        return []
    }
}