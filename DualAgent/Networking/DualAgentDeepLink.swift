//
//  DualAgentDeepLink.swift
//  DualAgent
//
//  Backend-neutral deep-link routing. Mirrors Hermex's `HermesDeepLink`
//  shape (issue #337, #338, #339) but with a `dualagent://` scheme and the
//  minimum set of host-based URLs we currently route:
//    - dualagent://chat/new                  — open the New Chat composer
//    - dualagent://chat/new?voice=1          — open + auto-start dictation
//    - dualagent://chat/new?profile=<name>   — open pinned to a profile
//    - dualagent://session/<id>              — open a specific session
//
//  All routes are read-only: they navigate the UI rather than mutating data.
//  Wiring happens at the app shell via `.onOpenURL`.
//
import Foundation

enum DualAgentDeepLink {
    /// Host for the parameter-less "open the New Chat composer" deep link.
    static let newChatHost = "new-chat"

    /// Host for "open the New Chat composer *and* auto-start voice dictation".
    static let newChatVoiceHost = "new-chat-voice"

    /// Host for "open the New Chat composer pinned to a specific profile".
    static let newChatProfileHost = "new-chat-profile"

    /// Host for "open a specific session by id".
    static let sessionHost = "session"

    /// Query-item name carrying the profile name (for the profile variant).
    static let profileQueryItem = "profile"

    /// Query-item name indicating dictation auto-start.
    static let voiceQueryItem = "voice"

    /// Build `dualagent://new-chat`.
    static func newChatURL(scheme: String = "dualagent") -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = newChatHost
        return components.url
    }

    /// Build `dualagent://new-chat-voice?voice=1`.
    static func newChatVoiceURL(scheme: String = "dualagent") -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = newChatVoiceHost
        components.queryItems = [URLQueryItem(name: voiceQueryItem, value: "1")]
        return components.url
    }

    /// Build `dualagent://new-chat-profile?profile=<name>`. Returns nil for
    /// blank profile names so callers can pass it straight through.
    static func newChatProfileURL(profileName: String, scheme: String = "dualagent") -> URL? {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = newChatProfileHost
        components.queryItems = [URLQueryItem(name: profileQueryItem, value: trimmed)]
        return components.url
    }

    /// Build `dualagent://session?id=<sessionID>`.
    static func sessionURL(sessionID: String, scheme: String = "dualagent") -> URL? {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = sessionHost
        components.queryItems = [URLQueryItem(name: "id", value: trimmed)]
        return components.url
    }

    // MARK: - Matching

    enum Intent: Equatable {
        case newChat(autoStartVoice: Bool, profileName: String?)
        case openSession(sessionID: String)
        case unknown
    }

    static func resolve(_ url: URL, expectedScheme: String = "dualagent") -> Intent {
        guard url.scheme?.lowercased() == expectedScheme.lowercased() else { return .unknown }
        let host = url.host?.lowercased() ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch host {
        case newChatHost:
            let items = components?.queryItems ?? []
            let voice = items.first { $0.name == voiceQueryItem }?.value == "1"
            let profile = items.first { $0.name == profileQueryItem }?.value
            return .newChat(autoStartVoice: voice, profileName: profile?.isEmpty == false ? profile : nil)
        case newChatVoiceHost:
            return .newChat(autoStartVoice: true, profileName: nil)
        case newChatProfileHost:
            let profile = components?.queryItems?.first { $0.name == profileQueryItem }?.value
            let trimmed = profile?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .newChat(autoStartVoice: false, profileName: (trimmed?.isEmpty == false) ? trimmed : nil)
        case sessionHost:
            let items = components?.queryItems ?? []
            guard let id = items.first(where: { $0.name == "id" })?.value,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return .unknown }
            return .openSession(sessionID: id)
        default:
            return .unknown
        }
    }
}
