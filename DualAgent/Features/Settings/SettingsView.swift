import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.brand) private var brand
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Theme.BrandCard(brand: brand) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(brand.gradient)
                                    .frame(width: 52, height: 52)
                                DualAgentLogoMark()
                                    .frame(width: 30, height: 30)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("DualAgent Theme")
                                    .font(.headline)
                                Text("Dark by default with \(brand.displayName) trim. Switch themes and accents here.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }

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
                    Toggle("Show response text in Live Activity", isOn: Binding(
                        get: { appSettings.showsLiveActivityResponseExcerpts },
                        set: { appSettings.setShowsLiveActivityResponseExcerpts($0) }
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

                Section("Keyboard shortcuts") {
                    ShortcutRow(symbol: "return", title: "Return", detail: "Submit the message.")
                    ShortcutRow(symbol: "shift", title: "Shift + Return", detail: "Insert a newline instead of sending.")
                    ShortcutRow(symbol: "option", title: "Option + Return", detail: "Insert a newline (Alt+Enter on hardware keyboards).")
                    ShortcutRow(symbol: "cmd", title: "⌘ + Return", detail: "Submit (iPad/Mac with hardware keyboard).")
                    ShortcutRow(symbol: "arrow.up", title: "↑", detail: "Recall the most recent sent message into an empty composer.")
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
                    LabeledContent("App Version", value: "\(viewModel.appVersion) (\(viewModel.buildNumber))")
                    LabeledContent("Backend", value: AuthManager.shared.currentBackendType == .hermes ? "Hermes" : "OpenClaw")
                    LabeledContent("Server URL", value: AuthManager.shared.backend.baseURL.host ?? "—")
                    AboutServerStatusRow()
                    Link(destination: URL(string: "mailto:support@example.com")!) {
                        Label("Report a bug", systemImage: "envelope")
                    }
                    Link(destination: URL(string: "https://github.com/Franzferdinan51/IOS-Agent-App")!) {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
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
            .scrollContentBackground(.hidden)
            .background(BrandBackground(brand: brand))
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

/// One row in the "Keyboard shortcuts" section: a small icon, the key
/// combo, and a one-line description. Backend-neutral.
private struct ShortcutRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Async-loaded row showing the live server status string, fetched once
/// via `.task` from the backend's `fetchServerStatus()` probe.
private struct AboutServerStatusRow: View {
    @State private var status: String? = nil
    @State private var loaded: Bool = false

    var body: some View {
        HStack {
            Text("Server Status")
            Spacer()
            if loaded {
                HStack(spacing: 6) {
                    Circle()
                        .fill(status == nil ? Color.gray : Color.green)
                        .frame(width: 8, height: 8)
                    Text(status ?? "Unavailable")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            status = await AuthManager.shared.backend.fetchServerStatus()
            loaded = true
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}