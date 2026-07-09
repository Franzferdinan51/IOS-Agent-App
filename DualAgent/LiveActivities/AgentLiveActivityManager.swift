import ActivityKit
import Foundation

enum AgentLiveActivityEvent: Equatable {
    case token(String)
    case reasoning(String)
    case toolStarted(name: String?)
}

@MainActor
final class AgentLiveActivityManager {
    static let shared = AgentLiveActivityManager()

    private let minimumUpdateInterval: TimeInterval
    private var activity: Activity<AgentRunActivityAttributes>?
    private var currentState: AgentRunActivityAttributes.ContentState?
    private var currentSessionID: String?
    private var currentStreamID: String?
    private var rawResponseText = ""
    private var lastSentUpdateAt: Date?
    private var pendingUpdateTask: Task<Void, Never>?

    init(minimumUpdateInterval: TimeInterval = 1.5) {
        self.minimumUpdateInterval = minimumUpdateInterval
    }

    func start(sessionID: String, sessionTitle: String, streamID: String?) {
        let normalizedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionID.isEmpty else { return }

        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil
        rawResponseText = ""
        currentSessionID = normalizedSessionID
        currentStreamID = streamID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let startedAt = Date()
        let state = AgentRunActivityStateReducer.initialState(
            sessionID: normalizedSessionID,
            sessionTitle: sessionTitle,
            startedAt: startedAt
        )
        currentState = state
        lastSentUpdateAt = nil

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            activity = nil
            return
        }

        Task { [weak self] in
            await self?.requestActivity(sessionID: normalizedSessionID, streamID: self?.currentStreamID, sessionTitle: state.sessionTitle, state: state)
        }
    }

    func update(_ event: AgentLiveActivityEvent) {
        guard currentState != nil else { return }

        switch event {
        case .token(let text):
            guard !text.isEmpty else { return }
            rawResponseText += text
            updateCurrentState(immediate: false) { state in
                AgentRunActivityStateReducer.token(rawResponseText, state: state)
            }
        case .reasoning(let text):
            updateCurrentState { state in
                AgentRunActivityStateReducer.reasoning(text, state: state)
            }
        case .toolStarted(let name):
            updateCurrentState { state in
                AgentRunActivityStateReducer.toolStarted(name: name, state: state)
            }
        }
    }

    func end(status: AgentRunActivityStatus, activity activityLine: String, errorSummary: String? = nil) {
        guard let currentState else { return }
        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil
        let finalState = AgentRunActivityStateReducer.final(status: status, activity: activityLine, state: currentState, errorSummary: errorSummary)
        self.currentState = finalState
        let endingActivity = activity
        activity = nil

        Task { [weak self, endingActivity] in
            await endingActivity?.update(ActivityContent(state: finalState, staleDate: nil))
            if status == .complete {
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            await endingActivity?.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: self?.dismissalPolicy(for: status) ?? .default)
            await MainActor.run { self?.reset() }
        }
    }

    private func requestActivity(sessionID: String, streamID: String?, sessionTitle: String, state: AgentRunActivityAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        do {
            for existing in Activity<AgentRunActivityAttributes>.activities {
                await existing.end(nil, dismissalPolicy: .immediate)
            }

            let attributes = AgentRunActivityAttributes(
                sessionID: sessionID,
                sessionTitle: sessionTitle,
                streamID: streamID,
                startedAt: state.startedAt
            )
            let requestedActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: staleDate(for: state)),
                pushType: nil
            )
            activity = requestedActivity
            lastSentUpdateAt = Date()
        } catch {
            activity = nil
        }
    }

    private func updateCurrentState(immediate: Bool = true, _ transform: (AgentRunActivityAttributes.ContentState) -> AgentRunActivityAttributes.ContentState) {
        guard let currentState else { return }
        let updatedState = transform(currentState)
        self.currentState = updatedState
        guard activity != nil else { return }
        scheduleUpdate(updatedState, immediate: immediate)
    }

    private func scheduleUpdate(_ state: AgentRunActivityAttributes.ContentState, immediate: Bool) {
        let now = Date()
        if immediate || lastSentUpdateAt == nil || now.timeIntervalSince(lastSentUpdateAt!) >= minimumUpdateInterval {
            pendingUpdateTask?.cancel()
            pendingUpdateTask = nil
            Task { [weak self] in
                await self?.sendUpdate(state)
            }
            return
        }

        guard pendingUpdateTask == nil else { return }
        let delay = max(0, minimumUpdateInterval - now.timeIntervalSince(lastSentUpdateAt!))
        pendingUpdateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                guard let self, !Task.isCancelled, let currentState = self.currentState else { return }
                self.pendingUpdateTask = nil
                Task { [weak self] in
                    await self?.sendUpdate(currentState)
                }
            }
        }
    }

    private func sendUpdate(_ state: AgentRunActivityAttributes.ContentState) async {
        guard let activity else { return }
        await activity.update(ActivityContent(state: state, staleDate: staleDate(for: state)))
        lastSentUpdateAt = Date()
    }

    private func staleDate(for state: AgentRunActivityAttributes.ContentState) -> Date? {
        state.isFinal ? nil : Date().addingTimeInterval(300)
    }

    private func dismissalPolicy(for status: AgentRunActivityStatus) -> ActivityUIDismissalPolicy {
        switch status {
        case .complete:
            .after(Date().addingTimeInterval(300))
        case .failed, .cancelled:
            .after(Date().addingTimeInterval(30))
        default:
            .default
        }
    }

    private func reset() {
        activity = nil
        currentState = nil
        currentSessionID = nil
        currentStreamID = nil
        rawResponseText = ""
        lastSentUpdateAt = nil
        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil
    }
}
