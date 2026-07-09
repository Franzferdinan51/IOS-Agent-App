import SwiftUI

struct CronsView: View {
    @State private var crons: [CronJobSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedCron: CronJobSummary?
    @State private var searchText = ""

    private var filteredCrons: [CronJobSummary] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return crons }
        let lowered = needle.lowercased()
        return crons.filter { cron in
            cron.id.lowercased().contains(lowered)
                || cron.name.lowercased().contains(lowered)
                || cron.schedule.lowercased().contains(lowered)
                || cron.prompt.lowercased().contains(lowered)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && crons.isEmpty {
                    ProgressView("Loading cron jobs...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, crons.isEmpty {
                    ContentUnavailableView {
                        Label("Crons unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await loadCrons() } }
                    }
                } else if crons.isEmpty {
                    ContentUnavailableView {
                        Label("No Cron Jobs", systemImage: "clock")
                    } description: {
                        Text("No scheduled cron jobs configured.")
                    }
                } else {
                    List {
                        Section {
                            CronSummaryHeader(total: crons.count, running: crons.filter(\.isRunning).count)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                                .listRowBackground(Color.clear)
                        }

                        Section("Jobs") {
                            ForEach(filteredCrons) { cron in
                                Button {
                                    selectedCron = cron
                                } label: {
                                    CronRowView(cron: cron)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(BrandBackground(brand: .hermes))
                    .refreshable {
                        await loadCrons()
                    }
                }
            }
            .navigationTitle("Crons")
            .searchable(text: $searchText, prompt: "Search cron jobs by name, schedule, or prompt")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isLoading {
                        ProgressView()
                    }
                }
            }
            .sheet(item: $selectedCron) { cron in
                CronDetailView(cron: cron)
            }
        }
        .task {
            await loadCrons()
        }
    }

    private func loadCrons() async {
        isLoading = true
        errorMessage = nil
        do {
            crons = try await AuthManager.shared.backend.fetchCrons()
                .sorted {
                    let lhs = $0.nextRun ?? .distantFuture
                    let rhs = $1.nextRun ?? .distantFuture
                    if lhs == rhs { return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    return lhs < rhs
                }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct CronSummaryHeader: View {
    let total: Int
    let running: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hermes cron jobs")
                    .font(.headline)
                Text("\(total) configured · \(running) running now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct CronRowView: View {
    let cron: CronJobSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cron.name)
                        .font(.headline)
                    Text(cron.schedule)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(text: cron.isRunning ? "Running" : "Idle", color: cron.isRunning ? .green : .orange)
            }

            HStack(spacing: 12) {
                Label(cron.lastRun.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never", systemImage: "clock.arrow.circlepath")
                Label(cron.nextRun.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Unscheduled", systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let skill = cron.skill, !skill.isEmpty {
                Text(skill)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            if !cron.prompt.isEmpty {
                Text(cron.prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

private struct CronDetailView: View {
    let cron: CronJobSummary
    @Environment(\.dismiss) private var dismiss
    @State private var output = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Schedule") {
                    LabeledContent("Name", value: cron.name)
                    LabeledContent("Schedule", value: cron.schedule)
                    LabeledContent("Status", value: cron.isRunning ? "Running" : "Idle")
                    LabeledContent("Last Run", value: cron.lastRun?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    LabeledContent("Next Run", value: cron.nextRun?.formatted(date: .abbreviated, time: .shortened) ?? "Unscheduled")
                    if let skill = cron.skill, !skill.isEmpty {
                        LabeledContent("Skill", value: skill)
                    }
                }

                if !cron.prompt.isEmpty {
                    Section("Prompt") {
                        Text(cron.prompt)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Section("Recent Output") {
                    if isLoading {
                        ProgressView("Loading output...")
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else if output.isEmpty {
                        Text("No output returned for this job.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Cron")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        Task { await loadOutput() }
                    }
                    .disabled(isLoading)
                }
            }
        }
        .task {
            await loadOutput()
        }
    }

    private func loadOutput() async {
        isLoading = true
        errorMessage = nil
        do {
            output = try await AuthManager.shared.backend.fetchCronOutput(jobId: cron.id, limit: 200)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
