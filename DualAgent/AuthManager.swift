import Foundation
import SwiftUI
import LocalAuthentication

/// Manages authentication and the currently active backend for DualAgent.
///
/// Auth is intentionally backend-aware — we never ask the user for an
/// "API key" or a "username" up front:
///
///   - **Hermes** signs in with a single server password (POST to
///     `/api/auth/login`). Hermes never has a username concept.
///     If the server reports `authEnabled == false`, the credential is
///     optional and we just connect.
///
///   - **OpenClaw Gateway** is reached by token, obtained from
///     `openclaw config get gateway.auth.token` on the gateway host
///     (or set via the `OPENCLAW_GATEWAY_TOKEN` env var). The token is
///     sent as a Bearer header to the gateway.
///     OpenClaw does not have an "API key" concept at the gateway layer.
///
/// The UI therefore has exactly one credential field whose label flips
/// between "Server Password" and "Gateway Token" based on the selected
/// backend. See `OnboardingViewModel.credentialLabel`.
@MainActor
final class AuthManager: ObservableObject {
    // MARK: - Singleton

    static let shared = AuthManager()

    // MARK: - Dependencies

    private let keychain = KeychainStore()

    // MARK: - Published State

    @Published private(set) var isAuthenticated: Bool = false

    /// Convenience alias for `isAuthenticated` — used by `RootView` for auth routing.
    var isLoggedIn: Bool { isAuthenticated }

    @Published private(set) var currentBackendType: BackendType = .hermes

    // MARK: - Backend

    /// The currently active backend. Use `switchBackend(to:)` to change.
    private(set) var backend: Backend

    // MARK: - Keychain Keys

    /// The selected backend type (`"hermes"` or `"openclaw"`).
    private let backendTypeKey = "dualagent_backend_type"

    /// The configured server URL (host) as a string.
    private let serverURLKey = "dualagent_server_url"

    /// Single shared credential: server password (Hermes) or gateway token (OpenClaw).
    /// Never both. Stored per-backend so switching backends prefers the right value.
    private func credentialKey(for type: BackendType) -> String {
        switch type {
        case .hermes: return "dualagent_hermes_password"
        case .openclaw: return "dualagent_openclaw_gateway_token"
        }
    }

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
        if let urlString = keychain.read(forKey: serverURLKey),
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

