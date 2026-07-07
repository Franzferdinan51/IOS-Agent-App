import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [UnifiedMessage] = []
    @Published var isStreaming: Bool = false
    @Published var isSending: Bool = false
    @Published var errorMessage: String?
    @Published var inputText: String = ""
    @Published var attachments: [ChatAttachment] = []
    
    // MARK: - Private Properties
    private var streamTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let sessionId: String
    private let authManager: AuthManager
    
    // MARK: - Initialization
    init(sessionId: String, authManager: AuthManager) {
        self.sessionId = sessionId
        self.authManager = authManager
        loadMessages()
    }
    
    // MARK: - Public Methods
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isSending,
              !isStreaming else { return }
        
        let messageText = inputText
        inputText = ""
        isSending = true
        
        Task { @MainActor in
            do {
                let backend = authManager.backend
                let streamId = try await backend.startChat(
                    sessionId: sessionId,
                    message: messageText,
                    attachments: attachments.isEmpty ? nil : attachments
                )
                
                // Add user message immediately
                let userMessage = UnifiedMessage(
                    id: UUID().uuidString,
                    role: .user,
                    content: messageText,
                    createdAt: Date()
                )
                messages.append(userMessage)
                
                // Start streaming response
                await startStreaming(streamId: streamId)
                
                isSending = false
                attachments.removeAll()
            } catch {
                errorMessage = "Failed to send message: \(error.localizedDescription)"
                isSending = false
            }
        }
    }
    
    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
    
    func retryLastMessage() {
        guard let lastMessage = messages.last(where: { $0.role == .user }) else { return }
        
        inputText = lastMessage.content
        sendMessage()
    }
    
    func addAttachment(_ attachment: ChatAttachment) {
        attachments.append(attachment)
    }
    
    func removeAttachment(at index: Int) {
        guard index >= 0 && index < attachments.count else { return }
        attachments.remove(at: index)
    }
    
    // MARK: - Private Methods
    private func loadMessages() {
        Task { @MainActor in
            do {
                let backend = authManager.backend
                let sessionMessages = try await backend.getMessages(for: sessionId)
                self.messages = sessionMessages
            } catch {
                errorMessage = "Failed to load messages: \(error.localizedDescription)"
            }
        }
    }
    
    private func startStreaming(streamId: String) async {
        isStreaming = true
        errorMessage = nil
        
        streamTask = Task { @MainActor in
            do {
                let backend = authManager.backend
                for try await event in backend.streamChat(streamId: streamId) {
                    // Check if task was cancelled
                    if Task.isCancelled { break }
                    
                    switch event {
                    case .token(let text):
                        // Append token to last assistant message or create new one
                        if let lastIndex = messages.lastIndex(where: { $0.role == .assistant }),
                           case .assistant = messages[lastIndex].role {
                            // Update existing message
                            var updatedMessage = messages[lastIndex]
                            updatedMessage.content += text
                            messages[lastIndex] = updatedMessage
                        } else {
                            // Create new assistant message
                            let assistantMessage = UnifiedMessage(
                                id: UUID().uuidString,
                                role: .assistant,
                                content: text,
                                createdAt: Date()
                            )
                            messages.append(assistantMessage)
                        }
                        
                    case .toolCall(let toolCall):
                        // Add tool call message
                        let toolMessage = UnifiedMessage(
                            id: UUID().uuidString,
                            role: .assistant,
                            content: "",
                            createdAt: Date(),
                            toolCall: toolCall
                        )
                        messages.append(toolMessage)
                        
                    case .toolResult(let result):
                        // Update last tool call with result
                        if let lastIndex = messages.lastIndex(where: { $0.role == .assistant && $0.toolCall != nil }),
                           case .assistant = messages[lastIndex].role {
                            var updatedMessage = messages[lastIndex]
                            updatedMessage.toolCallResult = result
                            messages[lastIndex] = updatedMessage
                        }
                        
                    case .reasoning(let text):
                        // Add reasoning message
                        let reasoningMessage = UnifiedMessage(
                            id: UUID().uuidString,
                            role: .assistant,
                            content: "",
                            createdAt: Date(),
                            reasoning: text
                        )
                        messages.append(reasoningMessage)
                        
                    case .streamEnd:
                        // Stream ended
                        isStreaming = false
                        break
                        
                    case .error(let errorMessage):
                        self.errorMessage = errorMessage
                        isStreaming = false
                        break
                        
                    case .cancelled:
                        isStreaming = false
                        break
                    }
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Stream error: \(error.localizedDescription)"
                }
                isStreaming = false
            }
            
            streamTask = nil
        }
    }
    
    deinit {
        streamTask?.cancel()
    }
}