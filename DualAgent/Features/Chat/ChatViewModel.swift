import Foundation
import Observation

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var isConnected = false
    @Published var errorMessage: String? = nil
    @Published var isSending = false
    @Published var messageText = ""
    @Published var attachments: [ChatAttachment] = []    // was [Attachment] (typo - fixed)
    @Published var isStreaming = false

    let session: UnifiedSession?

    var isImportedReadOnlySession: Bool {
        session?.isImportedReadOnlySession == true
    }

    var composerDisabledReason: String? {
        guard let session, session.isImportedReadOnlySession else { return nil }

        let source = (session.sourceLabel ?? session.sourceTag ?? session.sessionSource ?? "session")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = source.lowercased()

        if normalized.contains("telegram") || normalized.contains("discord") || normalized.contains("slack") || normalized.contains("sms") || normalized.contains("imessage") || normalized.contains("whatsapp") {
            return "This \(source) session is owned by its messaging channel and can't be continued from the WebUI."
        }
        if normalized.contains("cron") {
            return "This cron session is historical output and can't be continued from the WebUI."
        }
        if normalized.contains("subagent") {
            return "This subagent session is view-only and can't be continued from the WebUI."
        }
        if session.isCliSession {
            return "This imported CLI/TUI session is currently marked read-only in Hermes and can't be continued from the WebUI."
        }
        return "This session is read-only and can't be continued from the WebUI."
    }

    // MARK: - Dependencies
    private let backend: Backend
    private let sessionId: String    // was sessionID (fixed to match protocol)
    private var streamID: String?
    private var streamTask: Task<Void, Never>?

    // MARK: - Init
    init(backend: Backend, sessionId: String, session: UnifiedSession? = nil) {
        self.backend = backend
        self.sessionId = sessionId
        self.session = session
    }
    
    // MARK: - Public Methods
    func sendMessage() {
        if let disabledReason = composerDisabledReason {
            Haptic.warning()
            errorMessage = disabledReason
            return
        }

        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isSending else {
            Haptic.warning()
            return
        }

        Haptic.send()
        isSending = true
        isStreaming = true
        errorMessage = nil

        // Add user message
        let userMessage = ChatMessage(role: .user, content: messageText, attachments: attachments)
        messages.append(userMessage)
        
        // Clear input
        let tempMessage = messageText
        let tempAttachments = attachments
        messageText = ""
        attachments = []
        
        // Start chat stream
        Task {
            do {
                let streamID = try await backend.startChat(
                    sessionId: sessionId,
                    message: tempMessage,
                    attachments: tempAttachments.isEmpty ? nil : tempAttachments
                )
                self.streamID = streamID

                // Listen to stream
                await listenToStream(streamID: streamID)
            } catch {
                errorMessage = "Failed to send message: \(error.localizedDescription)"
                isSending = false
                isStreaming = false
            }
        }
    }
    
    func stopSending() {
        guard let streamID = streamID, isStreaming else { return }
        
        Task {
            do {
                try await backend.cancelChat(streamId: streamID)
            } catch {
                errorMessage = "Failed to cancel stream: \(error.localizedDescription)"
            }
            isStreaming = false
            isSending = false
            streamTask?.cancel()
            streamTask = nil
        }
    }
    
    func attachFile(_ attachment: ChatAttachment) {
        attachments.append(attachment)
    }
    
    // MARK: - Private Methods
    private func listenToStream(streamID: String) {
        // Cancel any prior in-flight stream task before starting a new one
        // so we don't end up with two consumers writing to `messages` at once.
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in self.backend.chatStream(streamId: streamID) {
                    if Task.isCancelled { break }
                    await self.handleEvent(event)
                }
            } catch is CancellationError {
                // Expected on stop / new message.
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = "Stream error: \(error.localizedDescription)"
                }
            }
            self.isStreaming = false
            self.isSending = false
            self.streamTask = nil
        }
    }
    
    private func handleEvent(_ event: UnifiedChatEvent) {
        switch event {
        case .token(let text):
            appendOrAppendToLastAssistantMessage(text)
        case .toolCall(let toolCall):
            // Show tool call as a special message
            let toolMsg = ChatMessage(role: .assistant, content: "[Tool Call: \(toolCall.name)]", toolCall: toolCall)
            messages.append(toolMsg)
        case .toolResult(let toolResult):
            let resultMsg = ChatMessage(role: .assistant, content: "[Tool Result]", toolResult: toolResult)
            messages.append(resultMsg)
        case .reasoning(let text):
            // Optionally show reasoning in a collapsible section
            let reasoningMsg = ChatMessage(role: .assistant, content: "[Reasoning: \(text)]", isReasoning: true)
            messages.append(reasoningMsg)
        case .streamEnd:
            // Only fire the "I'm done" haptic if the user wasn't the one
            // who stopped the stream (otherwise it would double-buzz).
            if isStreaming {
                Haptic.completion()
            }
            isStreaming = false
            isSending = false
        case .error(let errorString):
            Haptic.error()
            errorMessage = errorString
            isStreaming = false
            isSending = false
        case .cancelled:
            isStreaming = false
            isSending = false
        }
    }
    
    private func appendOrAppendToLastAssistantMessage(_ text: String) {
        guard !messages.isEmpty else {
            messages.append(ChatMessage(role: .assistant, content: text))
            return
        }
        let lastIndex = messages.count - 1
        if messages[lastIndex].role == .assistant && !messages[lastIndex].isReasoning {
            messages[lastIndex].content += text
        } else {
            messages.append(ChatMessage(role: .assistant, content: text))
        }
    }
}

// MARK: - Supporting Models
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole    // UnifiedModels.MessageRole
    var content: String
    let attachments: [ChatAttachment]
    let toolCall: ToolCall?
    let toolResult: ToolResult?
    let isReasoning: Bool
    let timestamp: Date

    init(role: MessageRole, content: String = "", attachments: [ChatAttachment] = [], toolCall: ToolCall? = nil, toolResult: ToolResult? = nil, isReasoning: Bool = false, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.attachments = attachments
        self.toolCall = toolCall
        self.toolResult = toolResult
        self.isReasoning = isReasoning
        self.timestamp = timestamp
    }
}

// Local types removed — use UnifiedModels.MessageRole, ChatAttachment, etc.