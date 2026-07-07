import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var serverURL: String = ""
    @Published var appVersion: String = ""
    @Published var buildNumber: String = ""
    @Published var themeSelection: ThemeSelection = .system
    @Published var defaultModel: String = ""
    @Published var availableModels: [String] = []
    @Published var isClearingCache: Bool = false
    @Published var cacheClearSuccess: Bool = false
    @Published var errorMessage: String? = nil
    
    // We'll need a reference to the backend to fetch models and clear cache.
    private let backend: any Backend
    
    init(backend: any Backend) {
        self.backend = backend
        loadSettings()
        Task {
            await fetchAppVersion()
            await fetchAvailableModels()
        }
    }
    
    /// Load settings from UserDefaults.
    func loadSettings() {
        let defaults = UserDefaults.standard
        if let url = defaults.string(forKey: "serverURL") {
            self.serverURL = url
        }
        // Theme selection: 0 = system, 1 = light, 2 = dark
        let themeIndex = defaults.integer(forKey: "themeSelection")
        self.themeSelection = ThemeSelection(rawValue: themeIndex) ?? .system
        if let model = defaults.string(forKey: "defaultModel") {
            self.defaultModel = model
        }
    }
    
    /// Save settings to UserDefaults.
    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(self.serverURL, forKey: "serverURL")
        defaults.set(self.themeSelection.rawValue, forKey: "themeSelection")
        defaults.set(self.defaultModel, forKey: "defaultModel")
    }
    
    /// Fetch the app version and build number from the bundle.
    func fetchAppVersion() async {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        await MainActor.run {
            self.appVersion = version
            self.buildNumber = build
        }
    }
    
    /// Fetch the list of available models from the backend.
    func fetchAvailableModels() async {
        do {
            let models = try await backend.getModels()
            // Extract just the model names or IDs for display.
            let modelNames = models.map { $0.id } // Assuming $0.id is the model identifier.
            await MainActor.run {
                self.availableModels = modelNames
                // If we don't have a default model set, set the first one.
                if self.defaultModel.isEmpty, let first = modelNames.first {
                    self.defaultModel = first
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load models: \(error.localizedDescription)"
            }
        }
    }
    
    /// Clear the cache (SwiftData and any other caches).
    func clearCache() async {
        await MainActor.run {
            self.isClearingCache = true
            self.cacheClearSuccess = false
            self.errorMessage = nil
        }
        
        // TODO: Implement actual cache clearing (SwiftData context reset, etc.)
        // For now, we'll just simulate.
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        await MainActor.run {
            self.isClearingCache = false
            self.cacheClearSuccess = true
        }
    }
    
    /// Save the selected default model to the backend (if supported).
    func saveDefaultModel() async {
        do {
            try await backend.saveDefaultModel(model: self.defaultModel)
            await MainActor.run {
                self.saveSettings()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to save default model: \(error.localizedDescription)"
            }
        }
    }
}

enum ThemeSelection: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2
    
    var id: Int { self.rawValue }
    
    var name: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}