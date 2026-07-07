import Foundation
import Combine

class OnboardingViewModel: ObservableObject {
    @Published var serverURL: String = ""
    @Published var authMethod: AuthMethod = .password
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var apiKey: String = ""
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var isAuthenticated: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Subscribe to AuthManager's authentication state
        AuthManager.shared.$isAuthenticated
            .assign(to: &$isAuthenticated)
    }
    
    func testConnection() {
        isLoading = true
        showError = false
        errorMessage = ""
        
        let credentials: [String: String]
        switch authMethod {
        case .password:
            credentials = ["username": username, "password": password]
        case .apiKey:
            credentials = ["api_key": apiKey]
        }
        
        AuthManager.shared.login(serverURL: serverURL, authMethod: authMethod, credentials: credentials) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    self?.showError = true
                }
                // On success, AuthManager.shared.isAuthenticated will be set to true
                // and the view will observe that via $isAuthenticated
            }
        }
    }
}