        // Attempt silent re-login if we already had a credential stored.
        Task {
            await attemptSilentLogin()
        }
    }

    /// Convenience initializer for previews and testing.
    init(backend: Backend) {
        self.backend = backend
        self.isAuthenticated = backend.isAuthenticated
        self.currentBackendType = backend.backendType
    }

    // MARK: - Connect

    /// Connect to a backend using the credential appropriate for it.
    ///
    /// - For Hermes: `credential` is the server password (or empty if auth is off).
    /// - For OpenClaw: `credential` is the gateway token (from
    ///   `openclaw config get gateway.auth.token`).
    ///
    /// Persists the server URL + credential so a cold relaunch can
    /// silently reconnect, then routes through the configured `Backend`
    /// (Hermes or OpenClaw).
    func connect(serverURL: String, credential: String) async throws -> Bool {
        guard let url = URL(string: serverURL), url.host != nil else {
            throw LoginError.invalidURL
        }

        // Persist selection + URL first so a crash mid-handshake still
        // leaves the new server active on next launch.
        keychain.save(currentBackendType.rawValue, forKey: backendTypeKey)
        keychain.save(serverURL, forKey: serverURLKey)
        keychain.save(credential, forKey: credentialKey(for: currentBackendType))

        // Hand the appropriate credential to the backend.
        // Hermes ignores username; OpenClaw ignores the apiKey path.
        let usernameOrEmail: String
        let passwordOrAPIKey: String
        switch currentBackendType {
        case .hermes:
            usernameOrEmail = "" // Hermes never uses a username.
            passwordOrAPIKey = credential
        case .openclaw:
            usernameOrEmail = "gateway_token"
            passwordOrAPIKey = credential
        }

        let success = try await backend.login(
            usernameOrEmail: usernameOrEmail,
            passwordOrAPIKey: passwordOrAPIKey
        )
        if !success {
            throw LoginError.invalidCredentials(currentBackendType)
        }
        isAuthenticated = true
        return true
    }

    // MARK: - Silent Login

    private func attemptSilentLogin() async {
        guard let serverURL = keychain.read(forKey: serverURLKey),
              let backendTypeRaw = keychain.read(forKey: backendTypeKey),
              let backendType = BackendType(rawValue: backendTypeRaw) else { return }

        let credential = keychain.read(forKey: credentialKey(for: backendType)) ?? ""
        // Hermes with no credential is fine when auth is off; still try — HermesBackend
        // will succeed if the server reports authEnabled == false.
        guard !credential.isEmpty || backendType == .hermes else { return }

        do {
            let usernameOrEmail: String
            let passwordOrAPIKey: String
            switch backendType {
            case .hermes:
                usernameOrEmail = ""
                passwordOrAPIKey = credential
            case .openclaw:
                usernameOrEmail = "gateway_token"
                passwordOrAPIKey = credential
            }
            let success = try await backend.login(
                usernameOrEmail: usernameOrEmail,
                passwordOrAPIKey: passwordOrAPIKey
            )
            isAuthenticated = success
            if !success {
                // Clear stale backend-side session cookie so the next explicit
                // login gets a clean attempt.
                try? await backend.logout()
            }
        } catch {
            // Silent login failed — keep the credential around for the user's
            // next explicit connect attempt; only clear on explicit logout.
        }
    }

    // MARK: - Logout

    /// Sign out. Local state is cleared synchronously so a relaunch starts
    /// at the onboarding screen; the network logout runs best-effort after.
    /// If callers need to know when the network call finished, they can
    /// wrap the call in a `Task` and `await` the result.
    @discardableResult
    func logout() async -> Bool {
        // Clear local state first — never leave a "logged out but token
        // still in memory/keychain" window where a relaunch would re-auth.
        isAuthenticated = false
        clearCredentials()
        do {
            try await backend.logout()
            return true
        } catch {
            // Already cleared locally; surface a non-blocking error if needed
            // by callers that want to show "couldn't reach server".
            return false
        }
    }

    /// Synchronous logout variant for callers that can't await (e.g. a
    /// button action). Performs only the local clear; the server-side
    /// logout fires on a detached `Task`.
    func logoutSync() {
        isAuthenticated = false
        clearCredentials()
        Task { try? await backend.logout() }
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

        // Build the new backend from the saved URL (if any) instead of always
        // resetting to defaults — the user's last server per-backend wins.
        let savedURLString = keychain.read(forKey: serverURLKey)
        let resolvedURL: URL = {
            if let s = savedURLString, let u = URL(string: s) { return u }
            return url
        }()

        let newBackend: Backend
        switch type {
        case .hermes:
            newBackend = HermesBackend(baseURL: resolvedURL)
        case .openclaw:
            newBackend = OpenClawBackend(baseURL: resolvedURL)
        }

        self.backend = newBackend
        currentBackendType = type
        keychain.save(type.rawValue, forKey: backendTypeKey)

        // We do NOT auto-reconnect on backend switch — the user will press
        // the Login button after filling the (label-changing) credential.
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
        // Keep the URL/backend choice; only drop secrets.
        keychain.delete(forKey: credentialKey(for: .hermes))
        keychain.delete(forKey: credentialKey(for: .openclaw))
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

// MARK: - LoginError

enum LoginError: LocalizedError {
    case invalidURL
    case invalidCredentials(BackendType)
    case network(String)
    case transportRefused(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid server URL (e.g. https://your-host.example)."
        case .invalidCredentials(let type):
            switch type {
            case .hermes: return "Wrong server password."
            case .openclaw: return "Wrong gateway token. Double-check `openclaw config get gateway.auth.token` on the gateway host."
            }
        case .network(let msg): return msg
        case .transportRefused(let msg): return msg
        }
    }
}
