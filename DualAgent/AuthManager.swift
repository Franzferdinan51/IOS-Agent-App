import Foundation
import SwiftUI
import LocalAuthentication

/// Manages authentication and the currently active backend for DualAgent.
/// Coordinates between the UI and the Backend protocol (Hermes or OpenClaw).
@MainActor
final class AuthManager: ObservableObject {
    // MARK: - Singleton

    static let shared = AuthManager()

    // MARK: - Dependencies

    private let keychain = KeychainStore()

    // MARK: - Published State

    @Published private(set) var isAuthenticated: Bool = false

    /// Convenience alias for isAuthenticated — used by RootView for auth routing.
    var isLoggedIn: Bool { isAuthenticated }
    @Published private(set) var currentBackendType: BackendType = .hermes

    // MARK: - Backend

    /// The currently active backend. Use `switchBackend(to:)` to change.
    private(set) var backend: Backend

    // MARK: - Keychain Keys

    private let serverURLKey = "dualagent_server_url"
    private let backendTypeKey = "dualagent_backend_type"
    private let usernameKey = "dualagent_username"
    private let passwordKey = "dualagent_password"
    private let apiKeyKey = "dualagent_api_key"
    private let biometricEnabledKey = "dualagent_biometric_enabled"

    // MARK: - Init

    init() {
        let savedBackendType: BackendType
        if let saved = Self.loadBackendType(), let type = BackendType(rawValue: saved) {
            savedBackendType = type
        } else {
            savedBackendType = .hermes
        }

        let savedURL: URL
        if let urlString = keychain.read(forKey: "dualagent_server_url"),
           let url = URL(string: urlString) {
            savedURL = url
        } else {
            savedURL = savedBackendType == .hermes ? AppConfig.hermesBaseURL : AppConfig.openClawBaseURL
        }

        let backend: Backend
        switch savedBackendType {
        case .hermes:
            backend = HermesBackend(baseURL: savedURL)
        case .openclaw:
            backend = OpenClawBackend(baseURL: savedURL)
        }

        self.backend = backend
        self.currentBackendType = savedBackendType
        self.isAuthenticated = backend.isAuthenticated

        // Attempt silent login if we have stored credentials
        Task {
            await attemptSilentLogin()
        }
    }

    /// Convenience initializer for previews and testing.
    init(backend: Backend) {
        self.backend = backend
        self._isAuthenticated = backend.isAuthenticated
        self.currentBackendType = backend.backendType
    }

    // MARK: - Silent Login

    private func attemptSilentLogin() async {
        guard let serverURL = keychain.read(forKey: serverURLKey),
              let backendTypeRaw = keychain.read(forKey: backendTypeKey),
              let backendType = BackendType(rawValue: backendTypeRaw) else { return }

        var credentials: [String: String] = [:]
        if backendType == .hermes {
            if let username = keychain.read(forKey: usernameKey),
               let password = keychain.read(forKey: passwordKey) {
                credentials = ["username": username, "password": password]
            }
        } else {
            if let apiKey = keychain.read(forKey: apiKeyKey) {
                credentials = ["api_key": apiKey]
            }
        }

        guard !credentials.isEmpty else { return }

        do {
            let usernameOrEmail: String
        let passwordOrAPIKey: String
        switch authMethod {
        case .password:
            usernameOrEmail = credentials["username"] ?? ""
            passwordOrAPIKey = credentials["password"] ?? ""
        case .apiKey:
            usernameOrEmail = "api_key"
            passwordOrAPIKey = credentials["api_key"] ?? ""
        }
        let success = try await backend.login(usernameOrEmail: usernameOrEmail, passwordOrAPIKey: passwordOrAPIKey)
            isAuthenticated = success
        } catch {
            // Silent login failed — clear stale credentials
            clearCredentials()
        }
    }

    // MARK: - Login (async, Backend protocol compatible)

    func login(serverURL: String, authMethod: AuthMethod, credentials: [String: String]) async throws -> Bool {
        guard let url = URL(string: serverURL) else {
            throw LoginError.invalidURL
        }

        // Save credentials for silent re-login
        keychain.save(serverURL, forKey: serverURLKey)
        keychain.save(currentBackendType.rawValue, forKey: backendTypeKey)

        switch authMethod {
        case .password:
            keychain.save(credentials["username"] ?? "", forKey: usernameKey)
            keychain.save(credentials["password"] ?? "", forKey: passwordKey)
        case .apiKey:
            keychain.save(credentials["api_key"] ?? "", forKey: apiKeyKey)
        }

        // Switch to correct backend type before login
        if currentBackendType == .hermes {
            // Already on Hermes
        } else {
            // Switching to OpenClaw for API key auth
        }

        let usernameOrEmail: String
        let passwordOrAPIKey: String
        switch authMethod {
        case .password:
            usernameOrEmail = credentials["username"] ?? ""
            passwordOrAPIKey = credentials["password"] ?? ""
        case .apiKey:
            usernameOrEmail = "api_key"
            passwordOrAPIKey = credentials["api_key"] ?? ""
        }
        let success = try await backend.login(usernameOrEmail: usernameOrEmail, passwordOrAPIKey: passwordOrAPIKey)
        isAuthenticated = success
        return success
    }

