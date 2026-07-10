import SwiftUI

struct DefaultModelPickerView: View {
    let backend: Backend
    let currentDefaultModel: String?
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isLoading = false
    @State private var groups: [ServerModelCatalogGroup] = []
    @State private var defaultModel: String?
    @State private var customModel = ""
    @State private var selectedModel: String?
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isSavingCustom = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    searchField

                    if let saveError, !saveError.isEmpty {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    customCard
                    modelListContent
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Default Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadModels() }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            TextField("Search models", text: $searchText)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var customCard: some View {
        cardContainer(title: "Custom") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Custom model ID", text: $customModel)
                    .font(.subheadline)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Type a model ID exactly as the server expects it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                saveButton(
                    title: "Save Custom Model",
                    isLoading: isSavingCustom
                ) {
                    Task { await save(customModel, isCustom: true) }
                }
                .disabled(customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
    }

    @ViewBuilder
    private var modelListContent: some View {
        if isLoading && groups.isEmpty {
            cardContainer(title: "Models") {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading models...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let errorMessage, groups.isEmpty {
            cardContainer(title: "Models") {
                Label("Could Not Load Models", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if filteredGroups.isEmpty {
            cardContainer(title: "Models") {
                Label("No Matching Models", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                Text("Try a different model name or ID.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(filteredGroups) { group in
                cardContainer(title: group.name) {
                    VStack(spacing: 0) {
                        ForEach(Array(group.models.enumerated()), id: \.element.id) { index, model in
                            modelRow(model)
                            if index < group.models.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func modelRow(_ model: ServerModelOption) -> some View {
        Button {
            Task { await save(model.id) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                    if !model.id.isEmpty && model.id != model.displayName {
                        Text(model.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    }
                }

                Spacer(minLength: 12)

                if isSaving && selectedModel == model.id {
                    ProgressView()
                } else if model.id == defaultModel || model.id == selectedModel {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func cardContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func saveButton(title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isLoading ? Color.gray : Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var filteredGroups: [ServerModelCatalogGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return groups }

        return groups.compactMap { group in
            let matchingModels = group.models.filter { model in
                model.displayName.lowercased().contains(query)
                    || model.id.lowercased().contains(query)
                    || group.name.lowercased().contains(query)
            }
            guard !matchingModels.isEmpty else { return nil }
            return ServerModelCatalogGroup(
                id: group.id,
                name: group.name,
                providerID: group.providerID,
                models: matchingModels,
                extraModels: []
            )
        }
    }

    // MARK: - Data

    private func loadModels() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let catalog = try await backend.fetchServerModelCatalog()
            defaultModel = catalog.defaultModel ?? currentDefaultModel
            groups = catalog.groups
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func save(_ model: String, isCustom: Bool = false) async {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        isSavingCustom = isCustom
        saveError = nil
        selectedModel = trimmed

        // TODO: Persist via backend.saveDefaultModel() when available
        // For now, just confirm and dismiss.
        try? await Task.sleep(nanoseconds: 300_000_000)
        onSave(trimmed)
        dismiss()

        isSaving = false
        isSavingCustom = false
    }
}
