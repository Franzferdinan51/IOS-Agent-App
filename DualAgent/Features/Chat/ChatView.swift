import SwiftUI

struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    
    init(backend: Backend, sessionID: String) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(backend: backend, sessionID: sessionID))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                List {
                    ForEach(viewModel.messages) { message in
                        MessageView(message: message)
                            .id(message.id)
                    }
                }
                .listStyle(PlainListStyle())
                .onChange(of: viewModel.messages) { _ in
                    // Scroll to the bottom when a new message arrives
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Scroll to bottom on appear
                    if let lastMessage = viewModel.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            
            // Error banner
            if let errorMessage = viewModel.errorMessage {
                VStack {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red)
                }
            }
            
            // Composer
            HStack(spacing: 8) {
                // Attachment button
                Button(action: {
                    // TODO: Implement attachment picker
                }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                
                // Text field
                TextField("Message...", text: $viewModel.messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                
                // Send/Stop button
                Button(action: {
                    if viewModel.isStreaming {
                        viewModel.stopSending()
                    } else {
                        viewModel.sendMessage()
                    }
                }) {
                    if viewModel.isStreaming {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isStreaming)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Message View
struct MessageView: View {
    let message: ChatMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Message header
            HStack {
                Text(message.role == .user ? "You" : "Agent")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Message content
            if message.isReasoning {
                // Reasoning can be shown in a collapsible section
                DisclosureGroup("Reasoning") {
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            } else {
                Text(message.content)
                    .font(.body)
            }
            
            // Tool calls and results
            if let toolCall = message.toolCall {
                ToolCallView(toolCall: toolCall)
            }
            if let toolResult = message.toolResult {
                ToolResultView(toolResult: toolResult)
            }
            
            // Attachments
            if !message.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(message.attachments) { attachment in
                            AttachmentView(attachment: attachment)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(message.role == .user ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - Supporting Views
struct ToolCallView: View {
    let toolCall: ToolCall
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tool Call: \(toolCall.name)")
                .font(.subheadline)
                .fontWeight(.medium)
            Text(toolCall.arguments)
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ToolResultView: View {
    let toolResult: ToolResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tool Result")
                .font(.subheadline)
                .fontWeight(.medium)
            Text(toolResult.output)
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }
}

struct AttachmentView: View {
    let attachment: Attachment
    
    var body: some View {
        VStack {
            if attachment.isImage, let uiImage = UIImage(data: attachment.data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 100, maxHeight: 100)
                    .cornerRadius(8)
            } else {
                // Default attachment view
                Label(attachment.filename, systemImage: "paperclip")
                    .font(.caption)
                    .frame(width: 100, height: 100)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    // Preview data
    let sessionID = "preview-session-id"
    let mockBackend = MockBackend()
    
    return NavigationView {
        ChatView(backend: mockBackend, sessionID: sessionID)
    }
}

// MARK: - Mock Backend for Preview
class MockBackend: Backend {
    var backendType: BackendType { .hermes }
    var baseURL: URL { URL(string: "https://example.com")! }
    var isAuthenticated: Bool { true }

    func login(credentials: [String: String]) async throws -> Bool { true }
    func logout() async throws {}

    func fetchSessions() async throws -> [UnifiedSession] { [] }
    func createSession(workspace: String, model: String, profile: String?) async throws -> UnifiedSession {
        UnifiedSession(id: UUID().uuidString, title: "New Session", createdAt: Date(), updatedAt: Date(), workspace: workspace, model: model, modelProvider: nil)
    }
    func deleteSession(sessionId: String) async throws {}
    func setSessionPinned(sessionId: String, pinned: Bool) async throws {}
    func setSessionArchived(sessionId: String, archived: Bool) async throws {}
    func startChat(sessionId: String, message: String, attachments: [ChatAttachment]?) async throws -> String { "stream-id" }
    func steerChat(sessionId: String, text: String) async throws -> Bool { true }
    func cancelChat(streamId: String) async throws {}
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