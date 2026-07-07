import SwiftUI

struct CronsView: View {
    @State private var crons: [CronJobSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading cron jobs...")
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) }
                } else if crons.isEmpty {
                    ContentUnavailableView {
                        Label("No Cron Jobs", systemImage: "clock")
                    } description: { Text("No scheduled cron jobs configured.") }
                } else {
                    List(crons) { cron in
                        CronRowView(cron: cron)
                    }
                    .refreshable {
                        await loadCrons()
                    }
                }
            }
            .navigationTitle("Crons")
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
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct CronRowView: View {
    let cron: CronJobSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(cron.name).font(.headline)
                Spacer()
                Text(cron.schedule).font(.caption).foregroundStyle(.secondary)
            }
            Text("Last run: \(cron.lastRun?.formatted() ?? "Never")").font(.caption).foregroundStyle(.secondary)
            Text("Status: \(cron.isRunning ? "active" : "idle")").font(.caption).foregroundStyle(cron.isRunning ? .green : .orange)
        }
        .padding(.vertical, 4)
    }
}
