import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DualAgentLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgentRunLiveActivityWidget()
    }
}

struct AgentRunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentRunActivityAttributes.self) { context in
            AgentRunLockScreenView(context: context)
                .activityBackgroundTint(AgentRunLiveActivityTheme.background)
                .activitySystemActionForegroundColor(AgentRunLiveActivityTheme.primaryText)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AgentRunIslandBadge(status: context.state.status)
                        .padding(.leading, 18)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AgentRunIslandStatusView(state: context.state)
                        .padding(.trailing, 18)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AgentRunExpandedIslandBottomView(state: context.state)
                }
            } compactLeading: {
                AgentRunIslandCompactMark(status: context.state.status)
            } compactTrailing: {
                Text(context.state.status.compactTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AgentRunStatusStyle.color(for: context.state.status))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
            } minimal: {
                AgentRunIslandCompactMark(status: context.state.status)
            }
            .keylineTint(AgentRunStatusStyle.color(for: context.state.status))
        }
    }
}

private struct AgentRunExpandedIslandBottomView: View {
    let state: AgentRunActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AgentRunProgressRail(status: state.status)
            Text(state.responseExcerpt.isEmpty ? state.currentActivity : state.responseExcerpt)
                .font(.caption2)
                .foregroundStyle(AgentRunLiveActivityTheme.secondaryText)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

private struct AgentRunLockScreenView: View {
    let context: ActivityViewContext<AgentRunActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            activityProgressRow(progressWidth: 112)
            transcriptPanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var activityText: String {
        if let errorSummary = context.state.errorSummary, !errorSummary.isEmpty {
            return errorSummary
        }
        return context.state.currentActivity
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            AgentRunStatusDot(status: context.state.status, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("DualAgent")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AgentRunLiveActivityTheme.secondaryText)
                    .textCase(.uppercase)
                Text(context.state.sessionTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AgentRunLiveActivityTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.82)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            AgentRunTimerPill(state: context.state)
        }
    }

    private func activityProgressRow(progressWidth: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(activityText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AgentRunLiveActivityTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .layoutPriority(1)
            Spacer(minLength: 8)
            AgentRunProgressRail(status: context.state.status)
                .frame(width: progressWidth)
        }
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(excerptText)
                .font(.caption)
                .foregroundStyle(AgentRunLiveActivityTheme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AgentRunStatusStyle.color(for: context.state.status).opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AgentRunLiveActivityTheme.stroke, lineWidth: 1))
    }

    private var excerptText: String {
        if !context.state.responseExcerpt.isEmpty { return context.state.responseExcerpt }
        if context.state.isFinal { return "Response is ready to review." }
        return "Waiting for the next agent update."
    }
}

private struct AgentRunIslandBadge: View {
    let status: AgentRunActivityStatus
    var body: some View {
        HStack(spacing: 6) {
            AgentRunStatusDot(status: status)
            Text("DualAgent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AgentRunLiveActivityTheme.primaryText)
                .lineLimit(1)
        }
    }
}

private struct AgentRunIslandStatusView: View {
    let state: AgentRunActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(state.status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AgentRunStatusStyle.color(for: state.status))
                .lineLimit(1)
            if state.isFinal {
                Text("Ready")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AgentRunLiveActivityTheme.secondaryText)
            } else {
                HStack(spacing: 3) {
                    Circle()
                        .fill(AgentRunLiveActivityTheme.liveDot)
                        .frame(width: 4, height: 4)
                    AgentRunElapsedTimerText(startedAt: state.startedAt, alignment: .trailing)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(AgentRunLiveActivityTheme.secondaryText)
            }
        }
    }
}

private struct AgentRunIslandCompactMark: View {
    let status: AgentRunActivityStatus
    var body: some View {
        ZStack {
            Circle().fill(AgentRunStatusStyle.color(for: status).opacity(0.25))
            Image(systemName: AgentRunStatusStyle.symbolName(for: status))
                .font(.caption2.weight(.bold))
                .foregroundStyle(AgentRunStatusStyle.color(for: status))
        }
        .frame(width: 22, height: 22)
    }
}

private struct AgentRunStatusDot: View {
    let status: AgentRunActivityStatus
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: AgentRunStatusStyle.symbolName(for: status))
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(AgentRunStatusStyle.color(for: status))
            .frame(width: size, height: size)
            .background(AgentRunStatusStyle.color(for: status).opacity(0.18), in: Circle())
            .overlay(Circle().stroke(AgentRunStatusStyle.color(for: status).opacity(0.36), lineWidth: 1))
    }
}

private struct AgentRunProgressRail: View {
    let status: AgentRunActivityStatus
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(AgentRunLiveActivityTheme.railBackground)
                Capsule(style: .continuous)
                    .fill(AgentRunStatusStyle.color(for: status))
                    .frame(width: max(12, geometry.size.width * progressFraction))
            }
        }
        .frame(height: 6)
    }

    private var progressFraction: CGFloat {
        switch status {
        case .starting: 0.14
        case .thinking: 0.3
        case .usingTool: 0.52
        case .responding: 0.78
        case .complete, .failed, .cancelled: 1
        }
    }
}

private struct AgentRunTimerPill: View {
    let state: AgentRunActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(state.isFinal ? AgentRunStatusStyle.color(for: state.status) : AgentRunLiveActivityTheme.liveDot)
                .frame(width: 5, height: 5)
            if state.isFinal {
                Text("Done")
            } else {
                AgentRunElapsedTimerText(startedAt: state.startedAt, alignment: .center)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(AgentRunLiveActivityTheme.secondaryText)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: 62, alignment: .center)
        .background(AgentRunLiveActivityTheme.pillBackground, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(AgentRunLiveActivityTheme.stroke, lineWidth: 1))
    }
}

private struct AgentRunElapsedTimerText: View {
    let startedAt: Date
    var alignment: TextAlignment = .trailing
    private static let maxDisplayInterval: TimeInterval = 99 * 60 + 59

    var body: some View {
        Text(timerInterval: startedAt...startedAt.addingTimeInterval(Self.maxDisplayInterval), countsDown: false, showsHours: false)
            .monospacedDigit()
            .multilineTextAlignment(alignment)
            .lineLimit(1)
    }
}

private enum AgentRunLiveActivityTheme {
    static let background = Color(red: 0.025, green: 0.028, blue: 0.038)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.68)
    static let stroke = Color.white.opacity(0.13)
    static let pillBackground = Color.white.opacity(0.08)
    static let railBackground = Color.white.opacity(0.14)
    static let liveDot = Color(red: 0.35, green: 0.95, blue: 0.7)
}

private enum AgentRunStatusStyle {
    static func color(for status: AgentRunActivityStatus) -> Color {
        switch status {
        case .starting, .thinking, .responding:
            Color(red: 1.0, green: 0.82, blue: 0.18)
        case .usingTool:
            Color(red: 0.50, green: 0.72, blue: 1.0)
        case .complete:
            Color(red: 0.35, green: 0.95, blue: 0.55)
        case .failed:
            Color(red: 1.0, green: 0.32, blue: 0.32)
        case .cancelled:
            Color.white.opacity(0.56)
        }
    }

    static func symbolName(for status: AgentRunActivityStatus) -> String {
        switch status {
        case .starting: "sparkle"
        case .thinking: "brain.head.profile"
        case .usingTool: "wrench.and.screwdriver"
        case .responding: "text.bubble"
        case .complete: "checkmark"
        case .failed: "exclamationmark"
        case .cancelled: "xmark"
        }
    }
}
