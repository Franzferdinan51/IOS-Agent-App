import ActivityKit
import Foundation

struct AgentRunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var sessionID: String
        var sessionTitle: String
        var status: AgentRunActivityStatus
        var currentActivity: String
        var responseExcerpt: String
        var startedAt: Date
        var updatedAt: Date
        var isFinal: Bool
        var errorSummary: String?

        init(
            sessionID: String,
            sessionTitle: String,
            status: AgentRunActivityStatus,
            currentActivity: String,
            responseExcerpt: String = "",
            startedAt: Date,
            updatedAt: Date,
            isFinal: Bool = false,
            errorSummary: String? = nil
        ) {
            self.sessionID = sessionID
            self.sessionTitle = AgentRunActivitySanitizer.sessionTitle(sessionTitle)
            self.status = status
            self.currentActivity = AgentRunActivitySanitizer.activityLine(currentActivity)
            self.responseExcerpt = AgentRunActivitySanitizer.responseExcerpt(responseExcerpt)
            self.startedAt = startedAt
            self.updatedAt = updatedAt
            self.isFinal = isFinal
            self.errorSummary = errorSummary.map(AgentRunActivitySanitizer.activityLine)
        }
    }

    var sessionID: String
    var sessionTitle: String
    var streamID: String?
    var startedAt: Date
}

enum AgentRunActivityStatus: String, Codable, Hashable, CaseIterable {
    case starting
    case thinking
    case usingTool
    case responding
    case complete
    case failed
    case cancelled

    var title: String {
        switch self {
        case .starting: "Starting"
        case .thinking: "Thinking"
        case .usingTool: "Using tool"
        case .responding: "Responding"
        case .complete: "Complete"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    var compactTitle: String {
        switch self {
        case .starting: "Start"
        case .thinking: "Think"
        case .usingTool: "Tool"
        case .responding: "Reply"
        case .complete: "Done"
        case .failed: "Fail"
        case .cancelled: "Stop"
        }
    }
}

enum AgentRunActivitySanitizer {
    static let maximumSessionTitleCharacters = 42
    static let maximumActivityCharacters = 64
    static let maximumExcerptCharacters = 140

    static func sessionTitle(_ rawValue: String) -> String {
        let normalized = normalizedSingleLine(rawValue)
        return trimmed(normalized.isEmpty ? "DualAgent chat" : normalized, limit: maximumSessionTitleCharacters)
    }

    static func activityLine(_ rawValue: String) -> String {
        trimmed(normalizedSingleLine(rawValue), limit: maximumActivityCharacters)
    }

    static func responseExcerpt(_ rawValue: String) -> String {
        trimmed(normalizedSingleLine(rawValue), limit: maximumExcerptCharacters)
    }

    static func toolLabel(_ rawValue: String?) -> String {
        guard let rawValue else { return "tool" }
        let noPathSeparators = rawValue
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init) ?? rawValue
        let words = noPathSeparators
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let normalized = normalizedSingleLine(words)
        return trimmed(normalized.isEmpty ? "tool" : normalized, limit: 28)
    }

    private static func normalizedSingleLine(_ rawValue: String) -> String {
        rawValue
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimmed(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        guard limit > 3 else { return String(value.prefix(limit)) }
        let endIndex = value.index(value.startIndex, offsetBy: limit - 3)
        return String(value[..<endIndex]) + "..."
    }
}

enum AgentRunActivityStateReducer {
    static func initialState(sessionID: String, sessionTitle: String, startedAt: Date = Date()) -> AgentRunActivityAttributes.ContentState {
        AgentRunActivityAttributes.ContentState(
            sessionID: sessionID,
            sessionTitle: sessionTitle,
            status: .starting,
            currentActivity: "Starting response",
            startedAt: startedAt,
            updatedAt: startedAt
        )
    }

    static func token(_ rawText: String, state: AgentRunActivityAttributes.ContentState, now: Date = Date()) -> AgentRunActivityAttributes.ContentState {
        let excerpt = AgentRunActivitySanitizer.responseExcerpt(rawText)
        return AgentRunActivityAttributes.ContentState(
            sessionID: state.sessionID,
            sessionTitle: state.sessionTitle,
            status: .responding,
            currentActivity: "Writing response",
            responseExcerpt: excerpt,
            startedAt: state.startedAt,
            updatedAt: now
        )
    }

    static func reasoning(_ text: String, state: AgentRunActivityAttributes.ContentState, now: Date = Date()) -> AgentRunActivityAttributes.ContentState {
        AgentRunActivityAttributes.ContentState(
            sessionID: state.sessionID,
            sessionTitle: state.sessionTitle,
            status: .thinking,
            currentActivity: text.isEmpty ? "Thinking" : "Thinking",
            responseExcerpt: state.responseExcerpt,
            startedAt: state.startedAt,
            updatedAt: now
        )
    }

    static func toolStarted(name: String?, state: AgentRunActivityAttributes.ContentState, now: Date = Date()) -> AgentRunActivityAttributes.ContentState {
        let label = AgentRunActivitySanitizer.toolLabel(name)
        return AgentRunActivityAttributes.ContentState(
            sessionID: state.sessionID,
            sessionTitle: state.sessionTitle,
            status: .usingTool,
            currentActivity: "Using \(label)",
            responseExcerpt: state.responseExcerpt,
            startedAt: state.startedAt,
            updatedAt: now
        )
    }

    static func final(status: AgentRunActivityStatus, activity: String, state: AgentRunActivityAttributes.ContentState, errorSummary: String? = nil, now: Date = Date()) -> AgentRunActivityAttributes.ContentState {
        AgentRunActivityAttributes.ContentState(
            sessionID: state.sessionID,
            sessionTitle: state.sessionTitle,
            status: status,
            currentActivity: activity,
            responseExcerpt: state.responseExcerpt,
            startedAt: state.startedAt,
            updatedAt: now,
            isFinal: true,
            errorSummary: errorSummary
        )
    }
}
