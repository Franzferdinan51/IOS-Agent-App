import SwiftUI

/// A swipeable 3-column Kanban board backed by Hermes crons.
/// Columns: Backlog (never run) | In Progress (last 5 min) | Done (older).
struct KanbanBoardView: View {
    @StateObject private var viewModel = KanbanViewModel()
    @EnvironmentObject private var connectionState: ConnectionState
    @State private var selectedTab = 0

    private let columns: [(title: String, color: Color, brand: Theme.Brand)] = [
        ("Backlog",      Theme.Brand.openclaw.primary, .openclaw),
        ("In Progress",  Theme.Brand.hermes.secondary,  .hermes),
        ("Done",         .secondary,                   .hermes),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground(brand: .openclaw)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // ConnectionStatePill — matching Sessions tab.
                    HStack {
                        ConnectionStatePill(state: connectionState)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Swipeable page TabView.
                    TabView(selection: $selectedTab) {
                        KanbanColumnView(
                            crons: viewModel.backlog,
                            isLoading: viewModel.isLoading,
                            errorMessage: viewModel.errorMessage,
                            headerTitle: "Backlog",
                            headerColor: Theme.Brand.openclaw.primary,
                            emptyMessage: "No backlogged cron jobs",
                            onRefresh: { await viewModel.refresh() },
                            onRunNow: { jobId in await viewModel.runNow(jobId: jobId) },
                            runningJobIds: viewModel.runningJobIds
                        )
                        .tag(0)

                        KanbanColumnView(
                            crons: viewModel.inProgress,
                            isLoading: viewModel.isLoading,
                            errorMessage: viewModel.errorMessage,
                            headerTitle: "In Progress",
                            headerColor: Theme.Brand.hermes.secondary,
                            emptyMessage: "No active cron jobs",
                            onRefresh: { await viewModel.refresh() },
                            onRunNow: { jobId in await viewModel.runNow(jobId: jobId) },
                            runningJobIds: viewModel.runningJobIds
                        )
                        .tag(1)

                        KanbanColumnView(
                            crons: viewModel.done,
                            isLoading: viewModel.isLoading,
                            errorMessage: viewModel.errorMessage,
                            headerTitle: "Done",
                            headerColor: .secondary,
                            emptyMessage: "No completed cron jobs",
                            onRefresh: { await viewModel.refresh() },
                            onRunNow: { jobId in await viewModel.runNow(jobId: jobId) },
                            runningJobIds: viewModel.runningJobIds
                        )
                        .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .accessibilityIdentifier("kanban.tab")

                    // Column tab switcher.
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { index in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTab = index
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(selectedTab == index ? columns[index].color : Color.clear)
                                        .frame(width: 8, height: 8)
                                    Text(columns[index].title)
                                        .font(.caption.weight(selectedTab == index ? .semibold : .regular))
                                        .foregroundStyle(selectedTab == index ? columns[index].color : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 10)
                    .background(Theme.Neutral.card)
                }
            }
            .navigationTitle("Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityIdentifier("kanban.refresh")
                }
            }
        }
        .task {
            await viewModel.refresh()
        }
    }
}

// MARK: - Column View

private struct KanbanColumnView: View {
    let crons: [CronJobSummary]
    let isLoading: Bool
    let errorMessage: String?
    let headerTitle: String
    let headerColor: Color
    let emptyMessage: String
    let onRefresh: () async -> Void
    let onRunNow: (String) async -> Void
    let runningJobIds: Set<String>

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                // Column header.
                HStack {
                    Text(headerTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(headerColor)
                    Text("(\(crons.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if isLoading && crons.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let error = errorMessage, crons.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 20)
                } else if crons.isEmpty {
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 30)
                } else {
                    ForEach(crons) { cron in
                        KanbanCardView(
                            cron: cron,
                            isRunning: runningJobIds.contains(cron.id)
                        ) {
                            Task { await onRunNow(cron.id) }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .refreshable {
            await onRefresh()
        }
    }
}
