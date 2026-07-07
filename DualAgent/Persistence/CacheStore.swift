import Foundation
import SwiftData

/// The Core Data stack for the app.
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

@Model
final class CachedMessage {
    @Attribute(.unique) var id: String
    var sessionId: String
    var role: String // "user" or "assistant"
    var content: String
    var createdAt: Date
    var isStreaming: Bool = false
    var toolCalls: [String]? // JSON string of tool calls
    var reasoning: String? // Reasoning text
    
    init(id: String, sessionId: String, role: String, content: String, createdAt: Date,
         isStreaming: Bool = false, toolCalls: [String]? = nil, reasoning: String? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.toolCalls = toolCalls
        self.reasoning = reasoning
    }
}

final class CacheStore {
    static let shared = CacheStore()
    
    let container: ModelContainer
    let context: ModelContext
    
    private init() {
        do {
            let schema = Schema([CachedSession.self, CachedMessage.self])
            let configuration = ModelConfiguration("ModelContainer", isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [configuration])
            context = ModelContext(container)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    // MARK: - Session Methods
    
    func saveSession(_ session: UnifiedSession) {
        // Check if we already have this session
        let fetchDescriptor = FetchDescriptor<CachedSession>(predicate: #Predicate { $0.id == session.id })
        do {
            let existing = try context.fetch(fetchDescriptor)
            if let existing = existing.first {
                // Update existing
                existing.title = session.title
                existing.updatedAt = session.updatedAt
                existing.lastMessageAt = session.lastMessageAt
                existing.isPinned = session.isPinned
                existing.isArchived = session.isArchived
                existing.projectId = session.projectId
                existing.workspace = session.workspace
                existing.model = session.model
                existing.inputTokens = session.inputTokens
                existing.outputTokens = session.outputTokens
                existing.estimatedCost = session.estimatedCost
            } else {
                // Create new
                let cached = CachedSession(
                    id: session.id,
                    title: session.title,
                    createdAt: session.createdAt,
                    updatedAt: session.updatedAt,
                    lastMessageAt: session.lastMessageAt,
                    isPinned: session.isPinned,
                    isArchived: session.isArchived,
                    projectId: session.projectId,
                    workspace: session.workspace,
                    model: session.model,
                    inputTokens: session.inputTokens,
                    outputTokens: session.outputTokens,
                    estimatedCost: session.estimatedCost
                )
                context.insert(cached)
            }
            try context.save()
        } catch {
            print("Failed to save session: \(error)")
        }
    }
    
    func fetchSessions() -> [UnifiedSession> {
        let fetchDescriptor = FetchDescriptor<CachedSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        do {
            let cached = try context.fetch(fetchDescriptor)
            return cached.map { $0.toUnifiedSession() }
        } catch {
            print("Failed to fetch sessions: \(error)")
            return []
        }
    }
    
    func deleteSession(_ sessionId: String) {
        let fetchDescriptor = FetchDescriptor<CachedSession>(predicate: #Predicate { $0.id == sessionId })
        do {
            let results = try context.fetch(fetchDescriptor)
            for object in results {
                context.delete(object)
            }
            try context.save()
        } catch {
            print("Failed to delete session: \(error)")
        }
    }
    
    // MARK: - Message Methods
    
    func saveMessage(_ message: UnifiedMessage, forSession sessionId: String) {
        let fetchDescriptor = FetchDescriptor<CachedMessage>(predicate: #Predicate { $0.id == message.id })
        do {
            let existing = try context.fetch(fetchDescriptor)
            if let existing = existing.first {
                // Update existing
                existing.content = message.content
                existing.role = message.role.rawValue
                existing.createdAt = message.createdAt
                existing.isStreaming = message.isStreaming
                // Note: toolCalls and reasoning are not in UnifiedMessage, but we can add if needed
            } else {
                // Create new
                let cached = CachedMessage(
                    id: message.id,
                    sessionId: sessionId,
                    role: message.role.rawValue,
                    content: message.content,
                    createdAt: message.createdAt,
                    isStreaming: message.isStreaming
                    // toolCalls and reasoning would be set if available
                )
                context.insert(cached)
            }
            try context.save()
        } catch {
            print("Failed to save message: \(error)")
        }
    }
    
    func fetchMessages(forSession sessionId: String) -> [UnifiedMessage> {
        let fetchDescriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate { $0.sessionId == sessionId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        do {
            let cached = try context.fetch(fetchDescriptor)
            return cached.map { $0.toUnifiedMessage() }
        } catch {
            print("Failed to fetch messages: \(error)")
            return []
        }
    }
    
    func clearCache() {
        // Delete all objects
        let sessionFetch = FetchDescriptor<CachedSession>()
        let messageFetch = FetchDescriptor<CachedMessage>()
        do {
            let sessions = try context.fetch(sessionFetch)
            let messages = try context.fetch(messageFetch)
            for object in sessions {
                context.delete(object)
            }
            for object in messages {
                context.delete(object)
            }
            try context.save()
        } catch {
            print("Failed to clear cache: \(error)")
        }
    }
}

// MARK: - Extensions to convert between Unified and Cached models

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

extension CachedMessage {
    func toUnifiedMessage() -> UnifiedMessage> {
        return UnifiedMessage(
            id: id,
            role: MessageRole(rawValue: role) ?? .user,
            content: content,
            createdAt: createdAt,
            isStreaming: isStreaming
            // Note: toolCalls and reasoning are not in UnifiedMessage, but we can add if needed
        )
    }
}