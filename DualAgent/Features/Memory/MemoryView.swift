import SwiftUI

struct MemoryView: View {
    @State private var memoryNotes: String = ""
    @State private var memoryUserProfile: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading memory...")
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) }
                } else {
                    List {
                        Section("User Profile") {
                            if !memoryUserProfile.isEmpty {
                                Text(memoryUserProfile)
                                    .font(.body)
                            } else {
                                Text("No user profile data").foregroundStyle(.secondary)
                            }
                        }
                        Section("Notes") {
                            if !memoryNotes.isEmpty {
                                Text(memoryNotes)
                                    .font(.body)
                            } else {
                                Text("No memory notes").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Memory")
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
