import SwiftUI

@main
struct DualAgentApp: App {
    @StateObject private var authManager: AuthManager? = nil
    
    var body: some Scene {
        WindowGroup {
            if let authManager = authManager {
                // We have an authenticated session, show the main app.
                MainTabView()
                    .environmentObject(authManager)
            } else {
                // Show onboarding to set up the connection.
                OnboardingView { url, authMethod, credentials in
                    // Attempt to create the backend and log in.
                    Task {
                        do {
                            let backend = try makeBackend(from: url, authMethod: authMethod)
                            let auth = AuthManager(backend: backend)
                            // Try to log in.
                            let success = await auth.login(usernameOrEmail: "", passwordOrAPIKey: credentials)
                            if success {
                                await MainActor.run {
                                    self.authManager = auth
                                }
                            } else {
                                // Handle error (we'll just print for now)
                                print("Login failed")
                            }
                        } catch {
                            print("Error creating backend: \(error)")
                        }
                    }
                }
            }
        }
    }
    
    /// Creates a backend instance based on the URL and auth method.
    /// For now, we default to Hermes if the URL contains "hermes" or if we can't determine.
    /// In a real app, we might let the user choose the backend type explicitly.
    private func makeBackend(from urlString: String, authMethod: AuthMethod) throws -> any Backend {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        // For simplicity, we'll assume Hermes unless the URL explicitly indicates OpenClaw.
        // We could add a separate setting for backend type in the onboarding.
        if urlString.lowercased().contains("openclaw") {
            return OpenClawBackend(baseURL: url)
        } else {
            return HermesBackend(baseURL: url)
        }
    }
}

/// The main tab view of the app.
struct MainTabView: View {
    var body: some View {
        TabView {
            SessionListView()
                .tabItem {
                    Label("Sessions", systemIcon: "bubble.left.and.bubble.right")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemIcon: "gear")
                }
        }
    }
}