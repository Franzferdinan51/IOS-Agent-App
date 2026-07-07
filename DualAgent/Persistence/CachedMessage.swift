import Foundation
import SwiftData

@Model
final class CachedMessage {
    @Attribute(.unique) var id: String
    var sessionId: String
    var role: String // We'll store the raw value of MessageRole
    var content: String
    var createdAt: Date
    var isStreaming: Bool
    // Note: We are not storing toolCalls and reasoning in the cached message for now.
    // If needed, we can add them as optional properties.
    
    init(id: String, sessionId: String, role: String, content: String, createdAt: Date, isStreaming: Bool = false) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
    }
}

extension CachedMessage {
    func toUnifiedMessage() -> UnifiedMessage> {
        // We need to convert the role string back to MessageRole.
        // We assume that UnifiedMessage is defined in the same module (or we import it).
        // Since we are in the same target, we can use the UnifiedMessage type.
        // However, note that we haven't defined UnifiedMessage in this file.
        // We'll have to import it or define it here. Let's assume it's available.
        // If not, we'll have to create a UnifiedMessage.swift in the Models folder.
        // For now, we'll force unwrap and hope that the role string is valid.
        return UnifiedMessage(
            id: id,
            role: MessageRole(rawValue: role) ?? .user,
            content: content,
            createdAt: createdAt,
            isStreaming: isStreaming
            // Note: toolCalls and reasoning are not set because they are not in CachedMessage.
        )
    }
}