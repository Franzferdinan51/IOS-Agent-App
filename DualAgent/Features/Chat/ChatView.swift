import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    @State private var voiceInput = ComposerVoiceInputController()
    @Environment(\.brand) private var brand
    @State private var showingFileImporter = false

    init(viewModel: ChatViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    init(backend: Backend, sessionId: String, session: UnifiedSession? = nil) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(backend: backend, sessionId: sessionId, session: session))
    }
    
    var body: some View {
        ZStack {
            BrandBackground(brand: brand)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Theme.BrandPill(
                        brand: brand,
                        title: viewModel.isStreaming ? "Working live" : brand.displayName,
                        symbol: viewModel.isStreaming ? "waveform.path.ecg" : "circle.fill"
                    )
                    Spacer()
                    if viewModel.isStreaming {
                        ProgressView()
                            .tint(brand.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

        ScrollViewReader { proxy in
            List {
                ForEach(viewModel.messages) { message in
                    MessageView(message: message)
                        .id(message.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 12, for: .scrollContent)
            .onChange(of: viewModel.messages) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                if let lastMessage = viewModel.messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.error, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                if let disabledReason = viewModel.composerDisabledReason {
                    Label(disabledReason, systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Neutral.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                if !viewModel.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.attachments) { attachment in
                                Label(attachment.filename, systemImage: attachment.isImage ? "photo" : "doc")
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.leading, 10)
                                    .padding(.vertical, 8)
                                    .background(brand.primary.opacity(0.12), in: Capsule())
                                    .overlay(alignment: .trailing) {
                                        Button {
                                            viewModel.removeAttachment(id: attachment.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(brand.primary)
                                        }
                                        .padding(.trailing, 6)
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 6)
                }

                HStack(spacing: 10) {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(brand.primary)
                    }
                    .disabled(viewModel.isImportedReadOnlySession || viewModel.isStreaming)
                    .accessibilityLabel("Add attachment")

                    // Voice dictation (Hermes-style ComposerVoiceInputController).
                    // Backend-neutral: fills the composer, then the user still hits Send.
                    Button {
                        let draft = viewModel.messageText
                        Task {
                            Haptic.tap()
                            await voiceInput.toggle(currentDraft: draft) { updated in
                                if Thread.isMainThread {
                                    viewModel.messageText = updated
                                } else {
                                    Task { @MainActor in viewModel.messageText = updated }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: voiceInput.isListening ? "waveform.circle.fill" : "mic.circle.fill")
                            .font(.title2)
                            .foregroundStyle(voiceInput.isListening ? Theme.error : brand.secondary)
                            .symbolEffect(.pulse, isActive: voiceInput.isListening)
                    }
                    .disabled(viewModel.isImportedReadOnlySession || viewModel.isStreaming)
                    .accessibilityLabel(voiceInput.isListening ? "Stop dictation" : "Start dictation")

                    TextField("Message the agent", text: $viewModel.messageText, axis: .vertical)
                        .lineLimit(1...6)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(brand.primary.opacity(0.20), lineWidth: 1))
                        .disabled(viewModel.isImportedReadOnlySession)

                    Button {
                        viewModel.isStreaming ? viewModel.stopSending() : viewModel.sendMessage()
                    } label: {
                        Image(systemName: viewModel.isStreaming ? "stop.fill" : "arrow.up")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(
                                viewModel.isStreaming ? AnyShapeStyle(Theme.error) : AnyShapeStyle(brand.gradient),
                                in: Circle()
                            )
                    }
                    .disabled(viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isStreaming)
                    .accessibilityLabel(viewModel.isStreaming ? "Stop response" : "Send message")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle(viewModel.session?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls { importAttachment(from: url) }
            case .failure(let error):
                viewModel.errorMessage = "Couldn't add attachment: \(error.localizedDescription)"
            }
        }
    }

    private func importAttachment(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
            let mimeType = type?.preferredMIMEType ?? "application/octet-stream"
            viewModel.attachFile(ChatAttachment(filename: url.lastPathComponent, mimeType: mimeType, data: data))
        } catch {
            viewModel.errorMessage = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

// MARK: - Message View
struct MessageView: View {
    let message: ChatMessage
    @Environment(\.brand) private var brand
    
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
                ReasoningCardView(text: message.content)
            } else {
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
            }

            // Tool calls and results
            if let toolCall = message.toolCall {
                ToolCallCardView(toolCall: toolCall)
            }
            if let toolResult = message.toolResult {
                ToolResultCardView(toolResult: toolResult)
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(message.role == .user ? brand.primary.opacity(0.18) : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(message.role == .user ? brand.primary.opacity(0.30) : brand.primary.opacity(0.10), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Supporting Views

private struct ToolCardChrome<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let badgeSymbol: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let badgeSymbol {
                    Image(systemName: badgeSymbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                }
            }
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.30), lineWidth: 1)
        )
        .padding(.vertical, 4)
    }
}

/// Collapsible tool-call card. Displays the tool name, a monospace arguments
/// pill row, and a copy affordance. Modeled after Hermex's `ToolCallCardView`
/// with our brand palette.
struct ToolCallCardView: View {
    let toolCall: ToolCall
    @Environment(\.brand) private var brand
    @State private var expanded: Bool = false
    @State private var copied: Bool = false

    var body: some View {
        ToolCardChrome(title: "Tool call", systemImage: "hammer.fill", tint: brand.primary, badgeSymbol: "terminal") {
            VStack(alignment: .leading, spacing: 6) {
                Text(toolCall.name)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(brand.primary)
                    .textSelection(.enabled)

                if !toolCall.arguments.isEmpty {
                    DisclosureGroup(isExpanded: $expanded) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(toolCall.arguments.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(entry.key)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(entry.value)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Label("\(toolCall.arguments.count) argument\(toolCall.arguments.count == 1 ? "" : "s")",
                              systemImage: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        let payload = "→ \(toolCall.name)(\(toolCall.arguments.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")))"
                        UIPasteboard.general.string = payload
                        Haptic.tap()
                        copied = true
                        Task { try? await Task.sleep(nanoseconds: 1_200_000_000); copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy call", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(brand.primary)
                }
            }
        }
    }
}

/// Collapsible tool-result card. Shows a status icon (success/error), the
/// output text in a monospaced, selectable body, and a copy affordance.
struct ToolResultCardView: View {
    let toolResult: ToolResult
    @Environment(\.brand) private var brand
    @State private var copied: Bool = false

    private var tint: Color {
        toolResult.isError ? Theme.error : brand.secondary
    }

    var body: some View {
        ToolCardChrome(
            title: toolResult.isError ? "Tool result · error" : "Tool result",
            systemImage: toolResult.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
            tint: tint
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(toolResult.output.isEmpty ? "<no output>" : toolResult.output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    UIPasteboard.general.string = toolResult.output
                    Haptic.tap()
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_200_000_000); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy output", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint)
            }
        }
    }
}

/// Collapsible reasoning card. Default collapsed so the transcript doesn't
/// push real content down. Mirrors Hermex's `ReasoningBlockView`.
struct ReasoningCardView: View {
    let text: String
    @Environment(\.brand) private var brand
    @State private var expanded: Bool = false

    private var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 120 { return trimmed }
        return String(trimmed.prefix(120)) + "…"
    }

    var body: some View {
        ToolCardChrome(title: "Reasoning", systemImage: "brain.head.profile", tint: brand.secondary, badgeSymbol: nil) {
            VStack(alignment: .leading, spacing: 8) {
                Text(expanded ? text : preview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if text.count > 120 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                        Haptic.tap()
                    } label: {
                        Label(expanded ? "Collapse" : "Show full reasoning",
                              systemImage: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(brand.primary)
                }
            }
        }
    }
}

struct AttachmentView: View {
    let attachment: ChatAttachment
    
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
    let mockBackend = MockBackend()
    return NavigationStack {
        ChatView(
            viewModel: ChatViewModel(
                backend: mockBackend,
                sessionId: "preview-session-id"
            )
        )
    }
}

// MARK: - Mock Backend for Preview
class MockBackend: @preconcurrency Backend {
    var backendType: BackendType { .hermes }
    var baseURL: URL { URL(string: "https://example.com")! }
    var isAuthenticated: Bool { true }

    func login(credential: String) async throws -> Bool { true }
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
    func chatStream(streamId: String) -> AsyncThrowingStream<UnifiedChatEvent, any Error> {
        AsyncThrowingStream { continuation in
            // Mock: yield a single token + stream end, then finish
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
    func fetchDefaultWorkspace() async throws -> String? { nil }
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