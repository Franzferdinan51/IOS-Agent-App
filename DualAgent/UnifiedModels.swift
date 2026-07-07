import Foundation

/// A unified session model that can represent a session from either Hermes or OpenClaw.
struct UnifiedSession: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let lastMessageAt: Date?
    let model: String?
    let modelProvider: String?
    let workspace: String?
    /// Optional: the raw backend-specific session object (for advanced usage).
    let hermesSession: Any? // In practice, we'd use a protocol or enum, but for simplicity we use Any.
    let openClawSession: Any?
    
    init(id: String, title: String, createdAt: Date, updatedAt: Date, lastMessageAt: Date? = nil,
         model: String? = nil, modelProvider: String? = nil, workspace: String? = nil,
         hermesSession: Any? = nil, openClawSession: Any? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessageAt = lastMessageAt
        self.model = model
        self.modelProvider = modelProvider
        self.workspace = workspace
        self.hermesSession = hermesSession
        self.openClawSession = openClawSession
    }
}

/// A unified message model.
struct UnifiedMessage: Identifiable, Codable, Equatable {
    let id: String
    let sessionID: String
    let role: MessageRole // .user or .assistant
    let content: String
    let createdAt: Date
    /// Optional: tool calls associated with this message (for assistant messages).
    let toolCalls: [ToolCall]?
    /// Optional: reasoning token usage, etc.
    let usage: UsageInfo?
    
    init(id: String, sessionID: String, role: MessageRole, content: String, createdAt: Date,
         toolCalls: [ToolCall]? = nil, usage: UsageInfo? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.toolCalls = toolCalls
        self.usage = usage
    }
}

enum MessageRole: String, Codable, Equatable {
    case user
    case assistant
}

/// A tool call (as might be returned by the agent).
struct ToolCall: Codable, Equatable {
    let id: String
    let type: String // e.g., "function"
    let function: FunctionCall
    
    struct FunctionCall: Codable, Equatable {
        let name: String
        let arguments: String // JSON string of arguments
    }
}

/// Usage information (token counts, etc.).
struct UsageInfo: Codable, Equatable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
}

/// A unified chat event that can be displayed in the chat view.
enum UnifiedChatEvent: Equatable {
    case token(String) // A piece of the assistant's message
    case toolCall(ToolCall)
    case toolResult(String) // Result of a tool call (could be more structured, but for simplicity we use String)
    case reasoning(String) // A reasoning block (e.g., "thinking...")
    case streamEnd // Indicates the end of the assistant's message
    case error(String) // An error occurred
    case cancel // The stream was cancelled
    // We could also add events for device data (from OpenClaw) if needed.
}

/// A file attachment for sending in a chat.
struct Attachment: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let data: Data
    let mimeType: String
}

/// Metadata about an uploaded file.
struct FileMetadata: Identifiable, Codable, Equatable {
    let id: String
    let filename: String
    let path: String
    let mimeType: String
    let size: Int
    let isImage: Bool
}

/// A workspace or filesystem entry.
struct WorkspaceEntry: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let isDirectory: Bool
}

/// A file item in a directory listing.
struct FileItem: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let isDirectory: Bool
    let size: Int?
    let modifiedDate: Date?
}

/// A skill (for the skills catalog).
struct Skill: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let category: String
}

/// The content of a skill (markdown and linked files).
struct SkillContent: Codable, Equatable {
    let name: String
    let markdown: String
    let files: [String: String] // filename -> content (text)
}

/// Memory data (notes and user profile).
struct MemoryData: Codable, Equatable {
    let notes: [String]
    let userProfile: [String: String] // key-value pairs
}

/// A scheduled job or task.
struct Job: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let status: String // e.g., "idle", "running", "completed", "failed"
    let createdAt: Date
    let metadata: [String: String] // additional job-specific data
}

/// Information about a model.
struct ModelInfo: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let provider: String
    let contextLength: Int? // in tokens
}

/// Information about a provider (e.g., openai, anthropic, local).
struct ProviderInfo: Identifiable, Codable, Equatable {
    let id: String
    let name: String
}

/// Information about a profile (a set of settings for the agent).
struct ProfileInfo: Identifiable, Codable, Equatable {
    let id: String
    let name: String
}

/// Reasoning effort options (for Hermes).
struct ReasoningOption: Identifiable, Codable, Equatable {
    let id: String // e.g., "low", "medium", "high"
    let name: String
    let description: String
}

/// Server settings (version, etc.).
struct ServerSettings: Codable, Equatable {
    let version: String
    let botName: String
    let extra: [String: String] // any other settings
}

/// An empty response (for endpoints that return no meaningful body).
struct EmptyResponse: Codable, Equatable { }