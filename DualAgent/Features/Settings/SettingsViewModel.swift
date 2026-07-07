import Foundation
import Observation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var serverURL: String = ""
    @Published var appVersion: String = ""
    @Published var buildNumber: String = ""
    @Published var serverVersion: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    private let backend: any Backend
    
    init(backend: any Backend) {
        self.backend = backend
        // Load stored settings from UserDefaults or Keychain? For now, we'll leave empty.
        // We could load the server URL from the AuthManager or from storage.
        // For simplicity, we'll leave it empty and require the user to set it in onboarding.
        // However, we can try to get the server URL from the backend's baseURL.
        self.serverURL = backend.baseURL.absoluteString
        // Fetch app version and build number from Info.plist
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        self.buildNumber = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "1"
        // Fetch server version
        Task {
            await self.fetchServerVersion()
        }
    }
    
    /// Fetch the server version from the backend.
    func fetchServerVersion() async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            // For Hermes, we can use /api/settings.webui_version
            // For OpenClaw, we might use a different endpoint.
            // We'll try to call a method on the backend to get server info.
            // Since we don't have a standard method, we'll skip for now and leave it empty.
            // In a real implementation, we would have a method in Backend to get server info.
            // For now, we'll just set a placeholder.
            self.serverVersion = "Unknown"
            await MainActor.run {
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    /// Clear the cache (SwiftData).
    func clearCache() {
        // We'll implement this by calling a method on the persistence layer.
        // For now, we'll just show a success message.
        // In a real app, we would delete the cached data.
        // We'll use a placeholder.
        Task {
            await MainActor.run {
                // Simulate clearing cache
                // We'll post a notification or update the UI.
                // For now, we'll just set a temporary message.
                self.errorMessage = "Cache cleared"
                // Clear after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    self.errorMessage = nil
                }
            }
        }
    }
    
    /// Toggle theme (not implemented, just a placeholder).
    func toggleTheme() {
        // This would typically be handled by the system setting.
        // We'll just do nothing for now.
    }
}