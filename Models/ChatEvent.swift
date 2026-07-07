//
//  ChatEvent.swift
//  DualAgent
//
//  Created by Hermes Agent on 2026-07-06.
//

import Foundation

/// Represents a single event in a chat stream from either Hermes or OpenClaw backend.
enum ChatEvent: Equatable {
    case token(String)
    case toolCall(ToolCall)
    case toolResult(ToolResult)
    case reasoning(String)
    case streamEnd
    case error(String)
    case cancel
    case heartbeat
    
    struct ToolCall: Equatable {
        let id: String
        let name: String
        let arguments: [String: Any]
    }
    
    struct ToolResult: Equatable {
        let toolCallId: String
        let result: String
    }
}

extension ChatEvent: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case content
        // Tool call fields
        case id
        case name
        case arguments
        // Tool result fields
        case toolCallId
        case result
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "token":
            let content = try container.decode(String.self, forKey: .content)
            self = .token(content)
        case "tool_call":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let arguments = try container.decode([String: Any].self, forKey: .arguments)
            self = .toolCall(ToolCall(id: id, name: name, arguments: arguments))
        case "tool_result":
            let toolCallId = try container.decode(String.self, forKey: .toolCallId)
            let result = try container.decode(String.self, forKey: .result)
            self = .toolResult(ToolResult(toolCallId: toolCallId, result: result))
        case "reasoning":
            let content = try container.decode(String.self, forKey: .content)
            self = .reasoning(content)
        case "stream_end":
            self = .streamEnd
        case "error":
            let content = try container.decode(String.self, forKey: .content)
            self = .error(content)
        case "cancel":
            self = .cancel
        default:
            // Treat unknown types as heartbeat or ignore
            self = .heartbeat
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .token(let content):
            try container.encode("token", forKey: .type)
            try container.encode(content, forKey: .content)
        case .toolCall(let toolCall):
            try container.encode("tool_call", forKey: .type)
            try container.encode(toolCall.id, forKey: .id)
            try container.encode(toolCall.name, forKey: .name)
            try container.encode(toolCall.arguments, forKey: .arguments)
        case .toolResult(let toolResult):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolResult.toolCallId, forKey: .toolCallId)
            try container.encode(toolResult.result, forKey: .result)
        case .reasoning(let content):
            try container.encode("reasoning", forKey: .type)
            try container.encode(content, forKey: .content)
        case .streamEnd:
            try container.encode("stream_end", forKey: .type)
        case .error(let content):
            try container.encode("error", forKey: .type)
            try container.encode(content, forKey: .content)
        case .cancel:
            try container.encode("cancel", forKey: .type)
        case .heartbeat:
            // Heartbeats are typically just comments in SSE, not JSON
            // We'll encode as a comment type or just not encode at all
            try container.encode("heartbeat", forKey: .type)
        }
    }
}

// Helper to convert [String: Any] to Codable for ToolCall.arguments
extension [String: Any]: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if JSONSerialization.isValidJSONObject(self) {
            let data = try JSONSerialization.data(withJSONObject: self)
            try container.encode(data)
        } else {
            throw EncodingError.invalidValue(self, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Invalid JSON object"))
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        if let dict = json as? [String: Any] {
            self = dict
        } else {
            throw DecodingError.typeMismatch([String: Any].self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected [String: Any]"))
        }
    }
}

// MARK: - Supporting Models

/// Represents a file attachment for chat messages.
struct ChatAttachment: Identifiable, Codable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let data: Data
    let isImage: Bool
    
    enum CodingKeys: String, CodingKey {
        case filename
        case mimeType
        case data
        case isImage
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filename = try container.decode(String.self, forKey: .filename)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        let dataString = try container.decode(String.self, forKey: .data)
        data = Data(base64Encoded: dataString) ?? Data()
        isImage = try container.decode(Bool.self, forKey: .isImage)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filename, forKey: .filename)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encode(data.base64EncodedString(), forKey: .data)
        try container.encode(isImage, forKey: .isImage)
    }
}

/// Result of a file upload.
struct UploadResult: Codable {
    let filename: String
    let path: String
    let mimeType: String
    let size: Int
    let isImage: Bool
}

/// Represents a workspace entry (file or folder).
struct WorkspaceEntry: Identifiable, Codable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int?
    let modifiedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case name
        case path
        case isDirectory
        case size
        case modifiedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        isDirectory = try container.decode(Bool.self, forKey: .isDirectory)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        let timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .modifiedAt)
        modifiedAt = timestamp.map { Date(timeIntervalSince1970: $0) }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(isDirectory, forKey: .isDirectory)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(modifiedAt?.timeIntervalSince1970, forKey: .modifiedAt)
    }
}