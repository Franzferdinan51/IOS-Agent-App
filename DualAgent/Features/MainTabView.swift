import SwiftUI

/// The main tab-based navigation shell for authenticated users.
struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

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
        .onChange(of: appState.selectedTab) { _, _ in
            Haptic.selectionChanged()
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
