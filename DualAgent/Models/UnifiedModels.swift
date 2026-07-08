import Foundation

// MARK: - Message Role

/// Represents the role of a message sender.
public enum MessageRole: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case user
    case assistant
    case system
    case tool
}

// MARK: - Unified Session

/// A unified session model that combines fields from Hermes and OpenClaw sessions.
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
    public let modelProvider: String?
    public let inputTokens: Int
    public let outputTokens: Int
    public let estimatedCost: Double

    public init(
        id: String,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        lastMessageAt: Date? = nil,
        isPinned: Bool = false,
        isArchived: Bool = false,
        projectId: String? = nil,
        workspace: String,
        model: String,
        modelProvider: String? = nil,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        estimatedCost: Double = 0.0
    ) {
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
        self.modelProvider = modelProvider
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.estimatedCost = estimatedCost
    }
}

// MARK: - Unified Message

/// A unified message model that can represent a message from either Hermes or OpenClaw backend.
public struct UnifiedMessage: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public let role: MessageRole
    public let content: String
    public let createdAt: Date
    public var isStreaming: Bool = false

    /// Whether this message contains a reasoning block (separate from content).
    public var isReasoning: Bool = false

    /// Optional file attachments associated with this message.
    public var attachments: [ChatAttachment]?

    /// Optional tool call made by the assistant in this message.
    public var toolCall: ToolCall?

    /// Optional result returned from a tool invocation.
    public var toolCallResult: ToolResult?

    /// Optional reasoning text associated with this message.
    public var reasoning: String?

    public init(
        id: String,
        role: MessageRole,
        content: String,
        createdAt: Date,
        isStreaming: Bool = false,
        isReasoning: Bool = false,
        attachments: [ChatAttachment]? = nil,
        toolCall: ToolCall? = nil,
        toolCallResult: ToolResult? = nil,
        reasoning: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.isReasoning = isReasoning
        self.attachments = attachments
        self.toolCall = toolCall
        self.toolCallResult = toolCallResult
        self.reasoning = reasoning
    }
}

// MARK: - Tool Call / Tool Result

/// Represents a tool call made by the assistant.
public struct ToolCall: Codable, Equatable, Hashable, Sendable {
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
public struct ToolResult: Codable, Equatable, Hashable, Sendable {
    public let toolCallId: String
    public let output: String
    public let isError: Bool

    public init(toolCallId: String, output: String, isError: Bool = false) {
        self.toolCallId = toolCallId
        self.output = output
        self.isError = isError
    }
}

// MARK: - Chat Attachment

/// Represents a file attachment for chat.
public struct ChatAttachment: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let filename: String
    public let mimeType: String
    public let data: Data
    public let isImage: Bool

    public init(id: String = UUID().uuidString, filename: String, mimeType: String, data: Data) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.isImage = mimeType.hasPrefix("image/")
    }
}

// MARK: - Unified Chat Event

/// Represents a unified chat event received from a streaming endpoint.
/// Alias for source compatibility — the canonical event type is now UnifiedChatEvent.
public typealias ChatEvent = UnifiedChatEvent

/// Represents a chat event received from a streaming endpoint.
/// Use `ChatEvent` as the canonical name; `UnifiedChatEvent` is the underlying type.
/// A simple concrete error type for chat streams.
public struct ChatStreamError: Error, Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public enum UnifiedChatEvent: Equatable, Sendable {
    case token(String)
    case toolCall(ToolCall)
    case toolResult(ToolResult)
    case reasoning(String)
    case streamEnd
    case error(String)
    case cancelled

    /// Decodes a server event payload into a UnifiedChatEvent.
    /// JSON shape: {"type": "token"|"tool_call"|"tool_result"|"reasoning"|"stream_end"|"error", "data": ...}
    public static func from(json: [String: Any]) -> UnifiedChatEvent? {
        guard let type = json["type"] as? String else { return nil }
        switch type {
        case "token":
            if let s = json["data"] as? String { return .token(s) }
            return nil
        case "reasoning":
            if let s = json["data"] as? String { return .reasoning(s) }
            return nil
        case "tool_call":
            if let d = json["data"] as? [String: Any],
               let toolCall = try? ToolCall.fromDict(d) {
                return .toolCall(toolCall)
            }
            return nil
        case "tool_result":
            if let d = json["data"] as? [String: Any],
               let toolResult = try? ToolResult.fromDict(d) {
                return .toolResult(toolResult)
            }
            return nil
        case "stream_end", "end":
            return .streamEnd
        case "error":
            if let s = json["data"] as? String { return .error(s) }
            return .error("Unknown stream error")
        case "cancelled", "cancel":
            return .cancelled
        default:
            return nil
        }
    }
}

