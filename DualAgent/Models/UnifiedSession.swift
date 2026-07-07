import Foundation

/// A unified session model that combines fields from both Hermes and OpenClaw sessions.
public struct UnifiedSession: Identifiable, Codable, Equatable {
    public let id: String
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date
    public let lastMessageAt: Date?
    public let isPinned: Bool
    public let isArchived: Bool
    public let projectId: String?
    public let workspace: String
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let estimatedCost: Double
    
    public init(id: String, title: String, createdAt: Date, updatedAt: Date, lastMessageAt: Date? = nil,
                isPinned: Bool = false, isArchived: Bool = false, projectId: String? = nil,
                workspace: String, model: String, inputTokens: Int, outputTokens: Int, estimatedCost: Double) {
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