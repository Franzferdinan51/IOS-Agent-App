import SwiftUI

struct MemoryView: View {
    @Environment(\.brand) private var brand
    @State private var memoryNotes: String = ""
    @State private var memoryUserProfile: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var noteLines: [String] {
        memoryNotes
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var userLines: [String] {
        memoryUserProfile
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && memoryNotes.isEmpty && memoryUserProfile.isEmpty {
                    ProgressView("Loading memory...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, memoryNotes.isEmpty && memoryUserProfile.isEmpty {
                    ContentUnavailableView {
                        Label("Memory unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await loadMemory() } }
                    }
                } else {
                    List {
                        Section {
                            MemoryOverviewCard(userCount: userLines.count, memoryCount: noteLines.count)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                                .listRowBackground(Color.clear)
                        }

                        Section("User Profile") {
                            if userLines.isEmpty {
                                Text("No user profile data")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(userLines, id: \.self) { line in
                                    MemoryLineView(line: line, symbol: "person.text.rectangle")
                                }
                            }
                        }

                        Section("Memory Notes") {
                            if noteLines.isEmpty {
                                Text("No memory notes")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(noteLines, id: \.self) { line in
                                    MemoryLineView(line: line, symbol: "brain.head.profile")
                                }
                            }
                        }

                        Section("Raw") {
                            if !memoryUserProfile.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("User")
                                        .font(.headline)
                                    Text(memoryUserProfile)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 6)
                            }

                            if !memoryNotes.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Memory")
                                        .font(.headline)
                                    Text(memoryNotes)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(BrandBackground(brand: brand))
                    .refreshable {
                        await loadMemory()
                    }
                }
            }
            .navigationTitle("Memory")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isLoading {
                        ProgressView()
                    }
                }
            }
        }
        .task {
            await loadMemory()
        }
    }

    private func loadMemory() async {
        isLoading = true
        errorMessage = nil
        do {
            let (notes, userProfile) = try await AuthManager.shared.backend.fetchMemory()
            memoryNotes = notes
            memoryUserProfile = userProfile
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct MemoryOverviewCard: View {
    let userCount: Int
    let memoryCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.title2)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hermes memory")
                    .font(.headline)
                Text("\(userCount) user facts · \(memoryCount) memory notes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct MemoryLineView: View {
    let line: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text(line)
                .font(.subheadline)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}
