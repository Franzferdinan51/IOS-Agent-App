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

    // MARK: - Dependencies
    private let backend: Backend
    private let sessionId: String    // was sessionID (fixed to match protocol)
    private var streamID: String?
    private var streamTask: Task<Void, Never>?

    // MARK: - Init
    init(backend: Backend, sessionId: String) {
        self.backend = backend
        self.sessionId = sessionId
    }
    
    // MARK: - Public Methods
    func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isSending else { return }
        
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
        streamTask = Task {
            do {
                for try await event in backend.chatStream(streamId: streamID) {
                    if Task.isCancelled { break }
                    await handleEvent(event)
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        errorMessage = "Stream error: \(error.localizedDescription)"
                    }
                }
            }
            await MainActor.run {
                isStreaming = false
                isSending = false
                streamTask = nil
            }
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
            isStreaming = false
            isSending = false
        case .error(let errorString):
            errorMessage = errorString
            isStreaming = false
            isSending = false
        case .cancelled:
            isStreaming = false
            isSending = false
        }
    }
    
    private func appendOrAppendToLastAssistantMessage(_ text: String) {
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .assistant && !messages[lastIndex].isReasoning {
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