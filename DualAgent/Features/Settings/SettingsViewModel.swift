import SwiftUI
import Foundation

class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var serverURL: String = ""
    @Published var themeSelection: String = "System"
    @Published var defaultModel: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var showError: Bool = false
    @Published var isCacheCleared: Bool = false
    
    // MARK: - AppStorage Keys
    private enum StorageKeys {
        static let serverURL = "serverURL"
        static let themeSelection = "themeSelection"
        static let defaultModel = "defaultModel"
    }
    
    // MARK: - Initialization
    init() {
        loadSettings()
    }
    
    // MARK: - Settings Management
    func loadSettings() {
        serverURL = UserDefaults.standard.string(forKey: StorageKeys.serverURL) ?? ""
        themeSelection = UserDefaults.standard.string(forKey: StorageKeys.themeSelection) ?? "System"
        defaultModel = UserDefaults.standard.string(forKey: StorageKeys.defaultModel) ?? ""
    }
    
    func saveSettings() {
        UserDefaults.standard.set(serverURL, forKey: StorageKeys.serverURL)
        UserDefaults.standard.set(themeSelection, forKey: StorageKeys.themeSelection)
        UserDefaults.standard.set(defaultModel, forKey: StorageKeys.defaultModel)
    }
    
    func clearCache() {
        isLoading = true
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.diskCapacity = 0
        URLCache.shared.memoryCapacity = 0
        URLCache.shared.removeAllCachedResponses()
        URLSession.shared.reset {
            DispatchQueue.main.async {
                self.isLoading = false
                self.isCacheCleared = true
                self.showError = false
            }
        }
        
        // Also clear any app-specific caches if needed
        // For example, if using NSCache or custom caches
        
        // Show success message temporarily
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isCacheCleared = false
        }
    }
    
    func testConnection() {
        isLoading = true
        errorMessage = ""
        showError = false
        
        guard let url = URL(string: serverURL) else {
            errorMessage = "Invalid server URL"
            isLoading = false
            showError = true
            return
        }
        
        var request = URLRequest(url: url.appendingPathComponent("/api/health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Connection failed: \(error.localizedDescription)"
                    self?.showError = true
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        self?.errorMessage = "Connection successful!"
                        self?.showError = true
                    } else {
                        self?.errorMessage = "Server returned statusCode: \(httpResponse.statusCode)"
                        self?.showError = true
                    }
                } else {
                    self?.errorMessage = "Invalid server response"
                    self?.showError = true
                }
            }
        }.resume()
    }
}