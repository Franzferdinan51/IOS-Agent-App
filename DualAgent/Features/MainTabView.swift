import SwiftUI

/// The main tab-based navigation shell for authenticated users.
struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var approvalInbox: ApprovalInboxCoordinator
    @Environment(\.brand) private var brand

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                SessionListView(authManager: appState.authManager)
            }
            .tabItem {
                Label("Sessions", systemImage: "list.bullet.rectangle")
            }
            .tag(AppState.Tab.sessions)
            NavigationStack {
                SkillsView()
            }
            .tabItem {
                Label("Skills", systemImage: "star")
            }
            .tag(AppState.Tab.skills)

            NavigationStack {
                MemoryView()
            }
            .tabItem {
                Label("Memory", systemImage: "brain")
            }
            .tag(AppState.Tab.memory)

            NavigationStack {
                CronsView()
            }
            .tabItem {
                Label("Crons", systemImage: "clock")
            }
            .tag(AppState.Tab.crons)

            NavigationStack {
                KanbanBoardView()
            }
            .tabItem {
                Label("Board", systemImage: "squares.badge.3x3")
            }
            .tag(AppState.Tab.board)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(AppState.Tab.settings)
        }
        .tint(appSettings.effectiveAccent.color)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color(.systemBackground), for: .tabBar)
        .toolbarColorScheme(.none, for: .tabBar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [brand.primary, brand.secondary],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 3)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .topTrailing) {
            // Persistent shield button — only shown when there are
            // pending approvals. Tapping opens the Inbox sheet.
            if !approvalInbox.pending.isEmpty {
                Button {
                    approvalInbox.presentedSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                        Text("\(approvalInbox.pending.count)")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.warning, in: Capsule())
                    .shadow(color: Theme.warning.opacity(0.40), radius: 6, y: 2)
                }
                .padding(.top, 8)
                .padding(.trailing, 16)
            }
        }
        .sheet(isPresented: $approvalInbox.presentedSheet) {
            ApprovalInboxView(coordinator: approvalInbox)
                .environment(\.brand, brand)
        }
        .onChange(of: appState.selectedTab) { _, _ in
            Haptic.selectionChanged()
        }
        #if DEBUG
        .task {
            // If the env explicitly requests a different backend than what's
            // saved, switch to it + re-authenticate. This lets us test
            // OpenClaw without manually logging out first.
            await switchBackendIfRequested()
            await runDebugCreateThreadSmokeIfRequested()
            await runDebugChatSmokeIfRequested()
        }
        #endif
    }

    // MARK: - Debug Backend Switch

    /// If `DA_BACKEND` env/arg is set to "openclaw" but the current backend
    /// is Hermes, switch + re-auth using the env-provided credential.
    private func switchBackendIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments
        func value(forKey key: String) -> String? {
            if let v = env[key], !v.isEmpty { return v }
            if let i = args.firstIndex(of: key), i + 1 < args.count {
                return args[i + 1]
            }
            return nil
        }
        guard let requested = value(forKey: "-DABackend") ?? value(forKey: "DA_BACKEND") else { return }
        let wantsOpenClaw = requested.lowercased() == "openclaw"

        guard wantsOpenClaw, appState.authManager.currentBackendType != .openclaw else { return }
        print("DUALAGENT_BACKEND_SWITCH switching to openclaw")

        let url = value(forKey: "-DAServerURL") ?? value(forKey: "DA_SERVER_URL") ?? "http://127.0.0.1:18790"
        let credential = value(forKey: "-DACredential") ?? value(forKey: "DA_CREDENTIAL") ?? ""

        appState.authManager.switchBackend(to: .openclaw)
        do {
            let ok = try await appState.authManager.connect(serverURL: url, credential: credential)
            print("DUALAGENT_BACKEND_SWITCH result=\(ok)")
        } catch {
            print("DUALAGENT_BACKEND_SWITCH failed: \(error.localizedDescription)")
        }
    }

    #if DEBUG
    private func resolveDebugModel() async throws -> String {
        let saved = appSettings.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let models = (try? await appState.authManager.backend.fetchModels()) ?? []
        let knownBrokenDisplayNames = ["MiniMax-M2.7"]
        if !saved.isEmpty, !knownBrokenDisplayNames.contains(saved), models.isEmpty || models.contains(saved) {
            return saved
        }
        let preferred = ["@minimax:MiniMax-M3", "MiniMax-Mix", "@minimax:MiniMax-M2.7", "MiniMax-M3"]
        if let match = preferred.first(where: { models.contains($0) }) {
            appSettings.setDefaultModel(match)
            return match
        }
        if let first = models.first(where: { !knownBrokenDisplayNames.contains($0) }) {
            appSettings.setDefaultModel(first)
            return first
        }
        return "@minimax:MiniMax-M3"
    }

    private func ensureDebugSmokeAuthenticated() async -> Bool {
        if appState.authManager.isAuthenticated { return true }
        do {
            let env = ProcessInfo.processInfo.environment
            let credential = env["DA_SMOKE_HERMES_PASSWORD"] ?? env["HERMES_WEBUI_PASSWORD"] ?? ""
            return try await appState.authManager.connect(
                serverURL: AppConfig.hermesBaseURL.absoluteString,
                credential: credential
            )
        } catch {
            print("DUALAGENT_SMOKE_AUTH exception \(error.localizedDescription)")
            return false
        }
    }

    private func runDebugCreateThreadSmokeIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-DASmokeCreateThread") else { return }
        guard UserDefaults.standard.bool(forKey: "debug.createThreadSmoke.hasRun") == false else { return }
        UserDefaults.standard.set(true, forKey: "debug.createThreadSmoke.hasRun")
        UserDefaults.standard.set("starting", forKey: "debug.createThreadSmoke.result")

        for _ in 0..<40 where !appState.authManager.isAuthenticated {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        guard await ensureDebugSmokeAuthenticated() else {
            UserDefaults.standard.set("not-authenticated", forKey: "debug.createThreadSmoke.result")
            return
        }

        do {
            let workspace = try await appState.authManager.backend.fetchDefaultWorkspace() ?? ""
            let model = try await resolveDebugModel()
            guard !workspace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                UserDefaults.standard.set("missing-workspace", forKey: "debug.createThreadSmoke.result")
                return
            }
            guard !model.isEmpty else {
                UserDefaults.standard.set("missing-model", forKey: "debug.createThreadSmoke.result")
                return
            }
            let session = try await appState.authManager.backend.createSession(
                workspace: workspace,
                model: model,
                profile: nil
            )
            let result = "created:\(session.id):\(session.model):\(session.workspace)"
            UserDefaults.standard.set(result, forKey: "debug.createThreadSmoke.result")
            print("DUALAGENT_SMOKE_CREATE_THREAD \(result)")
        } catch {
            UserDefaults.standard.set("exception:\(error.localizedDescription)", forKey: "debug.createThreadSmoke.result")
            print("DUALAGENT_SMOKE_CREATE_THREAD exception \(error.localizedDescription)")
        }
    }

    private func runDebugChatSmokeIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-DASmokeChat") else { return }
        guard UserDefaults.standard.bool(forKey: "debug.chatSmoke.hasRun") == false else { return }
        UserDefaults.standard.set(true, forKey: "debug.chatSmoke.hasRun")
        UserDefaults.standard.set("starting", forKey: "debug.chatSmoke.result")
        print("DUALAGENT_SMOKE_CHAT starting")

        for _ in 0..<40 where !appState.authManager.isAuthenticated {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        guard await ensureDebugSmokeAuthenticated() else {
            UserDefaults.standard.set("not-authenticated", forKey: "debug.chatSmoke.result")
            print("DUALAGENT_SMOKE_CHAT not-authenticated")
            return
        }

        do {
            let workspace = try await appState.authManager.backend.fetchDefaultWorkspace() ?? ""
            let model = try await resolveDebugModel()
            guard !workspace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                UserDefaults.standard.set("missing-workspace", forKey: "debug.chatSmoke.result")
                print("DUALAGENT_SMOKE_CHAT missing-workspace")
                return
            }
            let session = try await appState.authManager.backend.createSession(workspace: workspace, model: model, profile: nil)
            print("DUALAGENT_SMOKE_CHAT session=\(session.id) model=\(session.model) workspace=\(session.workspace)")

            let viewModel = ChatViewModel(backend: appState.authManager.backend, sessionId: session.id, session: session)
            viewModel.messageText = "debug smoke: reply with ok"
            viewModel.sendMessage()

            for _ in 0..<120 {
                if viewModel.messages.contains(where: { $0.role == .assistant && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    let assistantText = viewModel.messages.last(where: { $0.role == .assistant })?.content ?? ""
                    let result = "assistant-response:\(assistantText.prefix(120))"
                    UserDefaults.standard.set(result, forKey: "debug.chatSmoke.result")
                    print("DUALAGENT_SMOKE_CHAT success \(result)")
                    return
                }
                if let error = viewModel.errorMessage {
                    UserDefaults.standard.set("error:\(error)", forKey: "debug.chatSmoke.result")
                    print("DUALAGENT_SMOKE_CHAT error \(error)")
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            UserDefaults.standard.set("timeout", forKey: "debug.chatSmoke.result")
            print("DUALAGENT_SMOKE_CHAT timeout messages=\(viewModel.messages.count)")
        } catch {
            UserDefaults.standard.set("exception:\(error.localizedDescription)", forKey: "debug.chatSmoke.result")
            print("DUALAGENT_SMOKE_CHAT exception \(error.localizedDescription)")
        }
    }
    #endif
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
