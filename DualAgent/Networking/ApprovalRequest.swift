//
//  ApprovalRequest.swift
//  DualAgent
//
//  Pending-approval model. Shared between Hermes (REST/SSE) and OpenClaw
//  (WebSocket RPC); the transport-specific bridge code lives in the
//  backend's `fetchApprovals` / event subscription, and the inbox UI
//  consumes the same model.
//

import Foundation

/// One pending approval surfaced by the backend (tool exec requires
/// explicit permission, etc.).
struct ApprovalRequest: Identifiable, Equatable, Hashable {
    enum Kind: String, Codable, Hashable {
        case exec
        case plugin
    }

    enum Decision: String, Codable, Hashable {
        case allowOnce = "once"
        case allowSession = "session"
        case allowAlways = "always"
        case deny
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let command: String?
    let agentId: String?
    let sessionKey: String?
    let expiresAt: Date?
    let allowedDecisions: Set<Decision>
}
