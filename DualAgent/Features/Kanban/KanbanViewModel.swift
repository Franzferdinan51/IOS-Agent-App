import Foundation

@MainActor
final class KanbanViewModel: ObservableObject {
    @Published var backlog: [CronJobSummary] = []
    @Published var inProgress: [CronJobSummary] = []
    @Published var done: [CronJobSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var runningJobIds: Set<String> = []

    /// 5-minute window for "in progress" classification.
    private static let inProgressThreshold: TimeInterval = 5 * 60

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let crons = try await AuthManager.shared.backend.fetchCrons()
            classify(crons)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func runNow(jobId: String) async {
        runningJobIds.insert(jobId)
        defer { runningJobIds.remove(jobId) }
        do {
            _ = try await AuthManager.shared.backend.runCronNow(jobId: jobId)
            // Brief pause then refresh so the list reflects the new state.
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refresh()
        } catch {
            // Silently fail — the card-level UI handles feedback via isRunning state.
        }
    }

    private func classify(_ crons: [CronJobSummary]) {
        let now = Date()
        backlog = crons.filter { $0.lastRun == nil }
        inProgress = crons.filter { cron in
            guard let lastRun = cron.lastRun else { return false }
            return now.timeIntervalSince(lastRun) <= Self.inProgressThreshold
        }
        done = crons.filter { cron in
            guard let lastRun = cron.lastRun else { return false }
            return now.timeIntervalSince(lastRun) > Self.inProgressThreshold
        }
    }
}