    // MARK: - Legacy callback login (for OnboardingViewModel compatibility)

    func login(
        serverURL: String,
        authMethod: AuthMethod,
        credentials: [String: String],
        completion: @escaping (Bool, Error?) -> Void
    ) {
        Task {
            do {
                let success = try await login(serverURL: serverURL, authMethod: authMethod, credentials: credentials)
                completion(success, nil)
            } catch {
                completion(false, error)
            }
        }
    }

    // MARK: - Logout

    func logout() {
        Task {
            try? await backend.logout()
            isAuthenticated = false
            clearCredentials()
        }
    }

    func logoutSync() {
        try? await backend.logout()
        isAuthenticated = false
        clearCredentials()
    }

    // MARK: - Switch Backend

    func switchBackend(to type: BackendType) {
        let url: URL
        switch type {
        case .hermes:
            url = AppConfig.hermesBaseURL
        case .openclaw:
            url = AppConfig.openClawBaseURL
        }

        // Build the new backend from stored credentials
        var credentials: [String: String] = [:]
        if type == .hermes {
            if let username = keychain.read(forKey: usernameKey),
               let password = keychain.read(forKey: passwordKey) {
                credentials = ["username": username, "password": password]
            }
        } else {
            if let apiKey = keychain.read(forKey: apiKeyKey) {
                credentials = ["api_key": apiKey]
            }
        }

        let newBackend: Backend
        switch type {
        case .hermes:
            newBackend = HermesBackend(baseURL: url)
        case .openclaw:
            newBackend = OpenClawBackend(baseURL: url)
        }

        self.backend = newBackend
        currentBackendType = type
        keychain.save(type.rawValue, forKey: backendTypeKey)

        // Re-trigger login on new backend if we have credentials
        if !credentials.isEmpty {
            Task {
                do {
                    let usernameOrEmail: String
        let passwordOrAPIKey: String
        switch authMethod {
        case .password:
            usernameOrEmail = credentials["username"] ?? ""
            passwordOrAPIKey = credentials["password"] ?? ""
        case .apiKey:
            usernameOrEmail = "api_key"
            passwordOrAPIKey = credentials["api_key"] ?? ""
        }
        let success = try await backend.login(usernameOrEmail: usernameOrEmail, passwordOrAPIKey: passwordOrAPIKey)
                    isAuthenticated = success
                } catch {
                    isAuthenticated = false
                }
            }
        }
    }

    // MARK: - Biometric Auth

    var isBiometricEnabled: Bool {
        keychain.read(forKey: biometricEnabledKey) == "true"
    }

    func enableBiometricAuth(_ enabled: Bool) {
        keychain.save(enabled ? "true" : "false", forKey: biometricEnabledKey)
    }

    func canUseBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticateWithBiometrics(completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false, error)
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Authenticate to access DualAgent"
        ) { success, evalError in
            DispatchQueue.main.async {
                completion(success, evalError)
            }
        }
    }

    // MARK: - Private Helpers

    private func clearCredentials() {
        keychain.delete(forKey: serverURLKey)
        keychain.delete(forKey: backendTypeKey)
        keychain.delete(forKey: usernameKey)
        keychain.delete(forKey: passwordKey)
        keychain.delete(forKey: apiKeyKey)
    }

    private static func loadBackendType() -> String? {
        let store = KeychainStore()
        return store.read(forKey: "dualagent_backend_type")
    }
}

// MARK: - BackendType RawRepresentable

extension BackendType: RawRepresentable {
    public init?(rawValue: String) {
        switch rawValue {
        case "hermes": self = .hermes
        case "openclaw": self = .openclaw
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .hermes: return "hermes"
        case .openclaw: return "openclaw"
        }
    }
}

// MARK: - AuthMethod

enum AuthMethod: String, CaseIterable {
    case password = "Password"
    case apiKey = "API Key"
}

// MARK: - LoginError

enum LoginError: LocalizedError {
    case invalidURL
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .invalidCredentials: return "Invalid credentials"
        }
    }
}
