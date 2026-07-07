import SwiftUI

struct SkillsView: View {
    @State private var skills: [SkillSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading skills...")
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) }
                } else if skills.isEmpty {
                    ContentUnavailableView {
                        Label("No Skills", systemImage: "star")
                    } description: { Text("No skills available. Configure your backend to load skills.") }
                } else {
                    List(skills) { skill in
                        SkillRowView(skill: skill)
                    }
                    .refreshable {
                        await loadSkills()
                    }
                }
            }
            .navigationTitle("Skills")
        }
        .task {
            await loadSkills()
        }
    }

    private func loadSkills() async {
        isLoading = true
        errorMessage = nil
        do {
            skills = try await AuthManager.shared.backend.fetchSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct SkillRowView: View {
    let skill: SkillSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(skill.name).font(.headline)
            Text(skill.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            if !skill.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(skill.tags, id: \.self) { tag in
                            Text(tag).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
