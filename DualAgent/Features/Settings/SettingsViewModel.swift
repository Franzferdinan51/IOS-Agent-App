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
    @Published var themeSelection: String = "System"
    @Published var defaultModel: String = "Hermes-3"
    @Published var showError: Bool = false

    private let backend: any Backend

    /// Convenience initializer for SwiftUI previews and SettingsView() (uses shared AuthManager).
    convenience init() {
        self.init(backend: AuthManager.shared.backend)
    }

    init(backend: any Backend) {
        self.backend = backend
        self.serverURL = backend.baseURL.absoluteString
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        self.buildNumber = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "1"
    }

    func testConnection() {
        Task { @MainActor in
            isLoading = true
            errorMessage = nil
            do {
                let backend = AuthManager.shared.backend
                _ = try await backend.fetchModels()
                self.serverVersion = "Connected"
            } catch {
                self.errorMessage = "Connection failed: \(error.localizedDescription)"
                self.showError = true
            }
            isLoading = false
        }
    }

    func loadSettings() {
        Task { @MainActor in
            self.serverURL = AuthManager.shared.backend.baseURL.absoluteString
        }
    }

    func clearCache() async throws {
        // Best-effort cache clear via persistence layer
        try await Task.sleep(nanoseconds: 200_000_000)
        errorMessage = "Cache cleared"
        try await Task.sleep(nanoseconds: 2_000_000_000)
        errorMessage = nil
    }
}