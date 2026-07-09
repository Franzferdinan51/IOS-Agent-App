import SwiftUI

/// The main tab-based navigation shell for authenticated users.
struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var appSettings: AppSettings
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
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(AppState.Tab.settings)
        }
        .tint(appSettings.effectiveAccent.color)
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
        .onChange(of: appState.selectedTab) { _, _ in
            Haptic.selectionChanged()
        }
        #if DEBUG
        .task {
            await runDebugCreateThreadSmokeIfRequested()
            await runDebugChatSmokeIfRequested()
        }
        #endif
    }

    #if DEBUG
    private func runDebugCreateThreadSmokeIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-DASmokeCreateThread") else { return }
        guard UserDefaults.standard.bool(forKey: "debug.createThreadSmoke.hasRun") == false else { return }
        UserDefaults.standard.set(true, forKey: "debug.createThreadSmoke.hasRun")
        UserDefaults.standard.set("starting", forKey: "debug.createThreadSmoke.result")

        for _ in 0..<40 where !appState.authManager.isAuthenticated {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        guard appState.authManager.isAuthenticated else {
            UserDefaults.standard.set("not-authenticated", forKey: "debug.createThreadSmoke.result")
            return
        }

        do {
            let workspace = try await appState.authManager.backend.fetchDefaultWorkspace() ?? ""
            let model = appSettings.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
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

        guard appState.authManager.isAuthenticated else {
            UserDefaults.standard.set("not-authenticated", forKey: "debug.chatSmoke.result")
            print("DUALAGENT_SMOKE_CHAT not-authenticated")
            return
        }

        do {
            let sessions = try await appState.authManager.backend.fetchSessions()
            let session = sessions.first(where: { !$0.isReadOnly }) ?? sessions.first
            guard let session else {
                UserDefaults.standard.set("no-session", forKey: "debug.chatSmoke.result")
                print("DUALAGENT_SMOKE_CHAT no-session")
                return
            }

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
