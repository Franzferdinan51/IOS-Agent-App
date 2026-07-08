import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: Binding(
                        get: { appSettings.theme },
                        set: { appSettings.setTheme($0) }
                    )) {
                        ForEach(AppTheme.allCases) { theme in
                            Label(theme.displayName, systemImage: theme.sfSymbol)
                                .tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Accent Color")
                            .font(.subheadline.weight(.medium))

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                            ForEach(AccentColor.presets) { accent in
                                Button {
                                    appSettings.setAccent(accent)
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(accent.color)
                                            .frame(width: 34, height: 34)
                                        if appSettings.accent == accent {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(accent.name)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Chat") {
                    Toggle("Show assistant timestamps", isOn: Binding(
                        get: { appSettings.showAssistantTimestamps },
                        set: { appSettings.setShowAssistantTimestamps($0) }
                    ))
                    Toggle("Show thinking + tool cards", isOn: Binding(
                        get: { appSettings.showThinkingAndToolCards },
                        set: { appSettings.setShowThinkingAndToolCards($0) }
                    ))
                    Toggle("Wrap code block lines", isOn: Binding(
                        get: { appSettings.wrapCodeBlockLines },
                        set: { appSettings.setWrapCodeBlockLines($0) }
                    ))
                    Toggle("Tint primary actions", isOn: Binding(
                        get: { appSettings.tintsPrimaryActions },
                        set: { appSettings.setTintsPrimaryActions($0) }
                    ))
                    Toggle("RTL chat override", isOn: Binding(
                        get: { appSettings.rtlOverrideEnabled },
                        set: { appSettings.setRTLOverride($0) }
                    ))
                }

                Section("Feedback") {
                    Toggle("Haptics", isOn: Binding(
                        get: { appSettings.hapticsEnabled },
                        set: { appSettings.setHaptics($0) }
                    ))
                    Toggle("Notify on response completion", isOn: Binding(
                        get: { appSettings.responseCompletionNotificationsEnabled },
                        set: { appSettings.setResponseCompletionNotifications($0) }
                    ))
                }

                Section("Server Connection") {
                    LabeledContent("Backend", value: AuthManager.shared.currentBackendType == .hermes ? "Hermes" : "OpenClaw")
                    TextField("Server URL", text: $viewModel.serverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    Button {
                        viewModel.testConnection()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Test Connection", systemImage: "network")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(viewModel.serverURL.isEmpty || viewModel.isLoading)
                }

                Section("Defaults") {
                    TextField("Default Model", text: Binding(
                        get: { appSettings.defaultModel },
                        set: { appSettings.setDefaultModel($0) }
                    ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Default Workspace", text: Binding(
                        get: { appSettings.defaultWorkspace },
                        set: { appSettings.setDefaultWorkspace($0) }
                    ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        Task {
                            if let workspace = try? await AuthManager.shared.backend.fetchDefaultWorkspace(),
                               !workspace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                appSettings.setDefaultWorkspace(workspace)
                            }
                        }
                    } label: {
                        Label("Use Server Workspace", systemImage: "folder.badge.gearshape")
                    }
                    .disabled(!AuthManager.shared.isAuthenticated)
                }

                Section("About") {
                    LabeledContent("App Version", value: viewModel.appVersion)
                    LabeledContent("Build", value: viewModel.buildNumber)
                    if !viewModel.serverVersion.isEmpty {
                        LabeledContent("Server", value: viewModel.serverVersion)
                    }
                }

                Section("Advanced") {
                    Button(role: .destructive) {
                        Task { try? await viewModel.clearCache() }
                    } label: {
                        Text("Clear Cache")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .navigationTitle("Settings")
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onAppear {
                viewModel.loadSettings()
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}
