//
//  UnifiedSession.swift
//  DualAgent
//
//  Created by Hermes Agent on 2026-07-06.
//

import Foundation

/// Summary of a session.
struct UnifiedSession: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let lastMessageAt: Date?
    let isPinned: Bool
    let isArchived: Bool
    let projectId: String?
    let workspace: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let estimatedCost: Double
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastMessageAt = "last_message_at"
        case isPinned = "is_pinned"
        case isArchived = "is_archived"
        case projectId = "project_id"
        case workspace
        case model
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case estimatedCost = "estimated_cost"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastMessageAt = try container.decodeIfPresent(Date.self, forKey: .lastMessageAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        workspace = try container.decode(String.self, forKey: .workspace)
        model = try container.decode(String.self, forKey: .model)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        estimatedCost = try container.decodeIfPresent(Double.self, forKey: .estimatedCost) ?? 0.0
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(lastMessageAt, forKey: .lastMessageAt)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encodeIfPresent(projectId, forKey: .projectId)
        try container.encode(workspace, forKey: .workspace)
        try container.encode(model, forKey: .model)
        try container.encode(inputTokens, forKey: .inputTokens)
        try container.encode(outputTokens, forKey: .outputTokens)
        try container.encode(estimatedCost, forKey: .estimatedCost)
    }
}