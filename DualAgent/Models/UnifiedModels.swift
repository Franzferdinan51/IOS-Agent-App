import Foundation

/// Represents the role of a message sender.
public enum MessageRole: String, Codable, CaseIterable {
    case user
    case assistant
    case system
    case tool
}

/// Represents a chat message in the unified model.
public struct UnifiedMessage: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public let role: MessageRole
    public let content: String
    public let createdAt: Date
    public var isStreaming: Bool = false
    
    // Optional fields for tool calls and reasoning
    public var toolCall: ToolCall?
    public var toolCallResult: ToolResult?
    public var reasoning: String?
    
    public init(id: String, role: MessageRole, content: String, createdAt: Date,
                isStreaming: Bool = false, toolCall: ToolCall? = nil,
                toolCallResult: ToolResult? = nil, reasoning: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.toolCall = toolCall
        self.toolCallResult = toolCallResult
        self.reasoning = reasoning
    }
}

/// Represents a tool call made by the assistant.
public struct ToolCall: Codable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let arguments: [String: String] // Simplified - in reality could be any JSON
    
    public init(id: String, name: String, arguments: [String: String]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// Represents the result of a tool execution.
public struct ToolResult: Codable, Equatable, Hashable {
    public let toolCallId: String
    public let output: String
    public let isError: Bool
    
    public init(toolCallId: String, output: String, isError: Bool = false) {
        self.toolCallId = toolCallId
        self.output = output
        self.isError = isError
    }
}

/// Represents a chat session.
public struct UnifiedSession: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date
    public let lastMessageAt: Date?
    public var isPinned: Bool
    public var isArchived: Bool
    public let projectId: String?
    public let workspace: String
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let estimatedCost: Double
    
    public init(id: String, title: String, createdAt: Date, updatedAt: Date,
                lastMessageAt: Date? = nil, isPinned: Bool = false,
                isArchived: Bool = false, projectId: String? = nil,
                workspace: String, model: String, inputTokens: Int = 0,
                outputTokens: Int = 0, estimatedCost: Double = 0.0) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessageAt = lastMessageAt
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.projectId = projectId
        self.workspace = workspace
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.estimatedCost = estimatedCost
    }
}

/// Represents a chat event received from a streaming endpoint.
public enum ChatEvent: Equatable {
    case token(String)
    case toolCall(ToolCall)
    case toolResult(ToolResult)
    case reasoning(String)
    case streamEnd
    case error(String)
    case cancelled
}

/// Represents a file attachment for chat.
public struct ChatAttachment: Identifiable, Equatable, Hashable {
    public let id: String
    public let filename: String
    public let mimeType: String
    public let data: Data
    public let isImage: Bool
    
    public init(id: String, filename: String, mimeType: String, data: Data) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.isImage = mimeType.hasPrefix("image/")
    }
}

/// Represents a workspace entry (file or folder).
public struct WorkspaceEntry: Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64?
    public let modifiedDate: Date?
    
    public init(id: String, name: String, path: String, isDirectory: Bool,
                size: Int64? = nil, modifiedDate: Date? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedDate = modifiedDate
    }
}

/// Represents a skill summary.
public struct SkillSummary: Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let category: String
    public let description: String
    
    public init(id: String, name: String, category: String, description: String) {
        self.id = id
        self.name = name
        self.category = category
        self.description = description
    }
}

/// Represents skill content (markdown and linked files).
public struct SkillContent: Equatable, Hashable {
    public let markdown: String
    public let linkedFiles: [String: String] // filename -> content
    
    public init(markdown: String, linkedFiles: [String: String] = [:]) {
        self.markdown = markdown
        self.linkedFiles = linkedFiles
    }
}

/// Represents a cron job summary.
public struct CronJobSummary: Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let schedule: String
    public let nextRun: Date?
    public let lastRun: Date?
    public let isRunning: Bool
    public let prompt: String
    public let skill: String?
    
    public init(id: String, name: String, schedule: String, nextRun: Date?,
                lastRun: Date?, isRunning: Bool, prompt: String, skill: String? = nil) {
        self.id = id
        self.name = name
        self.schedule = schedule
        self.nextRun = nextRun
        self.lastRun = lastRun
        self.isRunning = isRunning
        self.prompt = prompt
        self.skill = skill
    }
}