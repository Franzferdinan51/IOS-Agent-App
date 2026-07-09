import SwiftUI
import MarkdownUI

struct SkillsView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.brand) private var brand
    @State private var skills: [SkillSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSkill: SkillSummary?
    @State private var query = ""

    private var filteredSkills: [SkillSummary] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return skills }
        let needle = query.lowercased()
        return skills.filter {
            $0.name.lowercased().contains(needle)
            || $0.category.lowercased().contains(needle)
            || $0.description.lowercased().contains(needle)
            || $0.tags.joined(separator: " ").lowercased().contains(needle)
        }
    }

    private var groupedSkills: [(key: String, value: [SkillSummary])] {
        Dictionary(grouping: filteredSkills) { skill in
            skill.category.isEmpty ? "General" : skill.category
        }
        .map { ($0.key, $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
        .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && skills.isEmpty {
                    ProgressView("Loading skills...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, skills.isEmpty {
                    ContentUnavailableView {
                        Label("Skills unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await loadSkills() }
                        }
                    }
                } else if filteredSkills.isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "No Skills" : "No Matches", systemImage: "star")
                    } description: {
                        Text(query.isEmpty ? "No skills were returned by Hermes." : "Try a different search term.")
                    }
                } else {
                    List {
                        Section {
                            SkillsSummaryHeader(totalSkills: skills.count, visibleSkills: filteredSkills.count)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                                .listRowBackground(Color.clear)
                        }

                        ForEach(groupedSkills, id: \.key) { category, items in
                            Section(category) {
                                ForEach(items) { skill in
                                    Button {
                                        selectedSkill = skill
                                    } label: {
                                        SkillRowView(skill: skill)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(BrandBackground(brand: brand))
                    .refreshable {
                        await refresh()
                    }
                }
            }
            .navigationTitle("Skills")
            .searchable(text: $query, prompt: "Search skills, categories, or tags")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isLoading {
                        ProgressView()
                    }
                }
            }
            .sheet(item: $selectedSkill) { skill in
                SkillDetailView(skill: skill)
            }
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
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Pull-to-refresh entry point. Mirrors the SessionListViewModel `refresh()`
    /// pattern so the on-disk API surface stays consistent across tabs.
    func refresh() async {
        await loadSkills()
    }
}

private struct SkillsSummaryHeader: View {
    let totalSkills: Int
    let visibleSkills: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hermes skill library")
                    .font(.headline)
                Text("Showing \(visibleSkills) of \(totalSkills) skills")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct SkillRowView: View {
    let skill: SkillSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if !skill.category.isEmpty {
                        HStack(spacing: 6) {
                            Theme.BrandPill(
                                brand: (skill.category.lowercased().contains("openclaw") ? .openclaw : .hermes),
                                title: skill.category,
                                symbol: "tag"
                            )
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(skill.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if !skill.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(skill.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct SkillDetailView: View {
    let skill: SkillSummary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brand) private var brand
    @State private var content: SkillContent?
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// Backend-agnostic heuristic: if the content starts with a `#` or contains
    /// `##`, we render it as Markdown via the upstream `MarkdownUI` dep
    /// (`swift-markdown-ui`). Otherwise plain monospaced is enough.
    private var contentLooksMarkdown: Bool {
        guard let body = content?.content else { return false }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { return true }
        if body.contains("\n## ") { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && content == nil {
                    ProgressView("Loading skill...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Skill unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") {
                            Task { await loadContent() }
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Image(systemName: "sparkles")
                                        .font(.title2)
                                        .foregroundStyle(brand.primary)
                                    Text(skill.name)
                                        .font(.title2.bold())
                                }
                                Text(skill.description)
                                    .foregroundStyle(.secondary)
                                if !skill.tags.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            ForEach(skill.tags, id: \.self) { tag in
                                                Text(tag)
                                                    .font(.caption.weight(.medium))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(brand.primary.opacity(0.12), in: Capsule())
                                                    .foregroundStyle(brand.primary)
                                            }
                                        }
                                    }
                                }
                            }

                            if let content {
                                VStack(alignment: .leading, spacing: 10) {
                                    if let linkedFiles = content.linkedFiles, !linkedFiles.isEmpty {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Linked files")
                                                .font(.headline)
                                            ForEach(linkedFiles, id: \.self) { file in
                                                Label(file, systemImage: "doc.text")
                                                    .font(.caption.monospaced())
                                                    .foregroundStyle(.secondary)
                                                    .textSelection(.enabled)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }

                                    // Render as Markdown when the body looks like it,
                                    // otherwise fall back to a clean monospaced surface.
                                    Group {
                                        if contentLooksMarkdown {
                                            MarkdownView(content: .string(content.content))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(14)
                                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                                .textSelection(.enabled)
                                        } else {
                                            Text(content.content)
                                                .font(.system(.body, design: .monospaced))
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(14)
                                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let body = content?.content {
                            UIPasteboard.general.string = body
                            Haptic.tap()
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(content?.content.isEmpty ?? true)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await loadContent()
        }
    }

    private func loadContent() async {
        isLoading = true
        errorMessage = nil
        do {
            content = try await AuthManager.shared.backend.fetchSkillContent(name: skill.name)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// Thin wrapper around `swift-markdown-ui`'s `Markdown` view so callers don't
/// need to import the package directly. Renders inline Markdown with a brand-
/// tinted link / emphasis style.
private struct MarkdownView: View {
    let content: MarkdownContent

    enum MarkdownContent {
        case string(String)
    }

    var body: some View {
        switch content {
        case .string(let s):
            Markdown(s)
                .markdownTheme(.basic)
                .textSelection(.enabled)
        }
    }
}
