import SwiftUI

/// A single cron job card for the Kanban board.
struct KanbanCardView: View {
    let cron: CronJobSummary
    let isRunning: Bool
    let onRunNow: () -> Void

    @Environment(\.brand) private var brand

    private var statusPillColor: Color {
        if cron.isRunning {
            return Color.green
        }
        if cron.lastRun == nil {
            return Theme.Brand.openclaw.primary
        }
        return .secondary
    }

    private var statusPillText: String {
        if cron.isRunning {
            return "Running"
        }
        if cron.lastRun == nil {
            return "Backlog"
        }
        return "Done"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: name + status pill.
            HStack(alignment: .top) {
                Text(cron.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer()
                Text(statusPillText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusPillColor.opacity(0.15))
                    .foregroundStyle(statusPillColor)
                    .clipShape(Capsule())
            }

            // Schedule label.
            Label(cron.schedule, systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Last run.
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                Text(cron.lastRun.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            // Skill tag, if present.
            if let skill = cron.skill, !skill.isEmpty {
                Text(skill)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(brand.primary.opacity(0.12))
                    .foregroundStyle(brand.primary)
                    .clipShape(Capsule())
            }

            // Prompt preview, if present.
            if !cron.prompt.isEmpty {
                Text(cron.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Run Now button.
            Button {
                onRunNow()
            } label: {
                HStack(spacing: 6) {
                    if isRunning {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.caption)
                    }
                    Text("Run now")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(brand.gradient)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
            .accessibilityIdentifier("kanban.runNow.\(cron.id)")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Neutral.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.Neutral.border, lineWidth: 1)
        )
        .accessibilityIdentifier("kanban.card.\(cron.id)")
    }
}
