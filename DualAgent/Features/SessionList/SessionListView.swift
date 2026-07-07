import SwiftUI

struct SessionListView: View {
    @StateObject private var viewModel: SessionListViewModel
    @State private var selectedSession: UnifiedSession?

    init(authManager: AuthManager) {
        _viewModel = StateObject(wrappedValue: SessionListViewModel(authManager: authManager))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
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
                                ChatView(
                                    viewModel: ChatViewModel(
                                        backend: viewModel.authManager.backend,
                                        sessionId: session.id
                                    )
                                )
                            } label: {
                                SessionRowView(session: session)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteSession(session) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    Task { await viewModel.togglePin(session) }
                                } label: {
                                    Label(session.isPinned ? "Unpin" : "Pin", systemImage: "pin")
                                }
                                .tint(.yellow)
                                Button {
                                    Task { await viewModel.toggleArchive(session) }
                                } label: {
                                    Label(session.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.refresh()
                    }
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.isShowingNewSessionSheet = true
                    } label: {
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
    }
}

// MARK: - New Session View
private struct NewSessionView: View {
    @ObservedObject var viewModel: SessionListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var workspace: String = ""
    @State private var model: String = ""
    @State private var profile: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Workspace") {
                    TextField("Workspace (optional)", text: $workspace)
                }
                Section("Model") {
                    TextField("Model ID", text: $model)
                }
                Section("Profile (optional)") {
                    TextField("Profile ID", text: $profile)
                }
            }
            .navigationTitle("New Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await viewModel.createSession(
                                workspace: workspace.isEmpty ? "default" : workspace,
                                model: model.isEmpty ? "Hermes-3" : model,
                                profile: profile.isEmpty ? nil : profile
                            )
                            dismiss()
                        }
                    }
                    .disabled(model.isEmpty && true) // allow default
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    let authManager = AuthManager(backend: PreviewBackend())
    return SessionListView(authManager: authManager)
}

// MARK: - Preview Backend
final class PreviewBackend: Backend {
    var backendType: BackendType { .hermes }
    var baseURL: URL { URL(string: "https://example.com")! }
    var isAuthenticated: Bool { true }

    func login(usernameOrEmail: String, passwordOrAPIKey: String) async throws -> Bool { true }
    func logout() async throws {}
    func fetchSessions() async throws -> [UnifiedSession] {
        [
            UnifiedSession(id: "1", title: "Chat with Assistant", createdAt: Date().addingTimeInterval(-3600), updatedAt: Date(), lastMessageAt: Date(), workspace: "default", model: "Hermes-3", modelProvider: nil),
            UnifiedSession(id: "2", title: "Code Review", createdAt: Date().addingTimeInterval(-7200), updatedAt: Date(), lastMessageAt: Date().addingTimeInterval(-1800), workspace: "default", model: "Hermes-3", modelProvider: nil)
        ]
    }
    func createSession(workspace: String, model: String, profile: String?) async throws -> UnifiedSession {
        UnifiedSession(id: UUID().uuidString, title: "New Session", createdAt: Date(), updatedAt: Date(), workspace: workspace, model: model, modelProvider: nil)
    }
    func deleteSession(sessionId: String) async throws {}
    func setSessionPinned(sessionId: String, pinned: Bool) async throws {}
    func setSessionArchived(sessionId: String, archived: Bool) async throws {}
    func startChat(sessionId: String, message: String, attachments: [ChatAttachment]?) async throws -> String { "stream-id" }
    func steerChat(sessionId: String, text: String) async throws -> Bool { true }
    func cancelChat(streamId: String) async throws {}
    func chatStream(streamId: String) -> AsyncThrowingStream<UnifiedChatEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.token("Hello from preview!"))
            continuation.yield(.streamEnd)
            continuation.finish()
        }
    }
    func uploadFile(sessionId: String, fileData: Data, filename: String, mimeType: String) async throws -> UploadResult {
        UploadResult(filename: filename, path: "/uploads/\(filename)", mimeType: mimeType, size: fileData.count, isImage: mimeType.hasPrefix("image/"))
    }
    func fetchModels() async throws -> [String] { [] }
    func fetchProviders() async throws -> [String] { [] }
    func fetchReasoning() async throws -> String? { "medium" }
    func saveReasoning(effort: String) async throws {}
    func fetchSkills() async throws -> [SkillSummary] { [] }
    func fetchSkillContent(name: String) async throws -> SkillContent {
        SkillContent(markdown: "# \(name)\n\nSkill content here.", linkedFiles: [:])
    }
    func fetchMemory() async throws -> (String, String) { ("", "") }
    func fetchCrons() async throws -> [CronJobSummary] { [] }
    func fetchCronOutput(jobId: String, limit: Int) async throws -> String { "" }
    func listWorkspace(sessionId: String, path: String) async throws -> [WorkspaceEntry] { [] }
    func readFile(sessionId: String, path: String) async throws -> FileResult {
        FileResult(content: "", mimeType: "text/plain", size: 0)
    }
    func readFileRaw(sessionId: String, path: String) async throws -> RawFileResult {
        RawFileResult(data: Data(), mimeType: "application/octet-stream", size: 0)
    }
}
