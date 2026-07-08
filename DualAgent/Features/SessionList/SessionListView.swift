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
                                        sessionId: session.id,
                                        session: session
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
                                    Task { await viewModel.togglePin(for: session) }
                                } label: {
                                    Label(session.isPinned ? "Unpin" : "Pin", systemImage: "pin")
                                }
                                .tint(.yellow)
                                Button {
                                    Task { await viewModel.toggleArchive(for: session) }
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
                    if session.isImportedReadOnlySession {
                        Label(session.sourceLabel ?? "Imported", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if let sourceLabel = session.sourceLabel, !sourceLabel.isEmpty, sourceLabel != "Web UI" {
                        Label(sourceLabel, systemImage: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var workspace: String = NSHomeDirectory()
    @State private var model: String = ""
    @State private var profile: String = ""
    @State private var showAdvanced = false

    private var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedWorkspace: String {
        let value = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? NSHomeDirectory() : value
    }

    private var trimmedProfile: String? {
        let value = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start a new thread")
                            .font(.headline)
                        Text("Uses your saved default model unless you change it here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Model") {
                    TextField("Model ID", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !appSettings.defaultModel.isEmpty {
                        Label("Saved default: \(appSettings.defaultModel)", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        TextField("Workspace", text: $workspace)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("Profile ID", text: $profile)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            }
            .navigationTitle("New Thread")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isLoading ? "Creating…" : "Create") {
                        Task {
                            let created = await viewModel.createSession(
                                workspace: trimmedWorkspace,
                                model: trimmedModel,
                                profile: trimmedProfile
                            )
                            if created != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(trimmedModel.isEmpty || viewModel.isLoading)
                }
            }
            .onAppear {
                if model.isEmpty {
                    model = appSettings.defaultModel
                }
                if workspace.isEmpty {
                    workspace = NSHomeDirectory()
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
final class PreviewBackend: @preconcurrency Backend {
    var backendType: BackendType { .hermes }
    var baseURL: URL { URL(string: "https://example.com")! }
    var isAuthenticated: Bool { true }

    func login(credential: String) async throws -> Bool { true }
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
    func chatStream(streamId: String) -> AsyncThrowingStream<UnifiedChatEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.token("Hello from preview!"))
            continuation.yield(.streamEnd)
            continuation.finish()
        }
    }
    func uploadFile(sessionId: String, fileData: Data, filename: String, mimeType: String) async throws -> UploadResult {
        UploadResult(filename: filename, path: "/uploads/\(filename)", size: Int64(fileData.count), mimeType: mimeType)
    }
    func fetchModels() async throws -> [String] { [] }
    func fetchProviders() async throws -> [String] { [] }
    func fetchReasoning() async throws -> String? { "medium" }
    func saveReasoning(effort: String) async throws {}
    func fetchSkills() async throws -> [SkillSummary] { [] }
    func fetchSkillContent(name: String) async throws -> SkillContent {
        SkillContent(content: "# \(name)\n\nSkill content here.")
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