extension ToolCall {
    static func fromDict(_ d: [String: Any]) throws -> ToolCall? {
        guard let name = d["name"] as? String else { return nil }
        let id = d["id"] as? String ?? UUID().uuidString
        // arguments may be a dict or a string; try dict first, then string
        let args: [String: String]
        if let dict = d["arguments"] as? [String: Any] {
            args = dict.mapValues { String(describing: $0) }
        } else if let s = d["arguments"] as? String {
            args = ["raw": s]
        } else {
            args = [:]
        }
        return ToolCall(id: id, name: name, arguments: args)
    }
}

extension ToolResult {
    static func fromDict(_ d: [String: Any]) throws -> ToolResult? {
        let callId = d["call_id"] as? String ?? d["callId"] as? String ?? UUID().uuidString
        let output = d["output"] as? String ?? d["result"] as? String ?? ""
        return ToolResult(toolCallId: callId, output: output)
    }
}

// MARK: - Workspace Entry

/// Represents a workspace entry (file or folder).
public struct WorkspaceEntry: Identifiable, Equatable, Hashable, Codable {
    public let id: String
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64?
    public let modifiedAt: Date?

    public init(id: String = UUID().uuidString, name: String, path: String, isDirectory: Bool,
                size: Int64? = nil, modifiedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

// MARK: - Skill Summary / Skill Content

/// Represents a skill summary.
public struct SkillSummary: Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let category: String
    public let description: String
    public let tags: [String]

    public init(id: String = UUID().uuidString, name: String, category: String, description: String, tags: [String] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.description = description
        self.tags = tags
    }
}

/// Represents skill content (markdown and linked files).
public struct SkillContent: Equatable, Hashable {
    public let content: String
    public let linkedFiles: [String]?

    public init(content: String, linkedFiles: [String]? = nil) {
        self.content = content
        self.linkedFiles = linkedFiles
    }
}

/// A skill (for the skills catalog).
public struct Skill: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let description_: String  // underscore suffix to avoid collision with 'description' keyword
    public let tags: [String]

    public init(id: String, name: String, description_: String, tags: [String] = []) {
        self.id = id
        self.name = name
        self.description_ = description_
        self.tags = tags
    }
}

/// Memory data (notes, user profile, and preferences).
public struct MemoryData: Codable, Equatable {
    public let notes: [String]
    public let userProfile: [String: String]
    public let preferences: [String: String]

    public init(notes: [String], userProfile: [String: String], preferences: [String: String] = [:]) {
        self.notes = notes
        self.userProfile = userProfile
        self.preferences = preferences
    }
}

// MARK: - Cron Job Summary

/// Represents a cron job summary.
public struct CronJobSummary: Identifiable, Equatable, Hashable, Codable {
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

// MARK: - Backend Return Types

/// Result of a file upload.
public struct UploadResult: Equatable, Hashable, Codable {
    public let filename: String
    public let path: String
    public let size: Int64
    public let mimeType: String

    public init(filename: String, path: String, size: Int64, mimeType: String) {
        self.filename = filename
        self.path = path
        self.size = size
        self.mimeType = mimeType
    }
}

/// Result of reading a file (text content).
public struct FileResult: Equatable, Hashable, Codable {
    public let content: String
    public let mimeType: String
    public let size: Int64

    public init(content: String, mimeType: String, size: Int64) {
        self.content = content
        self.mimeType = mimeType
        self.size = size
    }
}

/// Result of reading a file as raw bytes.
public struct RawFileResult: Equatable, Hashable {
    public let data: Data
    public let mimeType: String
    public let size: Int64

    public init(data: Data, mimeType: String, size: Int64) {
        self.data = data
        self.mimeType = mimeType
        self.size = size
    }
}
