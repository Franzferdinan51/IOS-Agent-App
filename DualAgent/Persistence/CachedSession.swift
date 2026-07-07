import Foundation
import SwiftData

@Model
final class CachedSession {
    @Attribute(.unique) var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var lastMessageAt: Date?
    var isPinned: Bool
    var isArchived: Bool
    var projectId: String?
    var workspace: String
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var estimatedCost: Double
    
    // Relationship to messages
    @Relationship(deleteRule: .cascade) var messages: [CachedMessage] = []
    
    init(id: String, title: String, createdAt: Date, updatedAt: Date, lastMessageAt: Date? = nil,
         isPinned: Bool = false, isArchived: Bool = false, projectId: String? = nil,
         workspace: String, model: String, inputTokens: Int = 0, outputTokens: Int = 0,
         estimatedCost: Double = 0.0) {
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

extension CachedSession {
    func toUnifiedSession() -> UnifiedSession> {
        return UnifiedSession(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMessageAt: lastMessageAt,
            isPinned: isPinned,
            isArchived: isArchived,
            projectId: projectId,
            workspace: workspace,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCost: estimatedCost
        )
    }
}